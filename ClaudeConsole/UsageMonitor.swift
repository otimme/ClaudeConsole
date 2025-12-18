//
//  UsageMonitor.swift
//  ClaudeConsole
//
//  Monitors Claude Code usage stats via background session
//

import Foundation
import Combine
import os.log

private let logger = Logger(subsystem: "com.claudeconsole", category: "UsageMonitor")

enum UsageFetchStatus {
    case idle
    case fetching
    case success
    case failed
}

struct UsageStats: Codable {
    var currentSessionTokens: Int = 0
    var dailyTokensUsed: Int = 0
    var dailyTokensLimit: Int = 0
    var weeklyTokensUsed: Int = 0
    var weeklyTokensLimit: Int = 0
    var sonnetTokensUsed: Int = 0
    var sonnetTokensLimit: Int = 100

    var dailyPercentage: Double {
        guard dailyTokensLimit > 0 else { return 0 }
        return Double(dailyTokensUsed) / Double(dailyTokensLimit) * 100
    }

    var weeklyPercentage: Double {
        guard weeklyTokensLimit > 0 else { return 0 }
        return Double(weeklyTokensUsed) / Double(weeklyTokensLimit) * 100
    }

    var sonnetPercentage: Double {
        guard sonnetTokensLimit > 0 else { return 0 }
        return Double(sonnetTokensUsed) / Double(sonnetTokensLimit) * 100
    }
}

class UsageMonitor: ObservableObject {
    @Published var usageStats = UsageStats()
    @Published var fetchStatus: UsageFetchStatus = .idle

    private var masterFD: Int32 = -1
    private var childPID: pid_t = -1
    private var outputSource: DispatchSourceRead?
    private var processMonitorSource: DispatchSourceProcess?

    // IMPORTANT: Only access outputBuffer from bufferQueue to prevent race conditions
    private var outputBuffer: String = ""

    private var pollTimer: Timer?
    private var attemptCount = 0
    private let maxAttempts = 3
    private var parseTimer: DispatchWorkItem?
    private var bufferCheckWorkItem: DispatchWorkItem?

    private var claudePath: String?

    // Serial queue for thread-safe buffer access
    private let bufferQueue = DispatchQueue(label: "com.claudeconsole.usagemonitor.buffer")

    init() {
        // Initialize on background thread to avoid view update conflicts
        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self = self else { return }

            // Find claude executable
            self.findClaudePath()

            if self.claudePath != nil {
                self.startBackgroundSession()
            }
        }
    }

    private func findClaudePath() {
        // Try to find claude using 'which' command
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/zsh")
        task.arguments = ["-l", "-c", "which claude"]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        task.standardOutput = outputPipe
        task.standardError = errorPipe

        do {
            try task.run()

            // Add timeout for waitUntilExit
            let timeoutSeconds = 5.0
            let deadline = Date().addingTimeInterval(timeoutSeconds)
            var timedOut = false

            while task.isRunning && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.1)
            }

            if task.isRunning {
                // Timeout occurred
                task.terminate()
                timedOut = true
                logger.warning("Timeout finding claude executable")
            }

            if !timedOut && task.terminationStatus == 0 {
                let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
                if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !path.isEmpty,
                   !path.contains("not found") {
                    self.claudePath = path
                    logger.info("Found claude at \(path)")
                    return
                }
            }

            // Fallback: search for claude in nvm node versions
            let nvmDir = "\(NSHomeDirectory())/.nvm/versions/node"
            if let nodeVersions = try? FileManager.default.contentsOfDirectory(atPath: nvmDir) {
                for version in nodeVersions.sorted().reversed() {
                    let claudePath = "\(nvmDir)/\(version)/bin/claude"
                    if FileManager.default.fileExists(atPath: claudePath) {
                        self.claudePath = claudePath
                        return
                    }
                }
            }
        } catch {
            logger.error("Failed to find claude: \(error.localizedDescription)")
        }
    }

    private func startBackgroundSession() {
        var masterFD: Int32 = -1
        var slaveFD: Int32 = -1
        var shouldCloseMasterFD = true // Track if we should close masterFD

        // Use defer to ensure slaveFD is always closed (parent process doesn't need it)
        defer {
            if slaveFD >= 0 {
                close(slaveFD)
            }
            // Only close masterFD if we're not using it
            if shouldCloseMasterFD && masterFD >= 0 {
                close(masterFD)
            }
        }

        guard openpty(&masterFD, &slaveFD, nil, nil, nil) == 0 else {
            logger.error("Failed to create PTY")
            return
        }

        self.masterFD = masterFD

        var fileActions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&fileActions)
        posix_spawn_file_actions_adddup2(&fileActions, slaveFD, STDIN_FILENO)
        posix_spawn_file_actions_adddup2(&fileActions, slaveFD, STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&fileActions, slaveFD, STDERR_FILENO)
        posix_spawn_file_actions_addclose(&fileActions, masterFD)
        posix_spawn_file_actions_addclose(&fileActions, slaveFD)

        guard let claudePath = self.claudePath else {
            logger.warning("Claude path not available")
            return
        }

        // Find node in the same directory as claude
        let claudeURL = URL(fileURLWithPath: claudePath)
        let nodeURL = claudeURL.deletingLastPathComponent().appendingPathComponent("node")
        let nodePath = nodeURL.path

        guard FileManager.default.fileExists(atPath: nodePath) else {
            logger.error("Node not found at \(nodePath)")
            return
        }

        logger.info("Using node at \(nodePath)")

        var pid: pid_t = 0

        // Run: node /path/to/claude
        let args: [UnsafeMutablePointer<CChar>?] = [
            strdup("node"),
            strdup(claudePath),
            nil
        ]

        // Get PATH from a login shell
        let pathTask = Process()
        pathTask.executableURL = URL(fileURLWithPath: "/bin/zsh")
        pathTask.arguments = ["-l", "-c", "echo $PATH"]
        let pathPipe = Pipe()
        pathTask.standardOutput = pathPipe

        var pathEnv = "PATH=/usr/bin:/bin:/usr/sbin:/sbin"
        do {
            try pathTask.run()

            // Add timeout for waitUntilExit
            let timeoutSeconds = 5.0
            let deadline = Date().addingTimeInterval(timeoutSeconds)
            var timedOut = false

            while pathTask.isRunning && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.1)
            }

            if pathTask.isRunning {
                // Timeout occurred
                pathTask.terminate()
                timedOut = true
                logger.warning("Timeout getting PATH, using default")
            }

            if !timedOut {
                if let pathData = try? pathPipe.fileHandleForReading.readToEnd(),
                   let path = String(data: pathData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !path.isEmpty {
                    pathEnv = "PATH=\(path)"
                    // print("UsageMonitor: Using PATH: \(path)")
                } else {
                    // print("UsageMonitor: Failed to get PATH, using default")
                }
            }
        } catch {
            // print("UsageMonitor: Failed to get PATH: \(error)")
        }

        var env: [UnsafeMutablePointer<CChar>?] = [
            strdup("TERM=xterm-256color"),
            strdup("HOME=\(NSHomeDirectory())"),
            strdup(pathEnv),
            nil
        ]

        logger.info("Spawning node with claude script")

        let result = posix_spawn(&pid, nodePath, &fileActions, nil, args, env)

        // Clean up
        posix_spawn_file_actions_destroy(&fileActions)
        for arg in args { free(arg) }
        for envVar in env { free(envVar) }

        if result == 0 {
            // Parent process - success
            self.childPID = pid

            // Register with process tracker
            ProcessTracker.shared.registerProcess(pid)

            // We're keeping masterFD open for reading
            shouldCloseMasterFD = false

            fcntl(masterFD, F_SETFL, O_NONBLOCK)
            startReading()
            monitorChildProcess()  // Monitor for process termination

            // Give Claude time to start, then send first /usage command
            // Increased wait time to ensure Claude is fully initialized
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
                self.requestUsageUpdate()
                self.startPolling()
            }
        } else {
            logger.error("posix_spawn failed with error: \(result)")
            // Defer block will clean up both FDs
        }
    }

    private func monitorChildProcess() {
        guard childPID > 0 else { return }

        let source = DispatchSource.makeProcessSource(
            identifier: childPID,
            eventMask: .exit,
            queue: .global()
        )

        source.setEventHandler { [weak self] in
            guard let self = self else { return }
            logger.warning("Claude process terminated unexpectedly")
            self.handleProcessTermination()
        }

        source.resume()
        processMonitorSource = source
    }

    private func handleProcessTermination() {
        // Clean up resources
        outputSource?.cancel()
        outputSource = nil
        processMonitorSource?.cancel()
        processMonitorSource = nil
        pollTimer?.invalidate()
        pollTimer = nil
        bufferCheckWorkItem?.cancel()
        bufferCheckWorkItem = nil

        // Unregister from process tracker
        if childPID > 0 {
            ProcessTracker.shared.unregisterProcess(childPID)
        }

        // Reset state
        childPID = -1
        masterFD = -1

        // Clear buffer safely on the serial queue
        bufferQueue.async {
            self.outputBuffer = ""
        }

        // Clear usage data to indicate monitoring stopped
        DispatchQueue.main.async {
            self.usageStats = UsageStats()
        }

        // Optionally: attempt restart after a delay
        DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self = self else { return }
            logger.info("Attempting to restart monitoring...")
            if self.claudePath != nil {
                self.startBackgroundSession()

                // Restart polling
                DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
                    self.requestUsageUpdate()
                    self.startPolling()
                }
            }
        }
    }

    private func startReading() {
        let source = DispatchSource.makeReadSource(fileDescriptor: masterFD, queue: .global())

        source.setEventHandler { [weak self] in
            guard let self = self else { return }

            var buffer = [UInt8](repeating: 0, count: 4096)
            let bytesRead = read(self.masterFD, &buffer, buffer.count)

            if bytesRead > 0 {
                let data = Data(buffer[0..<bytesRead])
                if let text = String(data: data, encoding: .utf8) {
                    // Update buffer on serial queue to prevent data races
                    self.bufferQueue.async {
                        self.outputBuffer += text

                        // Limit buffer size to prevent memory issues
                        if self.outputBuffer.count > 50000 {
                            self.outputBuffer = String(self.outputBuffer.suffix(20000))
                        }

                        // Debounce the expensive contains() checks
                        // Cancel any pending check and schedule a new one
                        self.bufferCheckWorkItem?.cancel()
                        let workItem = DispatchWorkItem { [weak self] in
                            guard let self = self else { return }
                            // Check if buffer contains usage data after output settles
                            if self.outputBuffer.contains("% used") && self.outputBuffer.contains("Current session") {
                                self.parseUsageOutput()
                            }
                        }
                        self.bufferCheckWorkItem = workItem
                        // Wait 300ms after last output before checking
                        self.bufferQueue.asyncAfter(deadline: .now() + 0.3, execute: workItem)
                    }
                }
            }
        }

        source.setCancelHandler { [weak self] in
            guard let self = self else { return }
            close(self.masterFD)
        }

        source.resume()
        self.outputSource = source
    }

    private func requestUsageUpdate() {
        guard masterFD >= 0 else {
            logger.warning("masterFD is invalid")
            DispatchQueue.main.async {
                self.fetchStatus = .failed
            }
            return
        }

        guard attemptCount < maxAttempts else {
            logger.warning("Max attempts reached")
            DispatchQueue.main.async {
                self.fetchStatus = .failed
            }
            return
        }

        // Update status to fetching on first attempt
        if attemptCount == 0 {
            DispatchQueue.main.async {
                self.fetchStatus = .fetching
            }
            // Clear buffer before starting new fetch cycle
            bufferQueue.async {
                // Clear buffer before fetch (logging removed)
                self.outputBuffer = ""
            }
        }

        attemptCount += 1

        // Only send /usage command on first attempt
        // On subsequent attempts, just wait for the panel to finish loading
        if attemptCount == 1 {
            // First, send Escape to clear any existing input
            if let escData = "\u{1B}".data(using: .utf8) {
                _ = escData.withUnsafeBytes { ptr in
                    write(masterFD, ptr.baseAddress, escData.count)
                }
            }

            usleep(100000) // 100ms delay

            // Type: /usage + space
            let command = "/usage "
            if let data = command.data(using: .utf8) {
                _ = data.withUnsafeBytes { ptr in
                    write(masterFD, ptr.baseAddress, data.count)
                }
            }

            usleep(200000) // 200ms delay to let autocomplete settle

            // Send Enter key
            if let enterData = "\r".data(using: .utf8) {
                _ = enterData.withUnsafeBytes { ptr in
                    write(masterFD, ptr.baseAddress, enterData.count)
                }
            }

            logger.debug("Sent '/usage ' + Enter")
        } else {
            logger.debug("Waiting for panel to load (not sending command again)")
        }

        // Schedule next attempt if we haven't reached max
        // Wait longer between attempts to give API time to respond
        if attemptCount < maxAttempts {
            DispatchQueue.main.asyncAfter(deadline: .now() + 15.0) { [weak self] in
                self?.requestUsageUpdate()
            }
        }
    }

    private func startPolling() {
        // Poll every 5 minutes
        pollTimer = Timer.scheduledTimer(withTimeInterval: 300.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            // Reset attempt count for new polling cycle
            self.attemptCount = 0
            self.requestUsageUpdate()
        }
    }

    private func parseUsageOutput() {
        // This method should only be called from bufferQueue
        // Parse the output buffer for usage statistics
        // Format:
        // Current session
        //  ███                                                6% used
        //  Resets 12:59pm (Europe/Amsterdam)
        //
        // Current week (all models)
        //  ██                                                 4% used
        //  Resets Dec 2, 8:59am (Europe/Amsterdam)
        //
        // Current week (Sonnet only)
        //  ███                                                6% used
        //  Resets Dec 2, 8:59am (Europe/Amsterdam)

        // Clean ANSI escape codes from buffer - wrap in do-catch to handle any string issues
        var cleanBuffer: String
        do {
            let regex = try NSRegularExpression(pattern: "\u{001B}\\[[0-9;]*[a-zA-Z]", options: [])
            let range = NSRange(location: 0, length: outputBuffer.utf16.count)
            cleanBuffer = regex.stringByReplacingMatches(in: outputBuffer, options: [], range: range, withTemplate: "")
        } catch {
            // If regex fails, just use the raw buffer
            cleanBuffer = outputBuffer
        }

        let lines = cleanBuffer.components(separatedBy: "\n")
        var newStats = UsageStats()

        var isSessionSection = false
        var isWeeklySection = false
        var isSonnetSection = false

        for i in 0..<lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespaces)

            // Detect sections (but don't skip - percentage might be on same line)
            if line.contains("Current session") {
                isSessionSection = true
                isWeeklySection = false
                isSonnetSection = false
            } else if line.contains("Current week (all models)") {
                isSessionSection = false
                isWeeklySection = true
                isSonnetSection = false
            } else if line.contains("Current week (Sonnet") {
                // Matches "Current week (Sonnet only)" or similar
                isSessionSection = false
                isWeeklySection = false
                isSonnetSection = true
            }

            // Parse percentage from lines like "5% used", "19% used", or "64%used" (no space)
            if let match = line.range(of: #"(\d+)%\s*used"#, options: .regularExpression) {
                let matchedText = String(line[match])
                let percentStr = matchedText.filter { $0.isNumber }
                if let percentage = Int(percentStr) {
                    if isSessionSection {
                        // Daily session is the "Current session"
                        newStats.dailyTokensUsed = percentage
                        newStats.dailyTokensLimit = 100 // We only get percentage
                    } else if isWeeklySection {
                        newStats.weeklyTokensUsed = percentage
                        newStats.weeklyTokensLimit = 100
                    } else if isSonnetSection {
                        newStats.sonnetTokensUsed = percentage
                        newStats.sonnetTokensLimit = 100
                    }
                }
            }
        }

        // Only update if we found valid data
        if newStats.dailyTokensUsed > 0 || newStats.weeklyTokensUsed > 0 {
            logger.info("Parsed stats - Daily: \(newStats.dailyTokensUsed)%, Weekly: \(newStats.weeklyTokensUsed)%")
            DispatchQueue.main.async {
                self.usageStats = newStats
                self.fetchStatus = .success
            }
        } else {
            logger.debug("No valid stats found in buffer (\(cleanBuffer.count) chars)")
            // Only set failed if we've reached max attempts
            if self.attemptCount >= self.maxAttempts {
                DispatchQueue.main.async {
                    self.fetchStatus = .failed
                }
            }
        }

        // Keep only recent output in buffer (last 20000 chars to capture full Settings panel)
        if outputBuffer.count > 20000 {
            outputBuffer = String(outputBuffer.suffix(20000))
        }
    }

    func cleanup() {
        logger.info("Cleaning up usage monitor session")

        // 1. Stop polling first
        pollTimer?.invalidate()
        pollTimer = nil

        // 2. Cancel parse timer and buffer check work item
        parseTimer?.cancel()
        parseTimer = nil
        bufferCheckWorkItem?.cancel()
        bufferCheckWorkItem = nil

        // 3. Send exit command (non-blocking, best effort)
        if masterFD >= 0 {
            let exitCommand = "/exit \r"
            if let data = exitCommand.data(using: .utf8) {
                _ = data.withUnsafeBytes { ptr in
                    write(masterFD, ptr.baseAddress, data.count)
                }
            }
        }

        // 4. Cancel dispatch sources (stops reading)
        outputSource?.cancel()
        outputSource = nil
        processMonitorSource?.cancel()
        processMonitorSource = nil

        // 5. Terminate the process if still running
        let pid = childPID
        if pid > 0 {
            // Verify process still exists before killing
            if kill(pid, 0) == 0 {
                kill(pid, SIGTERM)
                logger.info("Sent SIGTERM to Claude process \(pid)")
            }
            ProcessTracker.shared.unregisterProcess(pid)
            childPID = -1
        }

        // 6. Close file descriptor (if not already closed by outputSource cancel handler)
        let fd = masterFD
        if fd >= 0 {
            masterFD = -1
            // Note: outputSource cancel handler may have already closed this
            // close() on an already-closed FD is safe (returns EBADF)
            close(fd)
        }

        logger.info("Usage monitor cleanup complete")
    }

    deinit {
        cleanup()
    }
}

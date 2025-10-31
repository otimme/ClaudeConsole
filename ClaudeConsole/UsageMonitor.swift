//
//  UsageMonitor.swift
//  ClaudeConsole
//
//  Monitors Claude Code usage stats via background session
//

import Foundation
import Combine

struct UsageStats: Codable {
    var currentSessionTokens: Int = 0
    var dailyTokensUsed: Int = 0
    var dailyTokensLimit: Int = 0
    var weeklyTokensUsed: Int = 0
    var weeklyTokensLimit: Int = 0
    var opusTokensUsed: Int = 0
    var opusTokensLimit: Int = 100

    var dailyPercentage: Double {
        guard dailyTokensLimit > 0 else { return 0 }
        return Double(dailyTokensUsed) / Double(dailyTokensLimit) * 100
    }

    var weeklyPercentage: Double {
        guard weeklyTokensLimit > 0 else { return 0 }
        return Double(weeklyTokensUsed) / Double(weeklyTokensLimit) * 100
    }

    var opusPercentage: Double {
        guard opusTokensLimit > 0 else { return 0 }
        return Double(opusTokensUsed) / Double(opusTokensLimit) * 100
    }
}

class UsageMonitor: ObservableObject {
    @Published var usageStats = UsageStats()

    private var masterFD: Int32 = -1
    private var childPID: pid_t = -1
    private var outputSource: DispatchSourceRead?
    private var outputBuffer = ""
    private var pollTimer: Timer?
    private var attemptCount = 0
    private let maxAttempts = 3

    private var claudePath: String?

    init() {
        // Initialize on background thread to avoid view update conflicts
        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self = self else { return }

            // Find claude executable
            self.findClaudePath()

            if self.claudePath != nil {
                self.startBackgroundSession()

                // Start polling: first fetch after 3 seconds, then every 60 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    self.requestUsageUpdate()
                    self.startPolling()
                }
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
            task.waitUntilExit()

            if task.terminationStatus == 0 {
                let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
                if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !path.isEmpty,
                   !path.contains("not found") {
                    self.claudePath = path
                    // print("UsageMonitor: Found claude at \(path)")
                    return
                }
            }

            // print("UsageMonitor: 'which claude' failed, trying hardcoded nvm path")
            // Fallback: try common nvm location
            let nvmPath = "\(NSHomeDirectory())/.nvm/versions/node/v22.19.0/bin/claude"
            if FileManager.default.fileExists(atPath: nvmPath) {
                self.claudePath = nvmPath
                // print("UsageMonitor: Found claude at \(nvmPath)")
            }
        } catch {
            // print("UsageMonitor: Failed to find claude: \(error)")
        }
    }

    private func startBackgroundSession() {
        var masterFD: Int32 = -1
        var slaveFD: Int32 = -1

        guard openpty(&masterFD, &slaveFD, nil, nil, nil) == 0 else {
            // print("UsageMonitor: Failed to create PTY")
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
            // print("UsageMonitor: Claude path not available")
            close(masterFD)
            close(slaveFD)
            return
        }

        // Find node in the same directory as claude
        let claudeURL = URL(fileURLWithPath: claudePath)
        let nodeURL = claudeURL.deletingLastPathComponent().appendingPathComponent("node")
        let nodePath = nodeURL.path

        guard FileManager.default.fileExists(atPath: nodePath) else {
            // print("UsageMonitor: Node not found at \(nodePath)")
            close(masterFD)
            close(slaveFD)
            return
        }

        // print("UsageMonitor: Using node at \(nodePath)")

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
            pathTask.waitUntilExit()
            if let pathData = try? pathPipe.fileHandleForReading.readToEnd(),
               let path = String(data: pathData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !path.isEmpty {
                pathEnv = "PATH=\(path)"
                // print("UsageMonitor: Using PATH: \(path)")
            } else {
                // print("UsageMonitor: Failed to get PATH, using default")
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

        // print("UsageMonitor: Spawning node with claude script")

        let result = posix_spawn(&pid, nodePath, &fileActions, nil, args, env)

        // Clean up
        posix_spawn_file_actions_destroy(&fileActions)
        for arg in args { free(arg) }
        for envVar in env { free(envVar) }

        if result == 0 {
            // Parent process
            close(slaveFD)
            self.childPID = pid

            fcntl(masterFD, F_SETFL, O_NONBLOCK)
            startReading()

            // Give Claude time to start, then send first /usage command
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                self.requestUsageUpdate()
            }
        } else {
            // print("UsageMonitor: posix_spawn failed with error: \(result)")
            close(masterFD)
            close(slaveFD)
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
                    // Update buffer and parse on background queue
                    DispatchQueue.global(qos: .background).async {
                        self.outputBuffer += text
                        self.parseUsageOutput()
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
            // print("UsageMonitor: masterFD is invalid")
            return
        }

        guard attemptCount < maxAttempts else {
            // print("UsageMonitor: Max attempts reached")
            return
        }

        attemptCount += 1
        // print("UsageMonitor: Sending /usage command (attempt \(attemptCount)/\(maxAttempts))")

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

        // print("UsageMonitor: Sent '/usage ' + Enter")

        // Schedule next attempt if we haven't reached max
        if attemptCount < maxAttempts {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                self?.requestUsageUpdate()
            }
        }
    }

    private func startPolling() {
        // Poll every 60 seconds
        pollTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            // Reset attempt count for new polling cycle
            self.attemptCount = 0
            self.requestUsageUpdate()
        }
    }

    private func parseUsageOutput() {
        // Parse the output buffer for usage statistics
        // Format:
        // Current session
        //  ██▌                                                5% used
        //  Resets 8pm (Europe/Amsterdam)
        //
        // Current week (all models)
        //  █████████▌                                         19% used
        //  Resets Nov 5, 11am (Europe/Amsterdam)

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
        var isOpusSection = false

        for i in 0..<lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespaces)

            // Detect sections
            if line.contains("Current session") {
                isSessionSection = true
                isWeeklySection = false
                isOpusSection = false
                continue
            } else if line.contains("Current week (all models)") {
                isSessionSection = false
                isWeeklySection = true
                isOpusSection = false
                continue
            } else if line.contains("Current week (Opus)") {
                isSessionSection = false
                isWeeklySection = false
                isOpusSection = true
                continue
            }

            // Parse percentage from lines like "5% used" or "19% used"
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
                    } else if isOpusSection {
                        newStats.opusTokensUsed = percentage
                        newStats.opusTokensLimit = 100
                    }
                }
            }
        }

        // Only update if we found valid data
        if newStats.dailyTokensUsed > 0 || newStats.weeklyTokensUsed > 0 {
            // print("UsageMonitor: Parsed stats - Daily: \(newStats.dailyTokensUsed)%, Weekly: \(newStats.weeklyTokensUsed)%")
            DispatchQueue.main.async {
                self.usageStats = newStats
            }
        } else {
            // print("UsageMonitor: No valid stats found in buffer")
        }

        // Keep only recent output in buffer (last 5000 chars)
        if outputBuffer.count > 5000 {
            outputBuffer = String(outputBuffer.suffix(5000))
        }
    }

    deinit {
        pollTimer?.invalidate()
        outputSource?.cancel()
        if childPID > 0 {
            kill(childPID, SIGTERM)
        }
    }
}

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

    // Thread-safe PTY session
    private var ptySession: PTYSession?

    // Polling state
    private var pollTimer: Timer?
    private var attemptCount = 0
    private let maxAttempts = 3

    // Claude path (found during initialization)
    private var claudePath: String?

    // Initialization lock
    private let initLock = NSLock()
    private var isInitialized = false

    init() {
        // Initialize on background thread to avoid view update conflicts
        Task.detached(priority: .background) { [weak self] in
            await self?.initialize()
        }
    }

    private func initialize() async {
        initLock.lock()
        guard !isInitialized else {
            initLock.unlock()
            return
        }
        isInitialized = true
        initLock.unlock()

        // Find claude executable
        claudePath = await PTYSession.findClaudePath()

        guard claudePath != nil else {
            logger.warning("Could not find claude executable")
            await MainActor.run {
                self.fetchStatus = .failed
            }
            return
        }

        await startBackgroundSession()
    }

    private func startBackgroundSession() async {
        guard let claudePath = self.claudePath else {
            logger.warning("Claude path not available")
            return
        }

        // Find node in the same directory as claude
        let claudeURL = URL(fileURLWithPath: claudePath)
        let nodePath = claudeURL.deletingLastPathComponent().appendingPathComponent("node").path

        guard FileManager.default.fileExists(atPath: nodePath) else {
            logger.error("Node not found at \(nodePath)")
            return
        }

        logger.info("Using node at \(nodePath)")

        // Get PATH from login shell
        let pathEnv = await PTYSession.getLoginShellPath()

        // Create PTY session
        let session = PTYSession(maxBufferSize: 50000, debounceInterval: 0.3)

        // Set up output handler - parse usage data when buffer settles
        session.onOutput = { [weak self] buffer in
            self?.handleBufferOutput(buffer)
        }

        // Set up state change handler
        session.onStateChange = { [weak self] state in
            self?.handleStateChange(state)
        }

        do {
            try await session.start(
                executablePath: nodePath,
                arguments: ["node", claudePath],
                environment: [
                    "TERM": "xterm-256color",
                    "HOME": NSHomeDirectory(),
                    "PATH": pathEnv
                ]
            )

            self.ptySession = session
            logger.info("PTY session started successfully")

            // Wait for Claude to initialize
            try? await Task.sleep(nanoseconds: 8_000_000_000)  // 8 seconds

            // Send first usage request and start polling
            await MainActor.run {
                self.requestUsageUpdate()
                self.startPolling()
            }
        } catch {
            logger.error("Failed to start PTY session: \(error.localizedDescription)")
            await MainActor.run {
                self.fetchStatus = .failed
            }
        }
    }

    private func handleBufferOutput(_ buffer: String) {
        // Check if buffer contains usage data
        guard buffer.contains("% used") && buffer.contains("Current session") else {
            return
        }

        parseUsageOutput(from: buffer)
    }

    private func handleStateChange(_ state: PTYSessionState) {
        switch state {
        case .terminated, .failed:
            logger.warning("PTY session ended: \(state.description)")
            handleSessionTerminated()
        default:
            break
        }
    }

    private func handleSessionTerminated() {
        // Stop polling
        pollTimer?.invalidate()
        pollTimer = nil

        // Clear stats
        DispatchQueue.main.async { [weak self] in
            self?.usageStats = UsageStats()
            self?.fetchStatus = .idle
        }

        // Attempt restart after delay
        Task.detached(priority: .background) { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)  // 5 seconds
            logger.info("Attempting to restart monitoring...")
            await self?.startBackgroundSession()
        }
    }

    func requestUsageUpdate() {
        guard let session = ptySession, session.state.isRunning else {
            logger.warning("PTY session is not running")
            DispatchQueue.main.async { [weak self] in
                self?.fetchStatus = .failed
            }
            return
        }

        guard attemptCount < maxAttempts else {
            logger.warning("Max attempts reached")
            DispatchQueue.main.async { [weak self] in
                self?.fetchStatus = .failed
            }
            return
        }

        // Update status to fetching on first attempt
        if attemptCount == 0 {
            DispatchQueue.main.async { [weak self] in
                self?.fetchStatus = .fetching
            }
            // Clear buffer before starting new fetch cycle
            session.clearBuffer()
        }

        attemptCount += 1

        // Only send /usage command on first attempt
        if attemptCount == 1 {
            // First, send Escape to clear any existing input
            session.write("\u{1B}")

            usleep(100000) // 100ms delay

            // Type: /usage + space
            session.write("/usage ")

            usleep(200000) // 200ms delay to let autocomplete settle

            // Send Enter key
            session.write("\r")

            logger.debug("Sent '/usage ' + Enter")
        } else {
            logger.debug("Waiting for panel to load (not sending command again)")
        }

        // Schedule next attempt if we haven't reached max
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

    private func parseUsageOutput(from buffer: String) {
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

        // Clean ANSI escape codes from buffer
        var cleanBuffer: String
        do {
            let regex = try NSRegularExpression(pattern: "\u{001B}\\[[0-9;]*[a-zA-Z]", options: [])
            let range = NSRange(location: 0, length: buffer.utf16.count)
            cleanBuffer = regex.stringByReplacingMatches(in: buffer, options: [], range: range, withTemplate: "")
        } catch {
            // If regex fails, just use the raw buffer
            cleanBuffer = buffer
        }

        let lines = cleanBuffer.components(separatedBy: "\n")
        var newStats = UsageStats()

        var isSessionSection = false
        var isWeeklySection = false
        var isSonnetSection = false

        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)

            // Detect sections (but don't skip - percentage might be on same line)
            if trimmedLine.contains("Current session") {
                isSessionSection = true
                isWeeklySection = false
                isSonnetSection = false
            } else if trimmedLine.contains("Current week (all models)") {
                isSessionSection = false
                isWeeklySection = true
                isSonnetSection = false
            } else if trimmedLine.contains("Current week (Sonnet") {
                // Matches "Current week (Sonnet only)" or similar
                isSessionSection = false
                isWeeklySection = false
                isSonnetSection = true
            }

            // Parse percentage from lines like "5% used", "19% used", or "64%used" (no space)
            if let match = trimmedLine.range(of: #"(\d+)%\s*used"#, options: .regularExpression) {
                let matchedText = String(trimmedLine[match])
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

            // Capture values before async block to avoid weak self issues
            let stats = newStats
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.usageStats = stats
                self.fetchStatus = .success
            }
        } else {
            logger.debug("No valid stats found in buffer (\(cleanBuffer.count) chars)")
            // Only set failed if we've reached max attempts
            if self.attemptCount >= self.maxAttempts {
                DispatchQueue.main.async { [weak self] in
                    self?.fetchStatus = .failed
                }
            }
        }
    }

    func cleanup() {
        logger.info("Cleaning up usage monitor session")

        // 1. Stop polling first
        pollTimer?.invalidate()
        pollTimer = nil

        // 2. Send exit command before terminating (best effort)
        if let session = ptySession, session.state.isRunning {
            session.write("/exit \r")
        }

        // 3. Terminate PTY session (handles all cleanup internally)
        ptySession?.terminate()
        ptySession = nil

        logger.info("Usage monitor cleanup complete")
    }

    deinit {
        cleanup()
    }
}

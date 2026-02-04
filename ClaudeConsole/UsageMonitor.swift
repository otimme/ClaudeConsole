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
    private let maxAttempts = 5

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

        // Resolve symlink to get the real executable path
        let resolvedPath = (try? FileManager.default.destinationOfSymbolicLink(atPath: claudePath)) ?? claudePath

        // Determine if this is a native binary or node.js script
        let isNativeBinary = resolvedPath.contains("/versions/") || !resolvedPath.contains("/node/")

        // Get PATH from login shell
        let pathEnv = await PTYSession.getLoginShellPath()

        // Build environment: inherit full process environment for Keychain/OAuth access,
        // then override TERM and PATH for proper terminal operation
        var environment = ProcessInfo.processInfo.environment
        environment["TERM"] = "xterm-256color"
        environment["PATH"] = pathEnv
        // Ensure critical identity vars are set (needed for Keychain credential access)
        if environment["USER"] == nil {
            environment["USER"] = NSUserName()
        }
        if environment["HOME"] == nil {
            environment["HOME"] = NSHomeDirectory()
        }

        // Create PTY session (longer debounce to let the settings panel fully render)
        let session = PTYSession(maxBufferSize: 50000, debounceInterval: 2.0)

        // Set up output handler - parse usage data when buffer settles
        session.onOutput = { [weak self] buffer in
            self?.handleBufferOutput(buffer)
        }

        // Set up state change handler
        session.onStateChange = { [weak self] state in
            self?.handleStateChange(state)
        }

        do {
            if isNativeBinary {
                // Native Bun binary - spawn directly
                try await session.start(
                    executablePath: claudePath,
                    arguments: ["claude"],
                    environment: environment
                )
            } else {
                // Legacy node.js script - use node wrapper
                let claudeURL = URL(fileURLWithPath: claudePath)
                let nodePath = claudeURL.deletingLastPathComponent().appendingPathComponent("node").path

                guard FileManager.default.fileExists(atPath: nodePath) else {
                    logger.error("Node not found at \(nodePath) for legacy claude script")
                    await MainActor.run { self.fetchStatus = .failed }
                    return
                }

                try await session.start(
                    executablePath: nodePath,
                    arguments: ["node", claudePath],
                    environment: environment
                )
            }

            self.ptySession = session

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
        // Strip ANSI escapes before checking - the TUI inserts cursor movement
        // sequences (e.g. \e[1C) between "%" and "used" in the raw output
        let stripped = stripANSISequences(from: buffer)

        guard stripped.contains("% used") && stripped.contains("Current session") else {
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
            await self?.startBackgroundSession()
        }
    }

    func requestUsageUpdate() {
        guard let session = ptySession, session.state.isRunning else {
            DispatchQueue.main.async { [weak self] in
                self?.fetchStatus = .failed
            }
            return
        }

        guard attemptCount < maxAttempts else {
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

        if attemptCount == 1 {
            // Send /usage command on first attempt
            sendUsageCommandSequence(to: session)
        } else {
            // On retry attempts, poll the buffer directly since the TUI's continuous
            // redraws prevent the debounce-based onOutput callback from ever firing
            let buffer = session.getBuffer()
            let stripped = stripANSISequences(from: buffer)

            if stripped.contains("% used") && stripped.contains("Current session") {
                parseUsageOutput(from: buffer)
                return
            }
        }

        // Schedule next attempt if we haven't reached max
        if attemptCount < maxAttempts {
            DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) { [weak self] in
                self?.requestUsageUpdate()
            }
        }
    }

    /// Send the /usage command sequence with non-blocking delays
    private func sendUsageCommandSequence(to session: PTYSession) {
        // First, send Escape to close any open settings panel or clear input
        session.write("\u{1B}")

        // 500ms delay to let any open panel fully close before typing
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self, weak session] in
            guard let session = session, session.state.isRunning else { return }

            // Type each character individually with delays to simulate real keyboard input.
            // The Claude Code TUI uses a React/Ink-based input that processes keystrokes
            // individually. The "/" character triggers command mode, and subsequent
            // characters must arrive as individual key events for proper recognition.
            let chars = Array("/usage")
            let charDelay = 0.05 // 50ms between characters

            for (i, char) in chars.enumerated() {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * charDelay) { [weak session] in
                    guard let session = session, session.state.isRunning else { return }
                    session.write(String(char))
                }
            }

            // Send Enter after all characters have been typed
            let enterDelay = Double(chars.count) * charDelay + 0.3
            DispatchQueue.main.asyncAfter(deadline: .now() + enterDelay) { [weak session] in
                guard let session = session, session.state.isRunning else { return }
                session.write("\r")
            }
        }
    }

    /// Dismiss the settings panel by sending Escape
    private func dismissSettingsPanel() {
        guard let session = ptySession, session.state.isRunning else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak session] in
            guard let session = session, session.state.isRunning else { return }
            session.write("\u{1B}")
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

    /// Strip all ANSI/VT100 escape sequences from terminal output.
    /// CSI sequences are replaced with a space (they often represent cursor movement
    /// that provides visual spacing in the TUI), then runs of multiple spaces are collapsed.
    private func stripANSISequences(from text: String) -> String {
        var result = text

        // Standard CSI sequences: \e[...X (where X is a letter)
        // Replace with space — cursor movement sequences like \e[1C represent visual spacing
        if let regex = try? NSRegularExpression(pattern: "\u{001B}\\[[0-9;]*[a-zA-Z]") {
            result = regex.stringByReplacingMatches(in: result, range: NSRange(location: 0, length: result.utf16.count), withTemplate: " ")
        }

        // DEC private mode sequences: \e[?...X
        if let regex = try? NSRegularExpression(pattern: "\u{001B}\\[\\?[0-9;]*[a-zA-Z]") {
            result = regex.stringByReplacingMatches(in: result, range: NSRange(location: 0, length: result.utf16.count), withTemplate: "")
        }

        // OSC sequences: \e]...\a
        if let regex = try? NSRegularExpression(pattern: "\u{001B}\\][^\u{0007}]*\u{0007}") {
            result = regex.stringByReplacingMatches(in: result, range: NSRange(location: 0, length: result.utf16.count), withTemplate: "")
        }

        // Collapse runs of multiple spaces into a single space
        if let regex = try? NSRegularExpression(pattern: " {2,}") {
            result = regex.stringByReplacingMatches(in: result, range: NSRange(location: 0, length: result.utf16.count), withTemplate: " ")
        }

        return result
    }

    private func parseUsageOutput(from buffer: String) {
        let cleanBuffer = stripANSISequences(from: buffer)
        let lines = cleanBuffer.components(separatedBy: "\n")
        var newStats = UsageStats()

        var isSessionSection = false
        var isWeeklySection = false
        var isSonnetSection = false

        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            guard !trimmedLine.isEmpty else { continue }

            // Detect sections (but don't skip - percentage might be on same line)
            if trimmedLine.contains("Current session") {
                isSessionSection = true
                isWeeklySection = false
                isSonnetSection = false
            } else if trimmedLine.contains("Current week (all models)") {
                isSessionSection = false
                isWeeklySection = true
                isSonnetSection = false
            } else if trimmedLine.contains("Current week (Sonnet") || trimmedLine.contains("Current week (Opus") {
                // Matches "Current week (Sonnet only)" or "Current week (Opus only)"
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
            logger.info("Usage: session \(newStats.dailyTokensUsed)%, weekly \(newStats.weeklyTokensUsed)%, sonnet/opus \(newStats.sonnetTokensUsed)%")

            let stats = newStats
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.usageStats = stats
                self.fetchStatus = .success
            }

            // Dismiss the settings panel so the session is ready for the next poll
            dismissSettingsPanel()
        } else {
            logger.warning("Failed to parse usage percentages from output")
            // Only set failed if we've reached max attempts
            if self.attemptCount >= self.maxAttempts {
                DispatchQueue.main.async { [weak self] in
                    self?.fetchStatus = .failed
                }
            }
        }
    }

    func cleanup() {
        // 1. Stop polling first
        pollTimer?.invalidate()
        pollTimer = nil

        // 2. Send exit command before terminating (best effort)
        if let session = ptySession, session.state.isRunning {
            session.write("/exit\r")
        }

        // 3. Terminate PTY session (handles all cleanup internally)
        ptySession?.terminate()
        ptySession = nil
    }

    deinit {
        cleanup()
    }
}

//
//  ContextMonitor.swift
//  ClaudeConsole
//
//  Monitors Claude Code context usage by sending /context to visible terminal
//

import Foundation
import Combine
import SwiftTerm

struct ContextStats: Codable {
    var totalTokens: Int = 0
    var maxTokens: Int = 200000
    var systemPrompt: Int = 0
    var systemTools: Int = 0
    var mcpTools: Int = 0
    var customAgents: Int = 0
    var memoryFiles: Int = 0
    var skills: Int = 0
    var messages: Int = 0
    var freeSpace: Int = 0
    var autocompactBuffer: Int = 0

    var usedPercentage: Double {
        guard maxTokens > 0 else { return 0 }
        return Double(totalTokens) / Double(maxTokens) * 100
    }

    var freePercentage: Double {
        guard maxTokens > 0 else { return 0 }
        return Double(freeSpace) / Double(maxTokens) * 100
    }
}

class ContextMonitor: ObservableObject {
    @Published var contextStats = ContextStats()

    /// Terminal controller reference - can be set directly for multi-instance support
    /// or via notification for backwards compatibility
    weak var terminalController: LocalProcessTerminalView?

    // MARK: - Thread-Safe Buffer Access
    // Buffer properties are protected by bufferLock to prevent race conditions
    private let bufferLock = NSLock()
    private var _outputBuffer = ""
    private var _isCapturingContext = false

    // Thread-safe accessors
    private var outputBuffer: String {
        get {
            bufferLock.lock()
            defer { bufferLock.unlock() }
            return _outputBuffer
        }
        set {
            bufferLock.lock()
            defer { bufferLock.unlock() }
            _outputBuffer = newValue
        }
    }

    private var isCapturingContext: Bool {
        get {
            bufferLock.lock()
            defer { bufferLock.unlock() }
            return _isCapturingContext
        }
        set {
            bufferLock.lock()
            defer { bufferLock.unlock() }
            _isCapturingContext = newValue
        }
    }

    private var captureTimer: Timer?
    private var terminalOutputObserver: NSObjectProtocol?
    private var terminalControllerObserver: NSObjectProtocol?

    init() {
        // Listen for terminal output
        terminalOutputObserver = NotificationCenter.default.addObserver(
            forName: .terminalOutput,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }
            if let text = notification.userInfo?["text"] as? String {
                self.handleTerminalOutput(text)
            }
        }

        // Listen for terminal controller
        terminalControllerObserver = NotificationCenter.default.addObserver(
            forName: .terminalControllerAvailable,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }
            if let controller = notification.userInfo?["controller"] as? LocalProcessTerminalView {
                self.terminalController = controller
            }
        }
    }

    // MARK: - Multi-Instance Support

    /// Receive terminal output directly from TerminalView callback
    /// This bypasses NotificationCenter for window-scoped output handling
    func receiveTerminalOutput(_ text: String) {
        handleTerminalOutput(text)
    }

    // Public method to manually request context update
    func requestContextUpdate() {
        guard let terminal = terminalController else { return }

        // Reset state atomically to prevent race conditions
        bufferLock.lock()
        _isCapturingContext = true
        _outputBuffer = ""
        bufferLock.unlock()

        // Send /context + space to avoid autocomplete, then Enter
        let command = "/context "
        if let data = command.data(using: .utf8) {
            terminal.send(data: ArraySlice(data))
        }

        // Small delay, then send Enter
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if let enterData = "\r".data(using: .utf8) {
                terminal.send(data: ArraySlice(enterData))
            }
        }
    }

    private func handleTerminalOutput(_ text: String) {
        // Detect if user manually typed /context command
        if !isCapturingContext && text.contains("/context") {
            bufferLock.lock()
            _isCapturingContext = true
            _outputBuffer = ""
            bufferLock.unlock()
        }

        guard isCapturingContext else { return }

        outputBuffer += text

        // Reset the timer - wait for 2 seconds of no output before parsing
        captureTimer?.invalidate()
        captureTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            guard let self = self else { return }

            // Check if buffer contains actual context data (Free space line)
            let hasContextData = self.outputBuffer.contains("Free space") ||
                                 self.outputBuffer.contains("tokens (")

            if hasContextData {
                self.parseContextOutput()
                self.isCapturingContext = false
                self.captureTimer = nil
            } else {
                // Reschedule timer to wait for more output
                self.captureTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
                    guard let self = self else { return }
                    self.parseContextOutput()
                    self.isCapturingContext = false
                    self.captureTimer = nil
                }
            }
        }
    }

    private func parseContextOutput() {
        // Clean ANSI escape codes from buffer
        var cleanBuffer: String
        do {
            let regex = try NSRegularExpression(pattern: "\u{001B}\\[[0-9;]*[a-zA-Z]", options: [])
            let range = NSRange(location: 0, length: outputBuffer.utf16.count)
            cleanBuffer = regex.stringByReplacingMatches(in: outputBuffer, options: [], range: range, withTemplate: "")
        } catch {
            cleanBuffer = outputBuffer
        }

        let lines = cleanBuffer.components(separatedBy: "\n")
        var newStats = ContextStats()

        for line in lines {
            let cleanLine = line.trimmingCharacters(in: .whitespaces)

            // NEW FORMAT: Parse "Free space: 135k (67.3%)" - calculate max from this
            if cleanLine.contains("Free space:") {
                // Match pattern like "Free space: 135k (67.3%)"
                if let freeMatch = cleanLine.range(of: #"Free space:\s*(\d+\.?\d*)k\s*\((\d+\.?\d*)%\)"#, options: .regularExpression) {
                    let matchedStr = String(cleanLine[freeMatch])
                    // Extract the number before 'k'
                    if let numMatch = matchedStr.range(of: #"(\d+\.?\d*)k"#, options: .regularExpression) {
                        let numStr = matchedStr[numMatch].replacingOccurrences(of: "k", with: "")
                        if let freeK = Double(numStr) {
                            newStats.freeSpace = Int(freeK * 1000)
                        }
                    }
                    // Extract the percentage
                    if let pctMatch = matchedStr.range(of: #"\((\d+\.?\d*)%\)"#, options: .regularExpression) {
                        let pctStr = matchedStr[pctMatch]
                            .replacingOccurrences(of: "(", with: "")
                            .replacingOccurrences(of: "%)", with: "")
                        if let pct = Double(pctStr), pct > 0 {
                            // Calculate max tokens: freeSpace / (percentage/100)
                            newStats.maxTokens = Int(Double(newStats.freeSpace) / (pct / 100.0))
                            // Calculate used tokens
                            newStats.totalTokens = newStats.maxTokens - newStats.freeSpace
                        }
                    }
                }
            }

            // OLD FORMAT: Parse total tokens: "25k/200k tokens (13%)"
            if newStats.totalTokens == 0 {
                if let match = cleanLine.range(of: #"(\d+)k/(\d+)k tokens"#, options: .regularExpression) {
                    let numbers = cleanLine[match].split(separator: "/")
                    if numbers.count == 2 {
                        if let used = Int(numbers[0].replacingOccurrences(of: "k", with: "")) {
                            newStats.totalTokens = used * 1000
                        }
                        if let max = Int(numbers[1].replacingOccurrences(of: "k tokens", with: "").trimmingCharacters(in: .whitespaces)) {
                            newStats.maxTokens = max * 1000
                        }
                    }
                }
            }

            // Parse individual components using helper function
            // NEW FORMAT: "⛁ Memory files: 6.3k tokens (3.1%)"
            // OLD FORMAT: "Memory files: 6.3k tokens"
            if cleanLine.contains("System prompt") {
                newStats.systemPrompt = parseTokenValue(from: cleanLine)
            } else if cleanLine.contains("System tools") {
                newStats.systemTools = parseTokenValue(from: cleanLine)
            } else if cleanLine.contains("MCP tools") {
                newStats.mcpTools = parseTokenValue(from: cleanLine)
            } else if cleanLine.contains("Custom agents") {
                newStats.customAgents = parseTokenValue(from: cleanLine)
            } else if cleanLine.contains("Memory files") && !cleanLine.contains("·") {
                // Avoid matching header lines like "Memory files · /memory"
                newStats.memoryFiles = parseTokenValue(from: cleanLine)
            } else if cleanLine.contains("Skills") && cleanLine.contains("tokens") {
                newStats.skills = parseTokenValue(from: cleanLine)
            } else if cleanLine.contains("Messages") {
                newStats.messages = parseTokenValue(from: cleanLine)
            } else if cleanLine.contains("Autocompact buffer") {
                newStats.autocompactBuffer = parseTokenValue(from: cleanLine)
            }
        }

        // Only update if we found valid data
        if newStats.totalTokens > 0 {
            DispatchQueue.main.async {
                self.contextStats = newStats
            }
        }

        // Clear buffer
        outputBuffer = ""
    }

    /// Parse token values that can be either "X.Xk tokens" or "X tokens" format
    private func parseTokenValue(from line: String) -> Int {
        // First try to match "Xk tokens" or "X.Xk tokens" format (e.g., "2.7k tokens", "17.5k tokens")
        if let match = line.range(of: #"(\d+\.?\d*)k tokens"#, options: .regularExpression) {
            let numStr = line[match].replacingOccurrences(of: "k tokens", with: "").trimmingCharacters(in: .whitespaces)
            if let num = Double(numStr) {
                return Int(num * 1000)
            }
        }

        // Then try to match plain "X tokens" format (e.g., "844 tokens", "8 tokens")
        if let match = line.range(of: #"(\d+) tokens"#, options: .regularExpression) {
            let numStr = line[match].replacingOccurrences(of: " tokens", with: "").trimmingCharacters(in: .whitespaces)
            if let num = Int(numStr) {
                return num
            }
        }

        return 0
    }

    deinit {
        // Capture all references before async to avoid accessing self after dealloc
        // Using async instead of sync to avoid potential deadlock if main thread
        // is waiting for this object to be deallocated
        let timer = captureTimer
        let outputObserver = terminalOutputObserver
        let controllerObserver = terminalControllerObserver

        // Timer invalidation and observer removal must happen on main thread
        // Use async to avoid deadlock - timer might fire once more but that's safe
        // since it uses weak self
        if Thread.isMainThread {
            timer?.invalidate()
            if let obs = outputObserver {
                NotificationCenter.default.removeObserver(obs)
            }
            if let obs = controllerObserver {
                NotificationCenter.default.removeObserver(obs)
            }
        } else {
            DispatchQueue.main.async {
                timer?.invalidate()
                if let obs = outputObserver {
                    NotificationCenter.default.removeObserver(obs)
                }
                if let obs = controllerObserver {
                    NotificationCenter.default.removeObserver(obs)
                }
            }
        }
    }
}

// Additional notification names
extension Notification.Name {
    static let terminalOutput = Notification.Name("terminalOutput")
    static let terminalControllerAvailable = Notification.Name("terminalControllerAvailable")
}

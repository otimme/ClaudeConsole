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
    var customAgents: Int = 0
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

    private weak var terminalController: LocalProcessTerminalView?

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
            // Start capturing - user manually invoked /context
            bufferLock.lock()
            _isCapturingContext = true
            _outputBuffer = ""
            bufferLock.unlock()
        }

        guard isCapturingContext else { return }

        outputBuffer += text

        // Reset the timer - wait for 1 second of no output before parsing
        captureTimer?.invalidate()
        captureTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            self.parseContextOutput()
            self.isCapturingContext = false
            self.captureTimer = nil
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

            // Parse total tokens: "69k/200k tokens (34%)"
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

            // Parse individual components
            if cleanLine.contains("System prompt:") {
                if let match = cleanLine.range(of: #"(\d+\.?\d*)k tokens"#, options: .regularExpression) {
                    let numStr = cleanLine[match].replacingOccurrences(of: "k tokens", with: "").trimmingCharacters(in: .whitespaces)
                    if let num = Double(numStr) {
                        newStats.systemPrompt = Int(num * 1000)
                    }
                }
            } else if cleanLine.contains("System tools:") {
                if let match = cleanLine.range(of: #"(\d+\.?\d*)k tokens"#, options: .regularExpression) {
                    let numStr = cleanLine[match].replacingOccurrences(of: "k tokens", with: "").trimmingCharacters(in: .whitespaces)
                    if let num = Double(numStr) {
                        newStats.systemTools = Int(num * 1000)
                    }
                }
            } else if cleanLine.contains("Custom agents:") {
                if let match = cleanLine.range(of: #"(\d+\.?\d*)k tokens"#, options: .regularExpression) {
                    let numStr = cleanLine[match].replacingOccurrences(of: "k tokens", with: "").trimmingCharacters(in: .whitespaces)
                    if let num = Double(numStr) {
                        newStats.customAgents = Int(num * 1000)
                    }
                }
            } else if cleanLine.contains("Messages:") {
                if let match = cleanLine.range(of: #"(\d+\.?\d*)k tokens"#, options: .regularExpression) {
                    let numStr = cleanLine[match].replacingOccurrences(of: "k tokens", with: "").trimmingCharacters(in: .whitespaces)
                    if let num = Double(numStr) {
                        newStats.messages = Int(num * 1000)
                    }
                }
            } else if cleanLine.contains("Free space:") {
                if let match = cleanLine.range(of: #"(\d+)k"#, options: .regularExpression) {
                    let numStr = cleanLine[match].replacingOccurrences(of: "k", with: "").trimmingCharacters(in: .whitespaces)
                    if let num = Int(numStr) {
                        newStats.freeSpace = num * 1000
                    }
                }
            } else if cleanLine.contains("Autocompact buffer:") {
                if let match = cleanLine.range(of: #"(\d+\.?\d*)k tokens"#, options: .regularExpression) {
                    let numStr = cleanLine[match].replacingOccurrences(of: "k tokens", with: "").trimmingCharacters(in: .whitespaces)
                    if let num = Double(numStr) {
                        newStats.autocompactBuffer = Int(num * 1000)
                    }
                }
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

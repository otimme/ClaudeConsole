//
//  TerminalView.swift
//  ClaudeConsole
//
//  SwiftTerm-based terminal view
//

import SwiftUI
import SwiftTerm
import os.log

private let logger = Logger(subsystem: "com.claudeconsole", category: "TerminalView")

// Notification to signal Claude Code has started
extension Notification.Name {
    static let claudeCodeStarted = Notification.Name("claudeCodeStarted")
}

// Custom terminal view that monitors output for claude command
class MonitoredLocalProcessTerminalView: LocalProcessTerminalView {
    // Track the child process PID for cleanup
    private(set) var shellPID: pid_t?

    // MARK: - Callbacks for Multi-Instance Support
    /// Called when terminal receives output data (for ContextMonitor)
    var onDataReceived: ((String) -> Void)?

    /// Called when Claude Code is detected to have started (working directory available)
    var onClaudeStarted: ((String) -> Void)?

    // Constants for buffer limits
    private static let maxOutputBufferSize = 2000  // Max chars for output buffer
    private static let maxPWDBufferSize = 5000     // Max chars for PWD buffer

    // MARK: - Thread-Safe Buffer Access
    // All buffer properties are protected by bufferLock to prevent race conditions
    // in the dataReceived callback which can be called from multiple threads
    private let bufferLock = NSLock()

    // Backing storage (only access while holding bufferLock)
    private var _outputBuffer = ""
    private var _isPWDCapture = false
    private var _pwdBuffer = ""
    private var _waitingForClaudeBanner = false
    private var _claudeBannerBuffer = ""

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
            // Automatically trim buffer if it exceeds limit
            if _outputBuffer.count > Self.maxOutputBufferSize {
                _outputBuffer = String(_outputBuffer.suffix(Self.maxOutputBufferSize))
            }
        }
    }

    private var isPWDCapture: Bool {
        get {
            bufferLock.lock()
            defer { bufferLock.unlock() }
            return _isPWDCapture
        }
        set {
            bufferLock.lock()
            defer { bufferLock.unlock() }
            _isPWDCapture = newValue
        }
    }

    private var pwdBuffer: String {
        get {
            bufferLock.lock()
            defer { bufferLock.unlock() }
            return _pwdBuffer
        }
        set {
            bufferLock.lock()
            defer { bufferLock.unlock() }
            _pwdBuffer = newValue
            // Automatically trim buffer if it exceeds limit
            if _pwdBuffer.count > Self.maxPWDBufferSize {
                // If PWD capture buffer gets too large, abort capture
                _isPWDCapture = false
                _pwdBuffer = ""
            }
        }
    }

    // Event monitor (kept for removeEventMonitor safety)
    private var eventMonitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Ensure terminal becomes first responder when added to window
        if window != nil {
            DispatchQueue.main.async { [weak self] in
                self?.window?.makeFirstResponder(self)
            }
            setupEventMonitor()
            setupDragAndDrop()
        } else {
            removeEventMonitor()
        }
    }

    deinit {
        removeEventMonitor()

        // Unregister PID from tracker
        if let pid = shellPID {
            ProcessTracker.shared.unregisterProcess(pid)
        }
    }

    // MARK: - Process Management

    func captureShellPID() {
        // SwiftTerm doesn't expose the spawned process PID directly.
        // We find it by looking for zsh processes with our app as parent.
        // This is more reliable than guessing based on timing.
        let ourPID = getpid()

        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self = self else { return }

            // Use pgrep to find zsh processes with our app as parent
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
            task.arguments = ["-P", String(ourPID), "zsh"]

            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = FileHandle.nullDevice

            do {
                try task.run()
                task.waitUntilExit()

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8) {
                    let lines = output.components(separatedBy: .newlines)
                    for line in lines {
                        let trimmed = line.trimmingCharacters(in: .whitespaces)
                        if let pid = pid_t(trimmed), pid > 0 {
                            // Verify the process still exists before registering
                            if kill(pid, 0) == 0 {
                                DispatchQueue.main.async {
                                    self.shellPID = pid
                                    ProcessTracker.shared.registerProcess(pid)
                                    logger.info("Registered shell PID: \(pid)")
                                }
                            } else {
                                logger.warning("Shell PID \(pid) already exited before registration")
                            }
                            return
                        }
                    }
                }
                logger.debug("No child zsh process found for parent PID \(ourPID)")
            } catch {
                logger.error("Failed to capture shell PID: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Drag and Drop Support

    private var isDraggingOver = false
    private lazy var dropOverlay: NSView = {
        let overlay = NSView(frame: bounds)
        overlay.wantsLayer = true
        // Fallout green drop overlay
        let falloutGreen = NSColor(red: 0.08, green: 1.0, blue: 0.0, alpha: 1.0)
        overlay.layer?.backgroundColor = falloutGreen.withAlphaComponent(0.1).cgColor
        overlay.layer?.borderColor = falloutGreen.withAlphaComponent(0.6).cgColor
        overlay.layer?.borderWidth = 3
        overlay.layer?.cornerRadius = 4
        overlay.isHidden = true
        return overlay
    }()

    private func setupDragAndDrop() {
        // Register for file URL drops
        registerForDraggedTypes([.fileURL])

        // Add drop overlay
        addSubview(dropOverlay)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        // Check if pasteboard contains file URLs
        guard sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: nil) else {
            return []
        }

        isDraggingOver = true
        dropOverlay.frame = bounds
        dropOverlay.isHidden = false
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        isDraggingOver = false
        dropOverlay.isHidden = true
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        isDraggingOver = false
        dropOverlay.isHidden = true

        // Extract file URLs from pasteboard
        guard let urls = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: nil
        ) as? [URL] else {
            return false
        }

        // Format and insert paths
        let formattedPaths = urls.map { formatPathForTerminal($0) }.joined(separator: " ")

        if let data = formattedPaths.data(using: .utf8) {
            send(data: ArraySlice(data))

            // Restore focus to terminal window and make it first responder
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                NSApp.activate(ignoringOtherApps: true)
                self.window?.makeKeyAndOrderFront(nil)
                self.window?.makeFirstResponder(self)
            }

            return true
        }

        return false
    }

    // MARK: - Path Formatting

    private func formatPathForTerminal(_ url: URL) -> String {
        var path = url.path

        // Check if this is under home directory
        let useTilde = path.hasPrefix(NSHomeDirectory())
        if useTilde {
            path = "~" + path.dropFirst(NSHomeDirectory().count)
        }

        // Escape special characters with backslashes (like Terminal.app does)
        // Characters that need escaping in bash
        let specialChars = [" ", "(", ")", "&", ";", "|", "<", ">", "$", "`", "\"", "'", "*", "?", "[", "]", "!", "#", "{", "}", "\\"]

        var escapedPath = ""
        for (index, char) in path.enumerated() {
            let charString = String(char)
            // Don't escape the leading ~ for home directory
            if charString == "~" && index == 0 && useTilde {
                escapedPath += charString
            } else if specialChars.contains(charString) {
                escapedPath += "\\" + charString
            } else {
                escapedPath += charString
            }
        }

        return escapedPath
    }

    private func setupEventMonitor() {
        // Note: Previous workaround for SwiftTerm mouse selection bug removed.
        // The bug (issue #408) is now fixed in SwiftTerm main branch.
    }

    private func removeEventMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    override func layout() {
        super.layout()
        // Force the terminal to update its display after layout changes
        self.setNeedsDisplay(self.bounds)
    }


    override func dataReceived(slice: ArraySlice<UInt8>) {
        // Check if we're capturing PWD output - if so, don't display it
        let isCapturing = isPWDCapture

        if !isCapturing {
            // Only feed data to terminal when not capturing PWD
            super.dataReceived(slice: slice)
        }

        // Then monitor the output for claude command
        guard let text = String(bytes: slice, encoding: .utf8) else { return }

        // Post terminal output for ContextMonitor (on main thread to avoid issues)
        // Use callback if available, otherwise fall back to notification
        DispatchQueue.main.async { [weak self] in
            // Call the callback for window-scoped observers
            self?.onDataReceived?(text)

            // Also post notification for backwards compatibility
            NotificationCenter.default.post(
                name: .terminalOutput,
                object: nil,
                userInfo: ["text": text]
            )
        }

        // Process buffer atomically
        processReceivedData(text)
    }

    /// Process received data with proper synchronization
    private func processReceivedData(_ text: String) {
        // Check PWD capture state atomically
        bufferLock.lock()
        let isCapturing = _isPWDCapture
        if isCapturing {
            _pwdBuffer += text
            let currentPWDBuffer = _pwdBuffer
            bufferLock.unlock()

            processPWDCapture(buffer: currentPWDBuffer)
            return
        }

        // Regular output processing
        _outputBuffer += text
        let currentBuffer = _outputBuffer
        bufferLock.unlock()

        processOutputBuffer(buffer: currentBuffer, newText: text)
    }

    /// Process PWD capture buffer
    private func processPWDCapture(buffer: String) {
        guard buffer.contains("___PWD_START___") && buffer.contains("___PWD_END___") else {
            return
        }

        // Extract PWD between markers
        if let startRange = buffer.range(of: "___PWD_START___"),
           let endRange = buffer.range(of: "___PWD_END___") {
            let pwdSection = buffer[startRange.upperBound..<endRange.lowerBound]

            // Remove ANSI codes from the section
            var cleanSection = String(pwdSection)
            cleanSection = cleanSection.replacingOccurrences(
                of: "\\u{001B}\\[[0-9;?]*[a-zA-Z]",
                with: "",
                options: .regularExpression
            )

            let lines = cleanSection.components(separatedBy: CharacterSet.newlines)

            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty && trimmed.hasPrefix("/") {
                    // Post notification on main thread
                    DispatchQueue.main.async { [weak self] in
                        // Call the callback for window-scoped observers
                        self?.onClaudeStarted?(trimmed)

                        // Also post notification for backwards compatibility
                        NotificationCenter.default.post(
                            name: .claudeCodeStarted,
                            object: nil,
                            userInfo: ["workingDirectory": trimmed]
                        )
                    }

                    // Reset capture state atomically
                    bufferLock.lock()
                    _isPWDCapture = false
                    _pwdBuffer = ""
                    bufferLock.unlock()
                    return
                }
            }
        }

        // If we didn't find a path, reset and give up
        bufferLock.lock()
        _isPWDCapture = false
        _pwdBuffer = ""
        bufferLock.unlock()
    }

    /// Process regular output buffer for claude command detection
    private func processOutputBuffer(buffer: String, newText: String) {
        // Check for Enter key after typing 'claude'
        guard newText.contains("\n") || newText.contains("\r") else { return }

        // Remove ANSI codes
        let cleanBuffer = buffer.replacingOccurrences(
            of: "\\u{001B}\\[[0-9;?]*[a-zA-Z]",
            with: "",
            options: .regularExpression
        )

        // Get last 100 characters to check
        let searchText = String(cleanBuffer.suffix(100)).trimmingCharacters(in: .whitespacesAndNewlines)

        guard searchText.contains("claude") else { return }

        // Check if already capturing (atomically)
        bufferLock.lock()
        guard !_isPWDCapture else {
            bufferLock.unlock()
            return
        }
        bufferLock.unlock()

        // Extract PWD from the prompt itself (e.g., "Olaf@olafs-mbp-m1 /path/to/dir % claude")
        var workingDir: String? = nil

        // Try to extract path from prompt pattern
        if let match = searchText.range(of: #"@[^\s]+ ([^\s]+) [%$]"#, options: .regularExpression) {
            let matchedText = String(searchText[match])
            let components = matchedText.components(separatedBy: " ")
            if components.count >= 2 {
                workingDir = components[components.count - 2]
            }
        }

        // Expand ~ to home directory
        if let dir = workingDir, dir.hasPrefix("~") {
            workingDir = dir.replacingOccurrences(of: "~", with: NSHomeDirectory())
        }

        // If we got a valid full path, use it immediately
        if let dir = workingDir, dir.hasPrefix("/") {
            // Post notification on main thread
            DispatchQueue.main.async { [weak self] in
                self?.onClaudeStarted?(dir)
                NotificationCenter.default.post(
                    name: .claudeCodeStarted,
                    object: nil,
                    userInfo: ["workingDirectory": dir]
                )
            }

            // Clear buffer atomically
            bufferLock.lock()
            _outputBuffer = ""
            bufferLock.unlock()
        } else {
            // Prompt only shows folder name (not full path), use pwd to get the actual path
            bufferLock.lock()
            _outputBuffer = ""
            bufferLock.unlock()

            getPWD()
        }
    }

    private func getPWD() {
        // Set capture state atomically
        bufferLock.lock()
        _isPWDCapture = true
        _pwdBuffer = ""
        bufferLock.unlock()

        let command = "echo ___PWD_START___; pwd; echo ___PWD_END___\r"
        if let data = command.data(using: .utf8) {
            self.send(data: ArraySlice(data))
        }
    }
}

struct TerminalView: NSViewRepresentable {
    @Binding var terminalController: LocalProcessTerminalView?

    // MARK: - Callbacks for Multi-Instance Support
    /// Called when terminal receives output data (optional, for window-scoped observers)
    var onOutput: ((String) -> Void)?

    /// Called when Claude Code starts (optional, for window-scoped observers)
    var onClaudeStarted: ((String) -> Void)?

    func makeNSView(context: Context) -> MonitoredLocalProcessTerminalView {
        // Use a reasonable initial frame instead of .zero to help with coordinate system
        let initialFrame = NSRect(x: 0, y: 0, width: 800, height: 600)
        let terminalView = MonitoredLocalProcessTerminalView(frame: initialFrame)

        // Configure terminal appearance - Fallout Pip-Boy style
        terminalView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

        // Set terminal colors - Fallout phosphor green on dark background
        // Primary green: #14FF00 (20, 255, 0)
        // Background: #0A0F08 (10, 15, 8)
        let falloutGreen = NSColor(red: 20/255, green: 255/255, blue: 0/255, alpha: 1.0)
        let falloutBackground = NSColor(red: 10/255, green: 15/255, blue: 8/255, alpha: 1.0)
        terminalView.nativeForegroundColor = falloutGreen
        terminalView.nativeBackgroundColor = falloutBackground

        // Set cursor color to match theme
        terminalView.caretColor = falloutGreen

        // Ensure proper autoresizing behavior
        terminalView.autoresizingMask = [.width, .height]
        terminalView.translatesAutoresizingMaskIntoConstraints = false

        // Wire up callbacks for multi-instance support
        terminalView.onDataReceived = onOutput
        terminalView.onClaudeStarted = onClaudeStarted

        // Start interactive login shell (just like Terminal.app)
        // This will load .zshrc and give you full environment
        terminalView.startProcess(executable: "/bin/zsh", args: ["-l"])

        // Capture the shell PID for process tracking
        terminalView.captureShellPID()

        DispatchQueue.main.async {
            self.terminalController = terminalView

            // Make terminal become first responder to receive keyboard events
            terminalView.window?.makeFirstResponder(terminalView)

            // Post notification that terminal controller is available
            NotificationCenter.default.post(
                name: .terminalControllerAvailable,
                object: nil,
                userInfo: ["controller": terminalView]
            )
        }

        return terminalView
    }

    func updateNSView(_ nsView: MonitoredLocalProcessTerminalView, context: Context) {
        // Update callbacks if they've changed (SwiftUI may recreate the struct with new closures)
        nsView.onDataReceived = onOutput
        nsView.onClaudeStarted = onClaudeStarted

        // Update layout when SwiftUI view geometry changes
        // This ensures the terminal's coordinate system stays in sync
        DispatchQueue.main.async {
            nsView.needsLayout = true
            nsView.layoutSubtreeIfNeeded()
        }
    }

    static func dismantleNSView(_ nsView: MonitoredLocalProcessTerminalView, coordinator: ()) {
        // Send exit command to Claude if running (non-blocking)
        // Note: This may not work if terminal is running something else
        let exitCommand = "/exit \r"
        if let data = exitCommand.data(using: .utf8) {
            nsView.send(data: ArraySlice(data))
        }
        // Don't block - ProcessTracker will handle cleanup if needed
    }
}

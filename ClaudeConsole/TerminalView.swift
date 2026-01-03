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

    // Constants for buffer limits
    private static let maxOutputBufferSize = 2000  // Max chars for output buffer
    private static let maxPWDBufferSize = 5000     // Max chars for PWD buffer

    private var outputBuffer = "" {
        didSet {
            // Automatically trim buffer if it exceeds limit
            if outputBuffer.count > Self.maxOutputBufferSize {
                outputBuffer = String(outputBuffer.suffix(Self.maxOutputBufferSize))
            }
        }
    }

    private var isPWDCapture = false
    private var pwdBuffer = "" {
        didSet {
            // Automatically trim buffer if it exceeds limit
            if pwdBuffer.count > Self.maxPWDBufferSize {
                // If PWD capture buffer gets too large, abort capture
                isPWDCapture = false
                pwdBuffer = ""
            }
        }
    }

    // Event monitor for fixing selection coordinates
    private var eventMonitor: Any?
    private var cachedCellHeight: CGFloat?

    private func getCellHeight() -> CGFloat {
        if let cached = cachedCellHeight {
            return cached
        }
        let lineHeight = font.ascender - font.descender + font.leading
        let cellHeight = ceil(lineHeight)
        cachedCellHeight = cellHeight
        return cellHeight
    }

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
        removeEventMonitor()

        // Monitor left mouse dragged and up events to fix selection coordinates
        // This works around a SwiftTerm bug where mouseDragged doesn't account for yDisp
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp]) { [weak self] event in
            guard let self = self else { return event }

            // Only process events within our view
            guard let window = self.window,
                  let contentView = window.contentView else {
                return event
            }

            let locationInWindow = event.locationInWindow
            let locationInContent = contentView.convert(locationInWindow, from: nil)
            let locationInSelf = self.convert(locationInContent, from: contentView)

            // Check if event is within our bounds
            guard self.bounds.contains(locationInSelf) else {
                return event
            }

            // Get the scroll offset (yDisp)
            guard let terminal = self.terminal else {
                return event
            }

            let yDisp = terminal.buffer.yDisp

            // Always apply yDisp adjustment (no arbitrary limits)
            // SwiftTerm's mouseDown adds yDisp but mouseDragged doesn't
            // We compensate by shifting the Y coordinate
            if yDisp != 0 {
                let cellHeight = self.getCellHeight()

                // In NSView coordinates (origin at bottom-left), we need to shift UP
                // by the number of scrolled lines to make SwiftTerm calculate the correct buffer row
                // Add one extra cell height to account for off-by-one error
                let scrollOffset = CGFloat(yDisp) * cellHeight + cellHeight
                let adjustedY = locationInWindow.y + scrollOffset
                let adjustedLocation = CGPoint(x: locationInWindow.x, y: adjustedY)

                // Create adjusted event
                if let adjustedEvent = NSEvent.mouseEvent(
                    with: event.type,
                    location: adjustedLocation,
                    modifierFlags: event.modifierFlags,
                    timestamp: event.timestamp,
                    windowNumber: event.windowNumber,
                    context: nil,
                    eventNumber: event.eventNumber,
                    clickCount: event.clickCount,
                    pressure: event.pressure
                ) {
                    return adjustedEvent
                }
            }

            return event
        }
    }

    private func removeEventMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    // MARK: - Fix for text selection after scrolling

    override func layout() {
        super.layout()
        cachedCellHeight = nil  // Clear cache on layout changes
        // Force the terminal to update its internal coordinate system after layout changes
        // This ensures selection coordinates are properly updated when scrolling
        self.setNeedsDisplay(self.bounds)
    }


    override func dataReceived(slice: ArraySlice<UInt8>) {
        // First, feed the data to the terminal (normal operation)
        super.dataReceived(slice: slice)

        // Then monitor the output for claude command
        guard let text = String(bytes: slice, encoding: .utf8) else { return }

        // Post terminal output for ContextMonitor
        NotificationCenter.default.post(
            name: .terminalOutput,
            object: nil,
            userInfo: ["text": text]
        )

        if isPWDCapture {
            // Capturing pwd output
            pwdBuffer += text

            // Wait until we have both markers
            if pwdBuffer.contains("___PWD_START___") && pwdBuffer.contains("___PWD_END___") {
                // Extract PWD between markers
                if let startRange = pwdBuffer.range(of: "___PWD_START___"),
                   let endRange = pwdBuffer.range(of: "___PWD_END___") {
                    let pwdSection = pwdBuffer[startRange.upperBound..<endRange.lowerBound]

                    // Remove ANSI codes from the section
                    var cleanSection = String(pwdSection)
                    cleanSection = cleanSection.replacingOccurrences(of: "\\u{001B}\\[[0-9;?]*[a-zA-Z]", with: "", options: .regularExpression)

                    let lines = cleanSection.components(separatedBy: CharacterSet.newlines)

                    for line in lines {
                        let trimmed = line.trimmingCharacters(in: .whitespaces)
                        if !trimmed.isEmpty && trimmed.hasPrefix("/") {
                            NotificationCenter.default.post(
                                name: .claudeCodeStarted,
                                object: nil,
                                userInfo: ["workingDirectory": trimmed]
                            )
                            isPWDCapture = false
                            pwdBuffer = ""
                            return
                        }
                    }
                }

                // If we didn't find a path, reset and give up
                isPWDCapture = false
                pwdBuffer = ""
            }

            // Buffer size is automatically limited by didSet
            return
        }

        outputBuffer += text

        // Check for Enter key after typing 'claude'
        if text.contains("\n") || text.contains("\r") {
            // Remove ANSI codes
            let cleanBuffer = outputBuffer.replacingOccurrences(of: "\\u{001B}\\[[0-9;?]*[a-zA-Z]", with: "", options: .regularExpression)

            // Get last 100 characters to check
            let searchText = String(cleanBuffer.suffix(100)).trimmingCharacters(in: .whitespacesAndNewlines)

            // Simple check: does it contain "claude" anywhere in the last bit?
            if searchText.contains("claude") && !isPWDCapture {
                // Extract PWD from the prompt itself (e.g., "Olaf@olafs-mbp-m1 /path/to/dir % claude")
                // The prompt format is typically: username@host path % command
                var workingDir = "/"  // Default fallback

                // Try to extract path from prompt pattern
                if let match = searchText.range(of: #"@[^\s]+ ([^\s]+) [%$]"#, options: .regularExpression) {
                    let matchedText = String(searchText[match])
                    // Extract the path part (between the space and the % or $)
                    let components = matchedText.components(separatedBy: " ")
                    if components.count >= 2 {
                        workingDir = components[components.count - 2]
                    }
                }

                // Expand ~ to home directory
                if workingDir.hasPrefix("~") {
                    workingDir = workingDir.replacingOccurrences(of: "~", with: NSHomeDirectory())
                }

                // If path doesn't start with /, it might be relative - default to root
                if !workingDir.hasPrefix("/") {
                    workingDir = "/"
                }

                NotificationCenter.default.post(
                    name: .claudeCodeStarted,
                    object: nil,
                    userInfo: ["workingDirectory": workingDir]
                )

                // Clear buffer to avoid re-detecting
                outputBuffer = ""
            }
            // Buffer size is automatically limited by didSet
        }
    }

    private func getPWD() {
        isPWDCapture = true
        pwdBuffer = ""

        let command = "echo ___PWD_START___; pwd; echo ___PWD_END___\r"
        if let data = command.data(using: .utf8) {
            self.send(data: ArraySlice(data))
        }
    }
}

struct TerminalView: NSViewRepresentable {
    @Binding var terminalController: LocalProcessTerminalView?

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

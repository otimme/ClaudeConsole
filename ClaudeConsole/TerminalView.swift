//
//  TerminalView.swift
//  ClaudeConsole
//
//  SwiftTerm-based terminal view
//

import SwiftUI
import SwiftTerm

// Notification to signal Claude Code has started
extension Notification.Name {
    static let claudeCodeStarted = Notification.Name("claudeCodeStarted")
}

// Custom terminal view that monitors output for claude command
class MonitoredLocalProcessTerminalView: LocalProcessTerminalView {
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
        } else {
            removeEventMonitor()
        }
    }

    deinit {
        removeEventMonitor()
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

        // Configure terminal appearance
        terminalView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

        // Set terminal colors (default dark theme)
        terminalView.nativeForegroundColor = NSColor.textColor
        terminalView.nativeBackgroundColor = NSColor.textBackgroundColor

        // Ensure proper autoresizing behavior
        terminalView.autoresizingMask = [.width, .height]
        terminalView.translatesAutoresizingMaskIntoConstraints = false

        // Start interactive login shell (just like Terminal.app)
        // This will load .zshrc and give you full environment
        terminalView.startProcess(executable: "/bin/zsh", args: ["-l"])

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
}

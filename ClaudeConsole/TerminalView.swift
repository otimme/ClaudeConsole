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
    private var outputBuffer = ""
    private var isPWDCapture = false
    private var pwdBuffer = ""

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Ensure terminal becomes first responder when added to window
        if window != nil {
            DispatchQueue.main.async { [weak self] in
                self?.window?.makeFirstResponder(self)
            }
        }
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

            // Keep buffer size limited while capturing
            if pwdBuffer.count > 5000 {
                isPWDCapture = false
                pwdBuffer = ""
            }
            return
        }

        outputBuffer += text

        // Check for Enter key after typing 'claude'
        if text.contains("\n") || text.contains("\r") {
            // Remove ANSI codes
            var cleanBuffer = outputBuffer.replacingOccurrences(of: "\\u{001B}\\[[0-9;?]*[a-zA-Z]", with: "", options: .regularExpression)

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
            } else {
                // Keep buffer limited
                if outputBuffer.count > 2000 {
                    outputBuffer = String(outputBuffer.suffix(2000))
                }
            }
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
        let terminalView = MonitoredLocalProcessTerminalView(frame: .zero)

        // Configure terminal appearance
        terminalView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

        // Set terminal colors (default dark theme)
        terminalView.nativeForegroundColor = NSColor.textColor
        terminalView.nativeBackgroundColor = NSColor.textBackgroundColor

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
        // No updates needed - SwiftTerm handles everything
    }
}

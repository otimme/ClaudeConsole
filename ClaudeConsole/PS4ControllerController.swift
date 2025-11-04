//
//  PS4ControllerController.swift
//  ClaudeConsole
//
//  Orchestrates PS4 controller monitoring and terminal integration
//

import Foundation
import SwiftTerm
import Combine
import AppKit
import UserNotifications
import os.log

class PS4ControllerController: ObservableObject {
    // Configuration constants
    private static let sequenceActionDelay: TimeInterval = 0.1  // seconds between sequence actions
    private static let notificationDisplayDelay: TimeInterval = 2.0  // seconds for notifications

    let monitor = PS4ControllerMonitor()
    let mapping = PS4ButtonMapping()
    let appCommandExecutor = AppCommandExecutor()

    @Published var isEnabled = true
    @Published var showVisualizer = true

    private weak var terminalController: LocalProcessTerminalView?
    private var cancellables = Set<AnyCancellable>()
    private var terminalControllerObserver: NSObjectProtocol?

    // CRITICAL FIX: Push-to-talk state machine implementation
    // Previous implementation used simple `pushToTalkButton: PS4Button?` which had edge cases:
    // - Controller disconnects during recording → state never cleared
    // - Two buttons mapped to push-to-talk → only first button tracked
    // - Recording fails to start → state set but not recording
    // - Recording fails to stop → state cleared but still recording
    //
    // New state machine properly handles all edge cases with explicit states:
    private enum PushToTalkState {
        case idle                                          // Not recording
        case recording(button: PS4Button, startedAt: Date) // Recording in progress, tracks which button
        case transcribing                                  // Recording stopped, transcription in progress
    }
    private var pushToTalkState: PushToTalkState = .idle

    init() {
        // Forward monitor's objectWillChange to trigger UI updates
        monitor.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        // Forward mapping's objectWillChange as well
        mapping.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        // Listen for terminal controller availability
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

        // Observe connection state
        monitor.$isConnected
            .receive(on: DispatchQueue.main)
            .dropFirst() // Skip initial value to prevent notification on app launch
            .sink { [weak self] connected in
                if connected {
                    print("PS4 Controller connected")
                    self?.showConnectionNotification(connected: true)
                } else {
                    print("PS4 Controller disconnected")
                    self?.showConnectionNotification(connected: false)
                }
            }
            .store(in: &cancellables)

        // Defer setting up callbacks to avoid initialization issues
        DispatchQueue.main.async { [weak self] in
            self?.setupControllerCallbacks()
        }
    }

    private func setupControllerCallbacks() {
        // Handle button presses
        monitor.onButtonPressed = { [weak self] button in
            guard let self = self, self.isEnabled else { return }

            // Get the mapped action for this button
            if let action = self.mapping.getAction(for: button) {
                // Check if this is a push-to-talk action
                if case .applicationCommand(.pushToTalkSpeech) = action {
                    self.handlePushToTalkPress(button: button)
                } else {
                    // Execute action normally
                    self.executeButtonAction(action)
                }

                // Optional: Provide haptic feedback
                self.monitor.startVibration(intensity: 0.5, duration: 0.05)
            }
        }

        // Handle button releases
        monitor.onButtonReleased = { [weak self] button in
            guard let self = self, self.isEnabled else { return }

            // Check if this is a push-to-talk button being released
            self.handlePushToTalkRelease(button: button)
        }

        // Monitor controller disconnection to cleanup push-to-talk state
        monitor.$isConnected
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isConnected in
                if !isConnected {
                    self?.handleControllerDisconnected()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Push-to-Talk State Management
    // FIX: Proper state machine with error handling and edge case coverage

    private func handlePushToTalkPress(button: PS4Button) {
        // FIX: State guard - only allow starting if idle (prevents duplicate recordings)
        guard case .idle = pushToTalkState else {
            os_log("Cannot start push-to-talk: already in state %{public}@", log: .default, type: .info, String(describing: pushToTalkState))
            return
        }

        // FIX: Validate speech controller is ready before attempting to start
        // Previous implementation had no validation, leading to silent failures
        guard let speech = appCommandExecutor.speechController, speech.isReady else {
            os_log("Cannot start push-to-talk: speech controller not ready", log: .default, type: .error)
            showConnectionNotification(connected: false) // User feedback via notification
            return
        }

        // Transition to recording state
        pushToTalkState = .recording(button: button, startedAt: Date())

        // FIX: Call startRecordingViaController() directly instead of going through toggle
        // This eliminates the double DispatchQueue.main.async chain that was causing race conditions
        speech.startRecordingViaController()

        // FIX: Async verification that recording actually started
        // Increased delay to 300ms to account for async dispatch chain
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self = self else { return }

            // If still in recording state but not actually recording, reset
            if case .recording = self.pushToTalkState,
               let speech = self.appCommandExecutor.speechController,
               !speech.isRecording {
                os_log("Push-to-talk failed to start recording - resetting state", log: .default, type: .error)
                self.pushToTalkState = .idle
            }
        }
    }

    private func handlePushToTalkRelease(button: PS4Button) {
        // FIX: Only handle release if this button is currently recording
        // This prevents other buttons from interfering with active recording
        guard case .recording(let recordingButton, _) = pushToTalkState,
              recordingButton == button else {
            return
        }

        // Transition to transcribing state
        pushToTalkState = .transcribing

        // FIX: Call stopRecordingViaController() directly instead of going through executor
        // This ensures we stop recording immediately without extra indirection
        if let speech = appCommandExecutor.speechController {
            speech.stopRecordingViaController()
        }

        // FIX: Safety timeout fallback (30 seconds)
        // If transcription hangs or fails, automatically reset to idle state
        DispatchQueue.main.asyncAfter(deadline: .now() + 30.0) { [weak self] in
            guard let self = self else { return }
            if case .transcribing = self.pushToTalkState {
                os_log("Push-to-talk transcription timeout - resetting to idle", log: .default, type: .info)
                self.pushToTalkState = .idle
            }
        }

        // FIX: Monitor transcription completion via Combine
        // When transcription finishes, automatically return to idle state
        if let speech = appCommandExecutor.speechController {
            speech.$isTranscribing
                .receive(on: DispatchQueue.main)
                .filter { !$0 } // Wait for transcription to finish
                .prefix(1) // Only take the first completion
                .sink { [weak self] _ in
                    self?.pushToTalkState = .idle
                }
                .store(in: &cancellables)
        }
    }

    private func handleControllerDisconnected() {
        // FIX: Critical edge case - controller disconnects during recording
        // Force stop any active recording when controller disconnects to prevent:
        // - Microphone staying open indefinitely
        // - Battery drain from continued recording
        // - State inconsistency
        if case .recording = pushToTalkState {
            os_log("Controller disconnected during push-to-talk - stopping recording", log: .default, type: .info)
            if let speech = appCommandExecutor.speechController {
                speech.stopRecordingViaController()
            }
        }
        pushToTalkState = .idle
    }

    // Execute different types of button actions
    private func executeButtonAction(_ action: ButtonAction) {
        switch action {
        case .keyCommand(let command):
            sendCommandToTerminal(command)

        case .textMacro(let text, let autoEnter):
            sendTextMacroToTerminal(text, autoEnter: autoEnter)

        case .applicationCommand(let appCommand):
            executeApplicationCommand(appCommand)

        case .systemCommand(let systemCommand):
            executeSystemCommand(systemCommand)

        case .sequence(let actions):
            executeSequence(actions)

        case .shellCommand(let command):
            executeShellCommand(command)
        }
    }

    private func sendCommandToTerminal(_ command: KeyCommand) {
        guard let terminal = terminalController else {
            print("Terminal controller not available")
            return
        }

        // Convert the command to terminal data
        if let data = command.toTerminalData() {
            terminal.send(data: ArraySlice(data))
        }
    }

    private func sendTextMacroToTerminal(_ text: String, autoEnter: Bool) {
        guard let terminal = terminalController else {
            print("Terminal controller not available")
            return
        }

        // Process escape sequences and special characters
        let processedText = processEscapeSequences(text)

        var data = processedText.data(using: .utf8) ?? Data()
        if autoEnter {
            data.append(Data([0x0D])) // Carriage return
        }
        terminal.send(data: ArraySlice(data))
    }

    private func processEscapeSequences(_ text: String) -> String {
        var result = text

        // Handle common escape sequences
        result = result.replacingOccurrences(of: "\\n", with: "\n")
        result = result.replacingOccurrences(of: "\\t", with: "\t")
        result = result.replacingOccurrences(of: "\\r", with: "\r")
        result = result.replacingOccurrences(of: "\\\"", with: "\"")
        result = result.replacingOccurrences(of: "\\'", with: "'")
        result = result.replacingOccurrences(of: "\\\\", with: "\\")

        // Handle dynamic replacements
        if result.contains("$(date)") {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            result = result.replacingOccurrences(of: "$(date)", with: formatter.string(from: Date()))
        }

        if result.contains("$(time)") {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss"
            result = result.replacingOccurrences(of: "$(time)", with: formatter.string(from: Date()))
        }

        if result.contains("$(user)") {
            result = result.replacingOccurrences(of: "$(user)", with: NSUserName())
        }

        if result.contains("$(pwd)") {
            result = result.replacingOccurrences(of: "$(pwd)", with: FileManager.default.currentDirectoryPath)
        }

        return result
    }

    private func executeApplicationCommand(_ command: AppCommand) {
        // FIX: Removed duplicate command execution logic
        // Previous implementation had duplicate code for clipboard, terminal, and Claude commands
        // both here AND in AppCommandExecutor, violating DRY principle and creating maintenance burden.
        //
        // Now: Single source of truth - all commands delegated to AppCommandExecutor
        // Exception: togglePS4Panel affects local showVisualizer state

        // Special case: togglePS4Panel affects our local showVisualizer state
        if command == .togglePS4Panel {
            showVisualizer.toggle()
            return
        }

        // FIX: Delegate all other commands to AppCommandExecutor for centralized execution
        // This eliminates code duplication and ensures consistent behavior
        appCommandExecutor.execute(command)
    }

    private func executeSystemCommand(_ command: SystemCommand) {
        switch command {
        case .switchApplication(let bundleId):
            // TODO: Implement app switching via Accessibility API
            print("Switch to app: \(bundleId)")

        case .openURL(let url):
            if let nsUrl = URL(string: url) {
                NSWorkspace.shared.open(nsUrl)
            }

        case .runAppleScript(let script):
            // TODO: Execute AppleScript safely
            print("Execute AppleScript: \(script)")

        case .takeScreenshot:
            // Send Cmd+Shift+4 for screenshot
            sendCommandToTerminal(KeyCommand(key: "4", modifiers: KeyModifiers(rawValue: KeyModifiers.command.rawValue | KeyModifiers.shift.rawValue)))

        case .toggleFullscreen:
            // Send Cmd+Ctrl+F for fullscreen
            sendCommandToTerminal(KeyCommand(key: "f", modifiers: KeyModifiers(rawValue: KeyModifiers.command.rawValue | KeyModifiers.control.rawValue)))

        case .minimizeWindow:
            // Send Cmd+M to minimize
            sendCommandToTerminal(KeyCommand(key: "m", modifiers: .command))
        }
    }

    private func executeSequence(_ actions: [ButtonAction]) {
        // Execute each action with a small delay between them
        for (index, action) in actions.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * Self.sequenceActionDelay) { [weak self] in
                self?.executeButtonAction(action)
            }
        }
    }

    private func executeShellCommand(_ command: String) {
        // Validate shell command for dangerous patterns
        let dangerousPatterns = [
            "rm -rf /",
            ":(){ :|:& };:",  // fork bomb
            "mkfs",           // format filesystem
            "dd if=/dev/zero",
            "> /dev/sda",
            "wget.*|.*sh",    // download and execute
            "curl.*|.*sh",    // download and execute
        ]

        let trimmedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)

        for pattern in dangerousPatterns {
            if trimmedCommand.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil {
                os_log("SECURITY: Blocked dangerous shell command: %{public}@", log: .default, type: .error, command)
                showSecurityWarning(command: command)
                return
            }
        }

        // Log shell command execution for security audit
        os_log("Executing shell command from PS4 controller: %{public}@", log: .default, type: .info, command)

        // Send the shell command as a text macro with auto-enter
        sendTextMacroToTerminal(trimmedCommand, autoEnter: true)
    }

    private func showSecurityWarning(command: String) {
        let center = UNUserNotificationCenter.current()

        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            guard granted, error == nil else { return }

            let content = UNMutableNotificationContent()
            content.title = "Security Warning"
            content.body = "Blocked potentially dangerous command from PS4 controller"
            content.sound = .defaultCritical

            let request = UNNotificationRequest(
                identifier: "ps4-security-warning-\(UUID().uuidString)",
                content: content,
                trigger: nil
            )

            center.add(request, withCompletionHandler: nil)
        }
    }

    // Enable/disable controller input
    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
    }

    // Toggle visual display
    func toggleVisualizer() {
        showVisualizer.toggle()
    }

    // Handle analog stick input for special commands (optional)
    private func setupAnalogStickHandling() {
        // Monitor left stick for vi-style navigation
        monitor.$leftStickX
            .combineLatest(monitor.$leftStickY)
            .throttle(for: .milliseconds(100), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] x, y in
                guard let self = self, self.isEnabled else { return }

                // Threshold for stick movement
                let threshold: Float = 0.5

                if abs(x) > threshold || abs(y) > threshold {
                    // Determine direction
                    if x > threshold {
                        // Right
                        self.sendArrowKey(.rightArrow)
                    } else if x < -threshold {
                        // Left
                        self.sendArrowKey(.leftArrow)
                    }

                    if y > threshold {
                        // Up
                        self.sendArrowKey(.upArrow)
                    } else if y < -threshold {
                        // Down
                        self.sendArrowKey(.downArrow)
                    }
                }
            }
            .store(in: &cancellables)
    }

    private func sendArrowKey(_ arrow: KeyCommand.SpecialKey) {
        let command = KeyCommand(key: arrow.rawValue, modifiers: [])
        sendCommandToTerminal(command)
    }

    // Preset configurations for different use cases
    func applyPreset(_ preset: ControllerPreset) {
        switch preset {
        case .vim:
            applyVimPreset()
        case .navigation:
            applyNavigationPreset()
        case .terminal:
            applyTerminalPreset()
        case .custom:
            // Keep current custom configuration
            break
        }
    }

    private func applyVimPreset() {
        // Vim-friendly mappings using ButtonAction
        mapping.setMapping(for: .dpadUp, action: .keyCommand(KeyCommand(key: "k", modifiers: [])))
        mapping.setMapping(for: .dpadDown, action: .keyCommand(KeyCommand(key: "j", modifiers: [])))
        mapping.setMapping(for: .dpadLeft, action: .keyCommand(KeyCommand(key: "h", modifiers: [])))
        mapping.setMapping(for: .dpadRight, action: .keyCommand(KeyCommand(key: "l", modifiers: [])))
        mapping.setMapping(for: .cross, action: .keyCommand(KeyCommand(key: KeyCommand.SpecialKey.enter.rawValue, modifiers: [])))
        mapping.setMapping(for: .circle, action: .keyCommand(KeyCommand(key: KeyCommand.SpecialKey.escape.rawValue, modifiers: [])))
        mapping.setMapping(for: .square, action: .keyCommand(KeyCommand(key: "i", modifiers: [])))  // Insert mode
        mapping.setMapping(for: .triangle, action: .keyCommand(KeyCommand(key: "v", modifiers: [])))  // Visual mode
        mapping.setMapping(for: .l1, action: .keyCommand(KeyCommand(key: "u", modifiers: .control)))  // Page up
        mapping.setMapping(for: .r1, action: .keyCommand(KeyCommand(key: "d", modifiers: .control)))  // Page down
        mapping.setMapping(for: .l2, action: .keyCommand(KeyCommand(key: "b", modifiers: [])))  // Word back
        mapping.setMapping(for: .r2, action: .keyCommand(KeyCommand(key: "w", modifiers: [])))  // Word forward
        mapping.setMapping(for: .options, action: .keyCommand(KeyCommand(key: ":", modifiers: [])))  // Command mode
        mapping.setMapping(for: .share, action: .keyCommand(KeyCommand(key: "u", modifiers: [])))  // Undo
        // Add some text macros for common vim commands
        mapping.setMapping(for: .touchpad, action: .textMacro(text: ":wq", autoEnter: true))  // Save and quit
        mapping.setMapping(for: .psButton, action: .textMacro(text: ":q!", autoEnter: true))  // Force quit
    }

    private func applyNavigationPreset() {
        // Standard navigation mappings using ButtonAction
        mapping.setMapping(for: .dpadUp, action: .keyCommand(KeyCommand(key: KeyCommand.SpecialKey.upArrow.rawValue, modifiers: [])))
        mapping.setMapping(for: .dpadDown, action: .keyCommand(KeyCommand(key: KeyCommand.SpecialKey.downArrow.rawValue, modifiers: [])))
        mapping.setMapping(for: .dpadLeft, action: .keyCommand(KeyCommand(key: KeyCommand.SpecialKey.leftArrow.rawValue, modifiers: [])))
        mapping.setMapping(for: .dpadRight, action: .keyCommand(KeyCommand(key: KeyCommand.SpecialKey.rightArrow.rawValue, modifiers: [])))
        mapping.setMapping(for: .cross, action: .keyCommand(KeyCommand(key: KeyCommand.SpecialKey.enter.rawValue, modifiers: [])))
        mapping.setMapping(for: .circle, action: .keyCommand(KeyCommand(key: KeyCommand.SpecialKey.escape.rawValue, modifiers: [])))
        mapping.setMapping(for: .l1, action: .keyCommand(KeyCommand(key: KeyCommand.SpecialKey.pageUp.rawValue, modifiers: [])))
        mapping.setMapping(for: .r1, action: .keyCommand(KeyCommand(key: KeyCommand.SpecialKey.pageDown.rawValue, modifiers: [])))
        mapping.setMapping(for: .l2, action: .keyCommand(KeyCommand(key: KeyCommand.SpecialKey.home.rawValue, modifiers: [])))
        mapping.setMapping(for: .r2, action: .keyCommand(KeyCommand(key: KeyCommand.SpecialKey.end.rawValue, modifiers: [])))
        // Add app commands
        mapping.setMapping(for: .touchpad, action: .applicationCommand(.showUsage))
        mapping.setMapping(for: .psButton, action: .applicationCommand(.togglePS4Panel))
    }

    private func applyTerminalPreset() {
        // Terminal-friendly mappings with mix of key commands and text macros
        mapping.setMapping(for: .cross, action: .keyCommand(KeyCommand(key: KeyCommand.SpecialKey.enter.rawValue, modifiers: [])))
        mapping.setMapping(for: .circle, action: .keyCommand(KeyCommand(key: "c", modifiers: .control)))  // Ctrl+C
        mapping.setMapping(for: .square, action: .keyCommand(KeyCommand(key: "z", modifiers: .control)))  // Ctrl+Z
        mapping.setMapping(for: .triangle, action: .keyCommand(KeyCommand(key: "d", modifiers: .control)))  // Ctrl+D
        mapping.setMapping(for: .l1, action: .keyCommand(KeyCommand(key: "a", modifiers: .control)))  // Beginning of line
        mapping.setMapping(for: .r1, action: .keyCommand(KeyCommand(key: "e", modifiers: .control)))  // End of line
        mapping.setMapping(for: .l2, action: .keyCommand(KeyCommand(key: "u", modifiers: .control)))  // Clear line
        mapping.setMapping(for: .r2, action: .keyCommand(KeyCommand(key: "l", modifiers: .control)))  // Clear screen
        mapping.setMapping(for: .options, action: .keyCommand(KeyCommand(key: KeyCommand.SpecialKey.tab.rawValue, modifiers: [])))
        mapping.setMapping(for: .share, action: .keyCommand(KeyCommand(key: "r", modifiers: .control)))  // Reverse search
        // Add common terminal commands as text macros
        mapping.setMapping(for: .touchpad, action: .textMacro(text: "ls -la", autoEnter: true))
        mapping.setMapping(for: .psButton, action: .textMacro(text: "git status", autoEnter: true))
    }

    private func showConnectionNotification(connected: Bool) {
        let center = UNUserNotificationCenter.current()

        // Request authorization if needed
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                os_log("Failed to request notification authorization: %{public}@", log: .default, type: .error, error.localizedDescription)
                return
            }

            guard granted else { return }

            let content = UNMutableNotificationContent()
            content.title = "PS4 Controller"
            content.sound = .default

            if connected {
                if let batteryLevel = self.monitor.batteryLevel {
                    let percentage = Int(batteryLevel * 100)
                    if batteryLevel == 0 && self.monitor.batteryState == .unknown {
                        content.body = "Controller connected - Battery: Unknown"
                    } else {
                        content.body = "Controller connected - Battery: \(percentage)%"
                    }
                } else {
                    content.body = "Controller connected"
                }
            } else {
                content.body = "Controller disconnected"
            }

            let request = UNNotificationRequest(
                identifier: "ps4-controller-\(UUID().uuidString)",
                content: content,
                trigger: nil
            )

            center.add(request) { error in
                if let error = error {
                    os_log("Failed to deliver notification: %{public}@", log: .default, type: .error, error.localizedDescription)
                }
            }
        }
    }

    deinit {
        // FIX: Comprehensive cleanup to prevent resource leaks

        // Cleanup notification observers
        if let observer = terminalControllerObserver {
            NotificationCenter.default.removeObserver(observer)
        }

        // FIX: Stop any active recording to prevent microphone staying open
        // Critical for battery life and privacy
        if case .recording = pushToTalkState {
            os_log("Controller deallocating during push-to-talk - stopping recording", log: .default, type: .info)
            if let speech = appCommandExecutor.speechController {
                speech.stopRecordingViaController()
            }
        }

        // FIX: Clear callbacks to break reference cycles
        // Without this, monitor could hold strong reference to self via closures
        monitor.onButtonPressed = nil
        monitor.onButtonReleased = nil
    }
}

// Preset configurations
enum ControllerPreset: String, CaseIterable {
    case vim = "Vim"
    case navigation = "Navigation"
    case terminal = "Terminal"
    case custom = "Custom"

    var description: String {
        switch self {
        case .vim:
            return "Optimized for Vim editor navigation"
        case .navigation:
            return "Standard arrow keys and navigation"
        case .terminal:
            return "Common terminal shortcuts"
        case .custom:
            return "Custom user configuration"
        }
    }
}
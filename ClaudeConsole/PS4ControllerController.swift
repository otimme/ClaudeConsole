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

class PS4ControllerController: ObservableObject {
    let monitor = PS4ControllerMonitor()
    let mapping = PS4ButtonMapping()

    @Published var isEnabled = true
    @Published var showVisualizer = true

    private weak var terminalController: LocalProcessTerminalView?
    private var cancellables = Set<AnyCancellable>()
    private var terminalControllerObserver: NSObjectProtocol?

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
                self.executeButtonAction(action)

                // Optional: Provide haptic feedback
                self.monitor.startVibration(intensity: 0.5, duration: 0.05)
            }
        }

        // Handle button releases (if needed for certain commands)
        monitor.onButtonReleased = { [weak self] button in
            guard let self = self, self.isEnabled else { return }

            // Handle special cases for hold-and-release behaviors
            // For example, implementing key repeat for held buttons
            switch button {
            case .dpadUp, .dpadDown, .dpadLeft, .dpadRight:
                // Could stop key repeat here if implemented
                break
            default:
                break
            }
        }
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

        var data = text.data(using: .utf8) ?? Data()
        if autoEnter {
            data.append(Data([0x0D])) // Carriage return
        }
        terminal.send(data: ArraySlice(data))
    }

    private func executeApplicationCommand(_ command: AppCommand) {
        switch command {
        case .triggerSpeechToText:
            // TODO: Integrate with SpeechToTextController
            print("Speech-to-text trigger requested")
            NotificationCenter.default.post(name: Notification.Name("PS4TriggerSpeechToText"), object: nil)

        case .stopSpeechToText:
            // TODO: Integrate with SpeechToTextController
            print("Speech-to-text stop requested")
            NotificationCenter.default.post(name: Notification.Name("PS4StopSpeechToText"), object: nil)

        case .togglePS4Panel:
            showVisualizer.toggle()

        case .toggleStatusBar:
            // TODO: Implement status bar toggle
            NotificationCenter.default.post(name: Notification.Name("PS4ToggleStatusBar"), object: nil)

        case .copyToClipboard:
            // Send Cmd+C to terminal
            sendCommandToTerminal(KeyCommand(key: "c", modifiers: .command))

        case .pasteFromClipboard:
            // Send Cmd+V to terminal
            sendCommandToTerminal(KeyCommand(key: "v", modifiers: .command))

        case .clearTerminal:
            // Send Ctrl+L to clear terminal
            sendCommandToTerminal(KeyCommand(key: "l", modifiers: .control))

        case .showUsage:
            // Send /usage command to Claude
            sendTextMacroToTerminal("/usage", autoEnter: true)

        case .showContext:
            // Send /context command to Claude
            sendTextMacroToTerminal("/context", autoEnter: true)

        case .refreshStats:
            // Post notification to refresh stats
            NotificationCenter.default.post(name: Notification.Name("PS4RefreshStats"), object: nil)
        }
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
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.1) { [weak self] in
                self?.executeButtonAction(action)
            }
        }
    }

    private func executeShellCommand(_ command: String) {
        // Send the shell command as a text macro with auto-enter
        sendTextMacroToTerminal(command, autoEnter: true)
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
        let notification = NSUserNotification()
        notification.title = "PS4 Controller"
        notification.informativeText = connected ? "Controller connected" : "Controller disconnected"
        notification.soundName = NSUserNotificationDefaultSoundName

        if connected {
            if let batteryLevel = monitor.batteryLevel {
                let percentage = Int(batteryLevel * 100)
                // Check if this is an estimated value (DualShock 4 workaround)
                if batteryLevel == 0.5 && monitor.batteryState == .discharging {
                    notification.informativeText = "Controller connected - Battery: ~\(percentage)% (Estimated)"
                } else {
                    notification.informativeText = "Controller connected - Battery: \(percentage)%"
                }
            }
        }

        NSUserNotificationCenter.default.deliver(notification)
    }

    deinit {
        if let observer = terminalControllerObserver {
            NotificationCenter.default.removeObserver(observer)
        }
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
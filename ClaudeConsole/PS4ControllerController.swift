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

            // Get the mapped command for this button
            if let command = self.mapping.getCommand(for: button) {
                self.sendCommandToTerminal(command)

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
        // Vim-friendly mappings
        mapping.setMapping(for: .dpadUp, command: KeyCommand(key: "K", modifiers: []))
        mapping.setMapping(for: .dpadDown, command: KeyCommand(key: "J", modifiers: []))
        mapping.setMapping(for: .dpadLeft, command: KeyCommand(key: "H", modifiers: []))
        mapping.setMapping(for: .dpadRight, command: KeyCommand(key: "L", modifiers: []))
        mapping.setMapping(for: .cross, command: KeyCommand(key: KeyCommand.SpecialKey.enter.rawValue, modifiers: []))
        mapping.setMapping(for: .circle, command: KeyCommand(key: KeyCommand.SpecialKey.escape.rawValue, modifiers: []))
        mapping.setMapping(for: .square, command: KeyCommand(key: "I", modifiers: []))  // Insert mode
        mapping.setMapping(for: .triangle, command: KeyCommand(key: "V", modifiers: []))  // Visual mode
        mapping.setMapping(for: .l1, command: KeyCommand(key: "U", modifiers: .control))  // Page up
        mapping.setMapping(for: .r1, command: KeyCommand(key: "D", modifiers: .control))  // Page down
        mapping.setMapping(for: .l2, command: KeyCommand(key: "B", modifiers: []))  // Word back
        mapping.setMapping(for: .r2, command: KeyCommand(key: "W", modifiers: []))  // Word forward
        mapping.setMapping(for: .options, command: KeyCommand(key: ":", modifiers: []))  // Command mode
        mapping.setMapping(for: .share, command: KeyCommand(key: "U", modifiers: []))  // Undo
    }

    private func applyNavigationPreset() {
        // Standard navigation mappings
        mapping.setMapping(for: .dpadUp, command: KeyCommand(key: KeyCommand.SpecialKey.upArrow.rawValue, modifiers: []))
        mapping.setMapping(for: .dpadDown, command: KeyCommand(key: KeyCommand.SpecialKey.downArrow.rawValue, modifiers: []))
        mapping.setMapping(for: .dpadLeft, command: KeyCommand(key: KeyCommand.SpecialKey.leftArrow.rawValue, modifiers: []))
        mapping.setMapping(for: .dpadRight, command: KeyCommand(key: KeyCommand.SpecialKey.rightArrow.rawValue, modifiers: []))
        mapping.setMapping(for: .cross, command: KeyCommand(key: KeyCommand.SpecialKey.enter.rawValue, modifiers: []))
        mapping.setMapping(for: .circle, command: KeyCommand(key: KeyCommand.SpecialKey.escape.rawValue, modifiers: []))
        mapping.setMapping(for: .l1, command: KeyCommand(key: KeyCommand.SpecialKey.pageUp.rawValue, modifiers: []))
        mapping.setMapping(for: .r1, command: KeyCommand(key: KeyCommand.SpecialKey.pageDown.rawValue, modifiers: []))
        mapping.setMapping(for: .l2, command: KeyCommand(key: KeyCommand.SpecialKey.home.rawValue, modifiers: []))
        mapping.setMapping(for: .r2, command: KeyCommand(key: KeyCommand.SpecialKey.end.rawValue, modifiers: []))
    }

    private func applyTerminalPreset() {
        // Terminal-friendly mappings
        mapping.setMapping(for: .cross, command: KeyCommand(key: KeyCommand.SpecialKey.enter.rawValue, modifiers: []))
        mapping.setMapping(for: .circle, command: KeyCommand(key: "C", modifiers: .control))  // Ctrl+C
        mapping.setMapping(for: .square, command: KeyCommand(key: "Z", modifiers: .control))  // Ctrl+Z
        mapping.setMapping(for: .triangle, command: KeyCommand(key: "D", modifiers: .control))  // Ctrl+D
        mapping.setMapping(for: .l1, command: KeyCommand(key: "A", modifiers: .control))  // Beginning of line
        mapping.setMapping(for: .r1, command: KeyCommand(key: "E", modifiers: .control))  // End of line
        mapping.setMapping(for: .l2, command: KeyCommand(key: "U", modifiers: .control))  // Clear line
        mapping.setMapping(for: .r2, command: KeyCommand(key: "L", modifiers: .control))  // Clear screen
        mapping.setMapping(for: .options, command: KeyCommand(key: KeyCommand.SpecialKey.tab.rawValue, modifiers: []))
        mapping.setMapping(for: .share, command: KeyCommand(key: "R", modifiers: .control))  // Reverse search
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
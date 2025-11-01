//
//  KeyboardMonitor.swift
//  ClaudeConsole
//
//  Monitors keyboard events for push-to-talk functionality
//

import Foundation
import AppKit
import Combine

class KeyboardMonitor: ObservableObject {
    @Published var isRecording = false

    // Default to Right Command key, but this can be made configurable
    private var pushToTalkKeyCode: UInt16 = 54 // Right Command
    private var isKeyPressed = false
    private var localMonitor: Any?

    var onRecordingStarted: (() -> Void)?
    var onRecordingStopped: (() -> Void)?

    init() {
        setupKeyboardMonitoring()
    }

    private func setupKeyboardMonitoring() {
        // Monitor local events (within the app)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
            guard let self = self else { return event }

            // Handle modifier keys (Command, Option, Control, etc.) via flagsChanged
            if event.type == .flagsChanged {
                self.handleModifierKey(event)
                return event
            }

            // Handle regular keys
            if event.keyCode == self.pushToTalkKeyCode {
                if event.type == .keyDown && !event.isARepeat {
                    self.startRecording()
                } else if event.type == .keyUp {
                    self.stopRecording()
                }
                // Don't consume the event, let it pass through
            }

            return event
        }
    }

    private func handleModifierKey(_ event: NSEvent) {
        // Check if Right Command is pressed
        let rightCommandPressed = event.modifierFlags.contains(.command) &&
                                   event.keyCode == 54

        if rightCommandPressed && !isKeyPressed {
            isKeyPressed = true
            startRecording()
        } else if !rightCommandPressed && isKeyPressed {
            isKeyPressed = false
            stopRecording()
        }
    }

    private func startRecording() {
        guard !isRecording else { return }

        DispatchQueue.main.async {
            self.isRecording = true
            self.onRecordingStarted?()
        }
    }

    private func stopRecording() {
        guard isRecording else { return }

        DispatchQueue.main.async {
            self.isRecording = false
            self.onRecordingStopped?()
        }
    }

    // Allow changing the push-to-talk key
    func setPushToTalkKey(_ keyCode: UInt16) {
        self.pushToTalkKeyCode = keyCode
    }

    deinit {
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}

// Common key codes for reference:
// Space: 49
// Right Command: 54
// Right Option: 61
// Function: 63
// F13: 105, F14: 107, F15: 113, F16: 106, F17: 64, F18: 79, F19: 80

//
//  WindowContext.swift
//  ClaudeConsole
//
//  Per-window context providing identity, terminal reference, and input event handling.
//  Each window creates its own WindowContext which registers with SharedResourceManager.
//

import Foundation
import SwiftUI
import SwiftTerm
import Combine
import os.log

/// Per-window context that coordinates hardware input routing and component wiring
final class WindowContext: ObservableObject, WindowCoordinatorProtocol {
    private static let logger = Logger(subsystem: "com.app.ClaudeConsole", category: "WindowContext")

    // MARK: - Window Identity

    /// Unique identifier for this window
    let windowID: UUID

    // MARK: - Focus State

    /// Whether this window currently has focus (is key window)
    @Published var isFocused: Bool = false

    // MARK: - Terminal Controller

    /// Reference to this window's terminal controller
    @Published var terminalController: LocalProcessTerminalView?

    // MARK: - Per-Window Components (to be wired up externally)

    /// Callback when terminal output is received (for ContextMonitor)
    var onTerminalOutput: ((String) -> Void)?

    /// Callback when Claude Code starts (working directory detected)
    var onClaudeStarted: ((String) -> Void)?

    // MARK: - Speech-to-Text State (observed from SharedResourceManager)

    /// Whether recording is in progress (from shared audio recorder)
    @Published var isRecording: Bool = false

    /// Whether transcription is in progress (from shared speech recognition)
    @Published var isTranscribing: Bool = false

    // MARK: - Private

    private var cancellables = Set<AnyCancellable>()
    private var shared: SharedResourceManager { SharedResourceManager.shared }

    // MARK: - Initialization

    init() {
        self.windowID = UUID()

        // Register with SharedResourceManager
        shared.registerWindow(id: windowID, coordinator: self)

        // Observe shared audio/speech state
        setupSharedStateObservers()

        Self.logger.info("WindowContext created: \(self.windowID)")
    }

    deinit {
        // Unregister from SharedResourceManager
        SharedResourceManager.shared.unregisterWindow(id: windowID)

        Self.logger.info("WindowContext destroyed: \(self.windowID)")
    }

    // MARK: - Focus Management

    /// Call when this window becomes the key window
    func windowBecameKey() {
        shared.setFocusedWindow(id: windowID)
        isFocused = true
    }

    /// Call when this window resigns key window status
    func windowResignedKey() {
        isFocused = false
    }

    // MARK: - Shared State Observers

    private func setupSharedStateObservers() {
        // Mirror shared audio recorder's recording state
        shared.audioRecorder.$isRecording
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isRecording in
                // Only update if this window is focused
                guard let self = self, self.isFocused else { return }
                self.isRecording = isRecording
            }
            .store(in: &cancellables)

        // Mirror shared speech recognition's transcribing state
        shared.speechRecognition.$isTranscribing
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isTranscribing in
                // Only update if this window is focused
                guard let self = self, self.isFocused else { return }
                self.isTranscribing = isTranscribing
            }
            .store(in: &cancellables)

        // Update recording/transcribing state when focus changes
        $isFocused
            .sink { [weak self] isFocused in
                guard let self = self else { return }
                if isFocused {
                    // Sync with current shared state
                    self.isRecording = self.shared.audioRecorder.isRecording
                    self.isTranscribing = self.shared.speechRecognition.isTranscribing
                } else {
                    // Clear state when losing focus
                    self.isRecording = false
                    self.isTranscribing = false
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - WindowCoordinatorProtocol

    func handleSpeechRecordingStarted() {
        guard isFocused else {
            Self.logger.warning("Ignoring speech recording start - window not focused")
            return
        }

        Self.logger.debug("Starting speech recording for window: \(self.windowID)")
        _ = shared.startRecording()
    }

    func handleSpeechRecordingStopped() {
        guard isFocused else {
            Self.logger.warning("Ignoring speech recording stop - window not focused")
            return
        }

        Self.logger.debug("Stopping speech recording for window: \(self.windowID)")

        guard let audioURL = shared.stopRecording() else {
            Self.logger.warning("No audio URL returned from recording")
            return
        }

        // Transcribe and insert into terminal
        Task {
            if let transcription = await shared.transcribe(audioURL: audioURL) {
                await insertTextIntoTerminal(transcription)
            }
            shared.cleanupRecording(at: audioURL)
        }
    }

    func handlePS4ButtonPressed(_ button: PS4Button) {
        guard isFocused else { return }

        Self.logger.debug("PS4 button pressed: \(button.rawValue) for window: \(self.windowID)")

        // Post notification for existing PS4ControllerController to handle
        // This maintains backwards compatibility during migration
        NotificationCenter.default.post(
            name: .ps4ButtonPressed,
            object: nil,
            userInfo: ["button": button, "windowID": windowID]
        )
    }

    func handlePS4ButtonReleased(_ button: PS4Button) {
        guard isFocused else { return }

        Self.logger.debug("PS4 button released: \(button.rawValue) for window: \(self.windowID)")

        // Post notification for existing PS4ControllerController to handle
        NotificationCenter.default.post(
            name: .ps4ButtonReleased,
            object: nil,
            userInfo: ["button": button, "windowID": windowID]
        )
    }

    func handleLeftStickChanged(x: Float, y: Float) {
        // Forward to any interested observers
        // Default implementation does nothing
    }

    func handleRightStickChanged(x: Float, y: Float) {
        // Forward to any interested observers
        // Default implementation does nothing
    }

    // MARK: - Terminal Integration

    @MainActor
    private func insertTextIntoTerminal(_ text: String) {
        guard let terminal = terminalController, !text.isEmpty else { return }

        if let data = text.data(using: .utf8) {
            terminal.send(data: ArraySlice(data))
        }
    }

    /// Forward terminal output to observers (called by TerminalView)
    func receiveTerminalOutput(_ text: String) {
        onTerminalOutput?(text)
    }

    /// Forward Claude started event to observers (called by TerminalView)
    func receiveClaudeStarted(workingDirectory: String) {
        onClaudeStarted?(workingDirectory)
    }
}

// MARK: - Notification Names for PS4 Button Events (temporary, for migration)

extension Notification.Name {
    static let ps4ButtonPressed = Notification.Name("ps4ButtonPressed")
    static let ps4ButtonReleased = Notification.Name("ps4ButtonReleased")
}

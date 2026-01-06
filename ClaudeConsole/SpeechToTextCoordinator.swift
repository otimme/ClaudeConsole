//
//  SpeechToTextCoordinator.swift
//  ClaudeConsole
//
//  Per-window speech-to-text coordinator that receives routed events from SharedResourceManager.
//  This is a lightweight facade that uses the shared audio recorder and speech recognition,
//  but routes transcribed text to this specific window's terminal.
//

import Foundation
import SwiftTerm
import Combine
import os.log

/// Per-window coordinator for speech-to-text functionality
/// Receives events routed from SharedResourceManager and inserts transcribed text
/// into this window's terminal
@MainActor
final class SpeechToTextCoordinator: ObservableObject {
    private static let logger = Logger(subsystem: "com.app.ClaudeConsole", category: "SpeechToTextCoordinator")

    // MARK: - Window Identity

    let windowID: UUID

    // MARK: - Terminal Reference

    /// Terminal controller for this window (set by WindowContext)
    weak var terminalController: LocalProcessTerminalView?

    // MARK: - Published State (mirrored from SharedResourceManager)

    @Published var isRecording = false
    @Published var isTranscribing = false
    @Published var isReady = false
    @Published var currentError: SpeechToTextError?

    /// Per-window speech recognition language (defaults to English, not persisted)
    @Published var speechLanguage: SpeechLanguage = .english

    // MARK: - Shared Resources

    private var shared: SharedResourceManager { SharedResourceManager.shared }

    // MARK: - Private State

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init(windowID: UUID) {
        self.windowID = windowID
        setupStateObservers()
        Self.logger.info("SpeechToTextCoordinator created for window: \(windowID)")
    }

    // MARK: - State Observers

    private func setupStateObservers() {
        // Mirror shared audio recorder's recording state - only for focused window
        shared.audioRecorder.$isRecording
            .receive(on: DispatchQueue.main)
            .sink { [weak self] recording in
                guard let self = self else { return }
                // Only show recording indicator in the focused window
                if self.shared.focusedWindowID == self.windowID {
                    self.isRecording = recording
                } else {
                    self.isRecording = false
                }
            }
            .store(in: &cancellables)

        // Mirror shared speech recognition state - only for focused window
        shared.speechRecognition.$isTranscribing
            .receive(on: DispatchQueue.main)
            .sink { [weak self] transcribing in
                guard let self = self else { return }
                // Only show transcribing indicator in the focused window
                if self.shared.focusedWindowID == self.windowID {
                    self.isTranscribing = transcribing
                } else {
                    self.isTranscribing = false
                }
            }
            .store(in: &cancellables)

        // Also update when focus changes
        shared.$focusedWindowID
            .receive(on: DispatchQueue.main)
            .sink { [weak self] focusedID in
                guard let self = self else { return }
                if focusedID == self.windowID {
                    // This window became focused - sync with current state
                    self.isRecording = self.shared.audioRecorder.isRecording
                    self.isTranscribing = self.shared.speechRecognition.isTranscribing
                } else {
                    // This window lost focus - hide indicators
                    self.isRecording = false
                    self.isTranscribing = false
                }
            }
            .store(in: &cancellables)

        shared.speechRecognition.$isInitialized
            .receive(on: DispatchQueue.main)
            .sink { [weak self] initialized in
                self?.isReady = initialized
            }
            .store(in: &cancellables)

        // Mirror errors from speech recognition
        shared.speechRecognition.$currentError
            .receive(on: DispatchQueue.main)
            .sink { [weak self] error in
                if let error = error {
                    self?.currentError = error
                }
            }
            .store(in: &cancellables)

        // Mirror errors from audio recorder
        shared.audioRecorder.$currentError
            .receive(on: DispatchQueue.main)
            .sink { [weak self] error in
                if let error = error {
                    self?.currentError = error
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Recording Control (called by WindowContext)

    /// Start recording - called when this window receives push-to-talk key press
    /// Note: SharedResourceManager routes events only to the focused window, so no focus check needed
    func handleRecordingStarted() {
        guard isReady else {
            Self.logger.warning("Cannot start recording: speech recognition not ready")
            return
        }

        Self.logger.debug("Starting recording for window: \(self.windowID)")
        _ = shared.startRecording()
    }

    /// Stop recording and transcribe - called when this window receives push-to-talk key release
    /// Note: SharedResourceManager routes events only to the focused window, so no focus check needed
    func handleRecordingStopped() {
        Self.logger.debug("Stopping recording for window: \(self.windowID)")

        guard let audioURL = shared.stopRecording() else {
            Self.logger.warning("No audio URL returned from recording")
            return
        }

        // Transcribe and insert into this window's terminal
        let language = self.speechLanguage
        Task {
            if let transcription = await shared.transcribe(audioURL: audioURL, language: language) {
                await insertTextIntoTerminal(transcription)
            }
            shared.cleanupRecording(at: audioURL)
        }
    }

    // MARK: - Controller Integration

    /// Start recording via controller (thread-safe, can be called from any thread)
    nonisolated func startRecordingViaController() {
        Task { @MainActor [weak self] in
            self?.handleRecordingStarted()
        }
    }

    /// Stop recording via controller (thread-safe, can be called from any thread)
    nonisolated func stopRecordingViaController() {
        Task { @MainActor [weak self] in
            self?.handleRecordingStopped()
        }
    }

    /// Toggle recording state (for toggle mode)
    nonisolated func toggleRecordingViaController() {
        Task { @MainActor [weak self] in
            guard let self = self else { return }

            // Don't toggle if transcribing is in progress
            guard !self.isTranscribing else {
                Self.logger.info("Cannot toggle recording while transcribing")
                return
            }

            if self.isRecording {
                self.handleRecordingStopped()
            } else {
                self.handleRecordingStarted()
            }
        }
    }

    // MARK: - Terminal Integration

    private func insertTextIntoTerminal(_ text: String) {
        guard let terminal = terminalController, !text.isEmpty else {
            Self.logger.warning("Cannot insert text: no terminal controller or empty text")
            return
        }

        // Filter out Whisper placeholder strings
        let trimmedText = text.trimmingCharacters(in: .whitespaces)
        if trimmedText == "[INAUDIBLE]" || trimmedText == "[BLANK_AUDIO]" {
            Self.logger.debug("Filtered out placeholder transcription: \(trimmedText)")
            return
        }

        if let data = text.data(using: .utf8) {
            terminal.send(data: ArraySlice(data))
            Self.logger.debug("Inserted transcription into terminal: \(text.prefix(50))...")
        }
    }

    // MARK: - Error Handling

    /// Clear current error
    func clearError() {
        currentError = nil
        shared.speechRecognition.clearError()
        shared.audioRecorder.clearError()
    }

    /// Retry after error
    func retryAfterError() {
        guard let error = currentError else { return }

        clearError()

        switch error {
        case .modelDownloadFailed, .modelInitializationFailed:
            Task {
                await shared.speechRecognition.retryInitialization()
            }
        case .audioRecordingFailed, .emptyAudioFile, .transcriptionFailed, .microphonePermissionDenied:
            // User can simply try recording again
            break
        }
    }
}

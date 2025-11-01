//
//  SpeechToTextController.swift
//  ClaudeConsole
//
//  Orchestrates keyboard monitoring, audio recording, and speech recognition
//

import Foundation
import SwiftTerm
import Combine

class SpeechToTextController: ObservableObject {
    private let keyboardMonitor = KeyboardMonitor()
    private let audioRecorder = AudioRecorder()
    let speechRecognition = SpeechRecognitionManager()

    @Published var isRecording = false
    @Published var isTranscribing = false
    @Published var isReady = false

    private weak var terminalController: LocalProcessTerminalView?
    private var cancellables = Set<AnyCancellable>()

    init() {
        setupKeyboardCallbacks()
        observeSpeechRecognition()

        // Listen for terminal controller
        NotificationCenter.default.addObserver(
            forName: .terminalControllerAvailable,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }
            if let controller = notification.userInfo?["controller"] as? LocalProcessTerminalView {
                self.terminalController = controller
            }
        }
    }

    private func setupKeyboardCallbacks() {
        // When key is pressed, start recording
        keyboardMonitor.onRecordingStarted = { [weak self] in
            self?.startRecording()
        }

        // When key is released, stop recording and transcribe
        keyboardMonitor.onRecordingStopped = { [weak self] in
            self?.stopRecordingAndTranscribe()
        }

        // Observe recording state
        keyboardMonitor.$isRecording
            .receive(on: DispatchQueue.main)
            .sink { [weak self] recording in
                self?.isRecording = recording
            }
            .store(in: &cancellables)
    }

    private func observeSpeechRecognition() {
        speechRecognition.$isInitialized
            .receive(on: DispatchQueue.main)
            .sink { [weak self] initialized in
                self?.isReady = initialized
            }
            .store(in: &cancellables)

        // Observe transcription state
        speechRecognition.$isTranscribing
            .receive(on: DispatchQueue.main)
            .sink { [weak self] transcribing in
                self?.isTranscribing = transcribing
            }
            .store(in: &cancellables)
    }

    private func startRecording() {
        guard isReady else { return }
        audioRecorder.startRecording()
    }

    private func stopRecordingAndTranscribe() {
        guard let audioURL = audioRecorder.stopRecording() else {
            return
        }

        // Transcribe in background
        Task {
            if let transcription = await speechRecognition.transcribe(audioURL: audioURL) {
                await insertTextIntoTerminal(transcription)
            }

            // Clean up audio file
            audioRecorder.cleanupRecording(at: audioURL)
        }
    }

    @MainActor
    private func insertTextIntoTerminal(_ text: String) {
        guard let terminal = terminalController, !text.isEmpty else {
            return
        }

        if let data = text.data(using: .utf8) {
            terminal.send(data: ArraySlice(data))
        }
    }

    // Allow changing the push-to-talk key
    func setPushToTalkKey(_ keyCode: UInt16) {
        keyboardMonitor.setPushToTalkKey(keyCode)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

//
//  AudioRecorder.swift
//  ClaudeConsole
//
//  Handles audio recording for speech-to-text
//

import Foundation
import AVFoundation
import AppKit

class AudioRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
    private var audioRecorder: AVAudioRecorder?
    private var recordingURL: URL?

    @Published var isRecording = false
    @Published var permissionDenied = false
    @Published var hasPermission = false
    @Published var currentError: SpeechToTextError?

    override init() {
        super.init()
        // Request microphone permission on init
        requestMicrophonePermission()
    }

    private func requestMicrophonePermission() {
        // Use AVCaptureDevice to explicitly request permission
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            DispatchQueue.main.async {
                self.hasPermission = true
            }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    self.hasPermission = granted
                    if !granted {
                        self.permissionDenied = true
                    }
                }
            }
        case .denied, .restricted:
            DispatchQueue.main.async {
                self.permissionDenied = true
                self.hasPermission = false
            }
            showPermissionAlert()
        @unknown default:
            break
        }
    }

    func startRecording() {
        guard hasPermission else {
            requestMicrophonePermission()
            DispatchQueue.main.async {
                self.currentError = .microphonePermissionDenied
            }
            return
        }

        // Clear any previous errors
        DispatchQueue.main.async {
            self.currentError = nil
        }

        // Create temporary file for recording
        let tempDir = FileManager.default.temporaryDirectory
        recordingURL = tempDir.appendingPathComponent("recording_\(Date().timeIntervalSince1970).wav")

        guard let url = recordingURL else {
            DispatchQueue.main.async {
                self.currentError = .audioRecordingFailed(reason: "Could not create temporary file.")
            }
            return
        }

        // Configure audio settings for Whisper
        // Whisper expects 16kHz mono audio
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            // On macOS, AVAudioRecorder will automatically trigger permission request
            // when record() is called for the first time
            audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            audioRecorder?.delegate = self

            let success = audioRecorder?.record() ?? false

            if success {
                DispatchQueue.main.async {
                    self.isRecording = true
                    self.permissionDenied = false
                }
            } else {
                DispatchQueue.main.async {
                    self.permissionDenied = true
                    self.currentError = .microphonePermissionDenied
                }
                showPermissionAlert()
            }
        } catch let error as NSError {
            // Check if error is permission-related
            if error.domain == NSOSStatusErrorDomain && error.code == -50 {
                DispatchQueue.main.async {
                    self.permissionDenied = true
                    self.currentError = .microphonePermissionDenied
                }
                showPermissionAlert()
            } else {
                // Other recording errors
                DispatchQueue.main.async {
                    let errorMessage = error.localizedDescription
                    self.currentError = .audioRecordingFailed(reason: errorMessage)
                }
            }
        }
    }

    // AVAudioRecorderDelegate method
    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        // Handle encoding errors during recording
        if let error = error {
            DispatchQueue.main.async {
                self.currentError = .audioRecordingFailed(reason: error.localizedDescription)
                self.isRecording = false
            }
        }
    }

    /// Clear current error (called when user dismisses error banner)
    func clearError() {
        currentError = nil
    }

    private func showPermissionAlert() {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Microphone Permission Required"
            alert.informativeText = "ClaudeConsole needs microphone access for speech-to-text. Please enable it in System Settings > Privacy & Security > Microphone."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Cancel")

            if alert.runModal() == .alertFirstButtonReturn {
                // Open System Settings to Privacy & Security
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
            }
        }
    }

    func stopRecording() -> URL? {
        guard let recorder = audioRecorder, recorder.isRecording else {
            return nil
        }

        recorder.stop()

        DispatchQueue.main.async {
            self.isRecording = false
        }

        return recordingURL
    }

    func cancelRecording() {
        audioRecorder?.stop()

        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
        }

        recordingURL = nil

        DispatchQueue.main.async {
            self.isRecording = false
        }
    }

    // Clean up old recording files
    func cleanupRecording(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}

//
//  SpeechRecognitionManager.swift
//  ClaudeConsole
//
//  Manages WhisperKit for speech-to-text transcription
//

import Foundation
import AVFoundation
import WhisperKit

class SpeechRecognitionManager: ObservableObject {
    private var whisperKit: WhisperKit?
    @Published var isInitialized = false
    @Published var isTranscribing = false
    @Published var isDownloadingModel = false
    @Published var downloadProgress: Double = 0.0
    @Published var isWarmingUp = false
    @Published var currentError: SpeechToTextError?

    init() {
        Task {
            await initializeWhisper()
        }
    }

    private func initializeWhisper() async {
        do {
            await MainActor.run {
                self.isDownloadingModel = true
                self.downloadProgress = 0.0
                self.currentError = nil
            }

            // Simulate progress for better UX (WhisperKit doesn't provide download progress)
            Task {
                for i in 1...20 {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    await MainActor.run {
                        self.downloadProgress = Double(i) * 0.05
                    }
                }
            }

            whisperKit = try await WhisperKit(model: "small")

            await MainActor.run {
                self.isDownloadingModel = false
                self.downloadProgress = 1.0
            }

            await warmUpModel()

            await MainActor.run {
                self.isInitialized = true
            }
        } catch {
            await MainActor.run {
                self.isDownloadingModel = false

                // Determine error reason based on error details
                let errorMessage = error.localizedDescription
                if errorMessage.contains("network") || errorMessage.contains("connection") {
                    self.currentError = .modelDownloadFailed(reason: "Check your internet connection and try again.")
                } else if errorMessage.contains("space") || errorMessage.contains("disk") {
                    self.currentError = .modelDownloadFailed(reason: "Insufficient disk space. The model requires ~500MB.")
                } else {
                    self.currentError = .modelInitializationFailed
                }
            }
        }
    }

    /// Retry model initialization (called from error banner retry button)
    func retryInitialization() async {
        await initializeWhisper()
    }

    private func warmUpModel() async {
        guard let whisper = whisperKit else { return }

        await MainActor.run {
            self.isWarmingUp = true
        }

        do {
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("warmup.wav")

            let sampleRate = 16000.0
            let duration = 1.0
            let numSamples = Int(sampleRate * duration)

            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatLinearPCM),
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsFloatKey: false
            ]

            if let audioFile = try? AVAudioFile(forWriting: tempURL, settings: settings) {
                let format = audioFile.processingFormat
                let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(numSamples))!
                buffer.frameLength = buffer.frameCapacity

                if let data = buffer.int16ChannelData {
                    memset(data[0], 0, Int(buffer.frameLength) * MemoryLayout<Int16>.size)
                }

                try? audioFile.write(from: buffer)
            }

            _ = try await whisper.transcribe(audioPath: tempURL.path)
            try? FileManager.default.removeItem(at: tempURL)
        } catch {
            // Warmup failed, but this is non-critical
        }

        await MainActor.run {
            self.isWarmingUp = false
        }
    }

    func transcribe(audioURL: URL, language: SpeechLanguage? = nil) async -> String? {
        guard let whisper = whisperKit else {
            await MainActor.run {
                self.isTranscribing = false
                self.currentError = .modelInitializationFailed
            }
            return nil
        }

        await MainActor.run {
            self.isTranscribing = true
            self.currentError = nil
        }

        // Check for empty audio file
        if let fileSize = try? FileManager.default.attributesOfItem(atPath: audioURL.path)[.size] as? Int {
            if fileSize == 0 {
                await MainActor.run {
                    self.isTranscribing = false
                    self.currentError = .emptyAudioFile
                }
                return nil
            }
        }

        do {
            // Use provided language or fall back to current setting
            let selectedLanguage = language ?? SpeechLanguageManager.shared.currentLanguage

            let options = DecodingOptions(
                verbose: false,
                language: selectedLanguage.rawValue,
                temperature: 0.0
            )

            let results = try await whisper.transcribe(
                audioPath: audioURL.path,
                decodeOptions: options
            )

            await MainActor.run {
                self.isTranscribing = false
            }

            let transcription = results.first?.text ?? ""
            let trimmed = transcription.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)

            // Check if transcription is empty even though file had data
            if trimmed.isEmpty {
                await MainActor.run {
                    self.currentError = .emptyAudioFile
                }
                return nil
            }

            return trimmed
        } catch {
            await MainActor.run {
                self.isTranscribing = false

                // Determine error reason based on error details
                let errorMessage = error.localizedDescription
                if errorMessage.contains("format") || errorMessage.contains("codec") {
                    self.currentError = .transcriptionFailed(reason: "Audio format not supported.")
                } else if errorMessage.contains("corrupted") || errorMessage.contains("invalid") {
                    self.currentError = .transcriptionFailed(reason: "Audio file appears to be corrupted.")
                } else {
                    self.currentError = .transcriptionFailed(reason: "Please try recording again.")
                }
            }
            return nil
        }
    }

    /// Clear current error (called when user dismisses error banner)
    func clearError() {
        currentError = nil
    }
}

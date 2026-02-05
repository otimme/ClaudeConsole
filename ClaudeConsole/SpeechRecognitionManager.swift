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
    @Published var isLoadingModel = false
    @Published var isWarmingUp = false
    @Published var currentError: SpeechToTextError?

    private static let modelName = "openai_whisper-small"
    private static let requiredModelFiles = [
        "AudioEncoder.mlmodelc",
        "TextDecoder.mlmodelc",
        "MelSpectrogram.mlmodelc"
    ]

    /// Persistent model directory in Application Support
    private static var persistentModelDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport
            .appendingPathComponent("ClaudeConsole", isDirectory: true)
            .appendingPathComponent("WhisperModels", isDirectory: true)
    }

    /// Full path to the persistent model folder
    private static var persistentModelFolder: URL {
        persistentModelDirectory.appendingPathComponent(modelName, isDirectory: true)
    }

    /// Check if all required model files exist in the persistent location
    private static func persistentModelExists() -> Bool {
        let fm = FileManager.default
        let folder = persistentModelFolder.path
        return requiredModelFiles.allSatisfy { file in
            fm.fileExists(atPath: (folder as NSString).appendingPathComponent(file))
        }
    }

    init() {
        Task {
            await initializeWhisper()
        }
    }

    private func initializeWhisper() async {
        do {
            await MainActor.run {
                self.currentError = nil
            }

            let persistentFolder = Self.persistentModelFolder

            if Self.persistentModelExists() {
                await MainActor.run {
                    self.isLoadingModel = true
                }

                whisperKit = try await WhisperKit(
                    model: "small",
                    modelFolder: persistentFolder.path,
                    tokenizerFolder: Self.persistentModelDirectory
                )

                await MainActor.run {
                    self.isLoadingModel = false
                }
            } else {
                await MainActor.run {
                    self.isDownloadingModel = true
                    self.downloadProgress = 0.0
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

                whisperKit = try await WhisperKit(
                    model: "small",
                    tokenizerFolder: Self.persistentModelDirectory
                )

                if let downloadedFolder = whisperKit?.modelFolder {
                    await copyModelToPersistentStorage(from: downloadedFolder)
                }

                await MainActor.run {
                    self.isDownloadingModel = false
                    self.downloadProgress = 1.0
                }
            }

            await warmUpModel()

            await MainActor.run {
                self.isInitialized = true
            }
        } catch {
            await MainActor.run {
                self.isDownloadingModel = false
                self.isLoadingModel = false

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

    /// Copy downloaded model files to the persistent Application Support location
    private func copyModelToPersistentStorage(from sourceFolder: URL) async {
        let fm = FileManager.default
        let destination = Self.persistentModelFolder

        do {
            // Create parent directories
            try fm.createDirectory(at: destination, withIntermediateDirectories: true)

            let contents = try fm.contentsOfDirectory(at: sourceFolder, includingPropertiesForKeys: nil)
            for item in contents {
                let destItem = destination.appendingPathComponent(item.lastPathComponent)
                if fm.fileExists(atPath: destItem.path) {
                    try fm.removeItem(at: destItem)
                }
                try fm.copyItem(at: item, to: destItem)
            }

        } catch {
            // Non-fatal: model will still work, just won't be cached for next launch
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

    func transcribe(audioURL: URL, language: SpeechLanguage = .english) async -> String? {
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
            let options = DecodingOptions(
                verbose: false,
                language: language.rawValue,
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

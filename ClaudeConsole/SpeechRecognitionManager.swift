//
//  SpeechRecognitionManager.swift
//  ClaudeConsole
//
//  Manages WhisperKit for speech-to-text transcription
//

import Foundation
import AVFoundation
import WhisperKit

enum ModelPreparationStep: Int, CaseIterable {
    case downloading = 0
    case loading = 1
    case optimizing = 2
    case warmingUp = 3

    var label: String {
        switch self {
        case .downloading: return "DOWNLOADING MODEL"
        case .loading: return "LOADING MODEL FILES"
        case .optimizing: return "OPTIMIZING FOR HARDWARE"
        case .warmingUp: return "WARMING UP ENGINE"
        }
    }

    var detail: String {
        switch self {
        case .downloading: return "~500MB FROM HUGGINGFACE"
        case .loading: return "READING COREML BUNDLES"
        case .optimizing: return "NEURAL ENGINE + GPU SPECIALIZATION"
        case .warmingUp: return "RUNNING FIRST INFERENCE"
        }
    }
}

class SpeechRecognitionManager: ObservableObject {
    private var whisperKit: WhisperKit?
    @Published var isInitialized = false
    @Published var isTranscribing = false
    @Published var preparationStep: ModelPreparationStep? = nil
    @Published var downloadProgress: Double = 0.0
    @Published var currentError: SpeechToTextError?

    private static let modelName = "openai_whisper-small"

    // Track macOS build version to detect OS updates that invalidate CoreML specialization cache
    private static var cachedOSBuild: String? {
        get { UserDefaults.standard.string(forKey: "whisper_model_os_build") }
        set { UserDefaults.standard.set(newValue, forKey: "whisper_model_os_build") }
    }

    private static var currentOSBuild: String {
        var size = 0
        sysctlbyname("kern.osversion", nil, &size, nil, 0)
        var version = [CChar](repeating: 0, count: size)
        sysctlbyname("kern.osversion", &version, &size, nil, 0)
        return String(cString: version)
    }

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

    /// Full path to the persistent model folder (standardized for stable CoreML cache key)
    private static var persistentModelFolder: URL {
        persistentModelDirectory
            .appendingPathComponent(modelName, isDirectory: true)
            .standardizedFileURL
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

    /// Whether the download flow is needed (no cached model)
    var needsDownload: Bool {
        !Self.persistentModelExists()
    }

    private func initializeWhisper() async {
        do {
            await MainActor.run {
                self.currentError = nil
            }

            let persistentFolder = Self.persistentModelFolder

            if Self.persistentModelExists() {
                // Cached path: load → optimize → warmup
                await MainActor.run {
                    self.preparationStep = .loading
                }

                let startTime = CFAbsoluteTimeGetCurrent()

                // Loading and optimization happen together in WhisperKit init
                await MainActor.run {
                    self.preparationStep = .optimizing
                }

                whisperKit = try await WhisperKit(
                    model: "small",
                    modelFolder: persistentFolder.path,
                    tokenizerFolder: Self.persistentModelDirectory
                )
                let elapsed = CFAbsoluteTimeGetCurrent() - startTime

                if elapsed > 5.0 {
                    print("[WhisperKit] Model required device specialization (\(String(format: "%.1f", elapsed))s)")
                } else {
                    print("[WhisperKit] Model loaded from cache (\(String(format: "%.1f", elapsed))s)")
                }

                Self.cachedOSBuild = Self.currentOSBuild
            } else {
                // Download path: WhisperKit handles download + load + optimize in one call
                await MainActor.run {
                    self.preparationStep = .downloading
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

                Self.cachedOSBuild = Self.currentOSBuild
            }

            await warmUpModel()

            await MainActor.run {
                self.preparationStep = nil
                self.isInitialized = true
            }
        } catch {
            await MainActor.run {
                self.preparationStep = nil

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

            let contents = try fm.contentsOfDirectory(at: sourceFolder, includingPropertiesForKeys: [.fileSizeKey])
            for item in contents {
                let destItem = destination.appendingPathComponent(item.lastPathComponent)
                // Skip files that already exist with the same size to preserve timestamps
                // (changed timestamps invalidate CoreML's device specialization cache)
                if fm.fileExists(atPath: destItem.path),
                   let srcSize = try? fm.attributesOfItem(atPath: item.path)[.size] as? Int,
                   let dstSize = try? fm.attributesOfItem(atPath: destItem.path)[.size] as? Int,
                   srcSize == dstSize {
                    continue
                }
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
            self.preparationStep = .warmingUp
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

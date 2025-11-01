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
            }
        }
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

    func transcribe(audioURL: URL) async -> String? {
        guard let whisper = whisperKit else {
            await MainActor.run {
                self.isTranscribing = false
            }
            return nil
        }

        await MainActor.run {
            self.isTranscribing = true
        }

        if let fileSize = try? FileManager.default.attributesOfItem(atPath: audioURL.path)[.size] as? Int {
            if fileSize == 0 {
                await MainActor.run {
                    self.isTranscribing = false
                }
                return nil
            }
        }

        do {
            let options = DecodingOptions(
                verbose: false,
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
            return transcription.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        } catch {
            await MainActor.run {
                self.isTranscribing = false
            }
            return nil
        }
    }
}

//
//  ContentView.swift
//  ClaudeConsole
//
//  Created by Olaf Timme on 31/10/2025.
//

import SwiftUI
import SwiftTerm

struct ContentView: View {
    @StateObject private var usageMonitor = UsageMonitor()
    @StateObject private var contextMonitor = ContextMonitor()
    @StateObject private var speechToText = SpeechToTextController()
    @State private var terminalController: LocalProcessTerminalView?

    var body: some View {
        VStack(spacing: 0) {
            // Real usage stats from /usage command
            RealUsageStatsView(usageMonitor: usageMonitor)
                .frame(height: 70)
                .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Terminal in the middle with speech-to-text overlay
            ZStack(alignment: .bottomTrailing) {
                TerminalView(terminalController: $terminalController)
                    .frame(minWidth: 800, minHeight: 400)

                // Model download indicator (center)
                if speechToText.speechRecognition.isDownloadingModel {
                    ModelDownloadIndicator(
                        progress: speechToText.speechRecognition.downloadProgress
                    )
                }

                // Model warmup indicator (center)
                if speechToText.speechRecognition.isWarmingUp {
                    ModelWarmupIndicator()
                }

                // Speech-to-text status indicator (bottom-right)
                if speechToText.isRecording || speechToText.isTranscribing {
                    SpeechStatusIndicator(
                        isRecording: speechToText.isRecording,
                        isTranscribing: speechToText.isTranscribing
                    )
                    .padding(16)
                }
            }

            Divider()

            // Context usage statistics
            ContextStatsView(contextMonitor: contextMonitor)
                .frame(height: 60)
                .background(Color(NSColor.controlBackgroundColor))
        }
        .frame(minWidth: 800, minHeight: 600)
    }
}

// Model download indicator (center of terminal)
struct ModelDownloadIndicator: View {
    let progress: Double

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(1.2)
                .progressViewStyle(.circular)

            Text("Downloading Whisper Model...")
                .font(.headline)
                .foregroundColor(.white)

            if progress > 0 {
                ProgressView(value: progress, total: 1.0)
                    .frame(width: 200)
                    .tint(.blue)

                Text("\(Int(progress * 100))%")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
            }

            Text("~500MB • First run only")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.6))
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.black.opacity(0.85))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                )
        )
        .shadow(radius: 20)
    }
}

// Model warmup indicator
struct ModelWarmupIndicator: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(1.2)
                .progressViewStyle(.circular)

            Text("Optimizing for Neural Engine...")
                .font(.headline)
                .foregroundColor(.white)

            Text("Compiling model for your Mac")
                .font(.caption)
                .foregroundColor(.white.opacity(0.8))

            Text("~10 seconds • First run only")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.6))
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.black.opacity(0.85))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.green.opacity(0.3), lineWidth: 1)
                )
        )
        .shadow(radius: 20)
    }
}

// Visual indicator for speech-to-text status
struct SpeechStatusIndicator: View {
    let isRecording: Bool
    let isTranscribing: Bool

    var body: some View {
        HStack(spacing: 8) {
            if isRecording {
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
                    .overlay(
                        Circle()
                            .stroke(Color.red, lineWidth: 2)
                            .scaleEffect(1.5)
                            .opacity(0.5)
                    )

                Text("Recording...")
                    .font(.caption)
                    .foregroundColor(.white)
            } else if isTranscribing {
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 12, height: 12)

                Text("Transcribing...")
                    .font(.caption)
                    .foregroundColor(.white)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.75))
        .cornerRadius(20)
    }
}

#Preview {
    ContentView()
}

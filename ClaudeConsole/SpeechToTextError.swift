//
//  SpeechToTextError.swift
//  ClaudeConsole
//
//  Defines error types and UI components for speech-to-text feature
//

import SwiftUI

// MARK: - Error Types

/// Represents all possible errors in the speech-to-text pipeline
enum SpeechToTextError: Identifiable, Equatable {
    case modelDownloadFailed(reason: String)
    case modelInitializationFailed
    case audioRecordingFailed(reason: String)
    case transcriptionFailed(reason: String)
    case emptyAudioFile
    case microphonePermissionDenied

    var id: String {
        switch self {
        case .modelDownloadFailed: return "modelDownload"
        case .modelInitializationFailed: return "modelInit"
        case .audioRecordingFailed: return "audioRecording"
        case .transcriptionFailed: return "transcription"
        case .emptyAudioFile: return "emptyAudio"
        case .microphonePermissionDenied: return "micPermission"
        }
    }

    /// User-friendly error message
    var title: String {
        switch self {
        case .modelDownloadFailed:
            return "Model Download Failed"
        case .modelInitializationFailed:
            return "Model Initialization Failed"
        case .audioRecordingFailed:
            return "Recording Failed"
        case .transcriptionFailed:
            return "Transcription Failed"
        case .emptyAudioFile:
            return "No Audio Detected"
        case .microphonePermissionDenied:
            return "Microphone Permission Required"
        }
    }

    /// Detailed user-friendly description
    var message: String {
        switch self {
        case .modelDownloadFailed(let reason):
            return "Failed to download the Whisper speech recognition model. \(reason)"
        case .modelInitializationFailed:
            return "The speech recognition model couldn't be initialized. This might be due to insufficient disk space or a corrupted download."
        case .audioRecordingFailed(let reason):
            return "Audio recording couldn't start. \(reason)"
        case .transcriptionFailed(let reason):
            return "The audio couldn't be transcribed. \(reason)"
        case .emptyAudioFile:
            return "The recorded audio file was empty. Try speaking closer to your microphone or checking your input volume."
        case .microphonePermissionDenied:
            return "ClaudeConsole needs microphone access to use speech-to-text. Please enable it in System Settings."
        }
    }

    /// Whether this error allows retry
    var canRetry: Bool {
        switch self {
        case .modelDownloadFailed, .audioRecordingFailed, .transcriptionFailed, .emptyAudioFile:
            return true
        case .modelInitializationFailed, .microphonePermissionDenied:
            return false
        }
    }

    /// Icon name for the error
    var iconName: String {
        switch self {
        case .modelDownloadFailed, .modelInitializationFailed:
            return "arrow.down.circle.fill"
        case .audioRecordingFailed, .emptyAudioFile:
            return "mic.slash.fill"
        case .transcriptionFailed:
            return "text.badge.xmark"
        case .microphonePermissionDenied:
            return "lock.fill"
        }
    }

    /// Icon color for the error
    var iconColor: Color {
        switch self {
        case .emptyAudioFile:
            return .orange
        case .microphonePermissionDenied:
            return .yellow
        default:
            return .red
        }
    }

    /// Error severity level
    enum Severity {
        case warning    // Non-critical, informational errors (auto-dismiss)
        case critical   // Serious errors requiring user attention (manual dismiss only)
    }

    /// Determines if this error is a warning (auto-dismissible) or critical (requires manual dismissal)
    var severity: Severity {
        switch self {
        case .emptyAudioFile:
            // Empty audio is a warning - user just didn't speak or spoke too quietly
            return .warning
        case .modelDownloadFailed, .modelInitializationFailed, .audioRecordingFailed,
             .transcriptionFailed, .microphonePermissionDenied:
            // These require user intervention or indicate serious problems
            return .critical
        }
    }

    /// Duration in seconds before auto-dismissal (only applies to warnings)
    var autoDismissDelay: TimeInterval {
        return 3.0
    }
}

// MARK: - Error Banner UI Component

/// A subtle, non-blocking error banner that appears at the top of the terminal area
struct ErrorBanner: View {
    let error: SpeechToTextError
    let onDismiss: () -> Void
    let onRetry: (() -> Void)?

    @State private var isVisible = false
    @State private var autoDismissTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // Error icon
                Image(systemName: error.iconName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(error.iconColor)

                // Error content
                VStack(alignment: .leading, spacing: 4) {
                    Text(error.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)

                    Text(error.message)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                // Action buttons
                HStack(spacing: 8) {
                    // Retry button (if applicable)
                    if error.canRetry, let retry = onRetry {
                        Button(action: {
                            // Cancel auto-dismiss before retrying
                            autoDismissTask?.cancel()
                            autoDismissTask = nil

                            withAnimation(.easeOut(duration: 0.2)) {
                                isVisible = false
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                retry()
                            }
                        }) {
                            Text("Retry")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.blue.opacity(0.8))
                                )
                        }
                        .buttonStyle(.plain)
                    }

                    // Open System Settings for permission error
                    if error == .microphonePermissionDenied {
                        Button(action: {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                                NSWorkspace.shared.open(url)
                            }
                        }) {
                            Text("Open Settings")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.blue.opacity(0.8))
                                )
                        }
                        .buttonStyle(.plain)
                    }

                    // Dismiss button
                    Button(action: {
                        dismissBanner()
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white.opacity(0.7))
                            .padding(6)
                            .background(
                                Circle()
                                    .fill(Color.white.opacity(0.1))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black.opacity(0.9))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(error.iconColor.opacity(0.3), lineWidth: 1)
                    )
            )
            .shadow(color: .black.opacity(0.3), radius: 10, y: 5)
            .padding(.horizontal, 16)
            .padding(.top, 16)
        }
        .offset(y: isVisible ? 0 : -100)
        .opacity(isVisible ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                isVisible = true
            }

            // Start auto-dismiss timer for warning-level errors
            if error.severity == .warning {
                startAutoDismissTimer()
            }
        }
        .onDisappear {
            // Clean up auto-dismiss task when view disappears
            autoDismissTask?.cancel()
            autoDismissTask = nil
        }
    }

    // MARK: - Helper Methods

    /// Dismisses the banner with animation and cancels any pending auto-dismiss
    private func dismissBanner() {
        // Cancel auto-dismiss task if it's still running
        autoDismissTask?.cancel()
        autoDismissTask = nil

        withAnimation(.easeOut(duration: 0.2)) {
            isVisible = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            onDismiss()
        }
    }

    /// Starts the auto-dismiss timer for warning-level errors
    private func startAutoDismissTimer() {
        autoDismissTask = Task { @MainActor in
            do {
                // Wait for the specified delay duration
                try await Task.sleep(nanoseconds: UInt64(error.autoDismissDelay * 1_000_000_000))

                // Check if task wasn't cancelled during sleep
                guard !Task.isCancelled else { return }

                // Auto-dismiss the banner
                withAnimation(.easeOut(duration: 0.2)) {
                    isVisible = false
                }

                // Wait for animation to complete before calling onDismiss
                try await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds

                guard !Task.isCancelled else { return }
                onDismiss()
            } catch {
                // Task was cancelled or sleep was interrupted - this is expected
                // when user manually dismisses or interacts with the banner
            }
        }
    }
}

// MARK: - Preview

#Preview("Model Download Error") {
    ZStack {
        Color.gray.opacity(0.2)

        ErrorBanner(
            error: .modelDownloadFailed(reason: "Network connection lost."),
            onDismiss: {},
            onRetry: {}
        )
    }
    .frame(width: 800, height: 400)
}

#Preview("Transcription Error") {
    ZStack {
        Color.gray.opacity(0.2)

        ErrorBanner(
            error: .transcriptionFailed(reason: "Audio format not supported."),
            onDismiss: {},
            onRetry: {}
        )
    }
    .frame(width: 800, height: 400)
}

#Preview("Permission Error") {
    ZStack {
        Color.gray.opacity(0.2)

        ErrorBanner(
            error: .microphonePermissionDenied,
            onDismiss: {},
            onRetry: nil
        )
    }
    .frame(width: 800, height: 400)
}

#Preview("Empty Audio") {
    ZStack {
        Color.gray.opacity(0.2)

        ErrorBanner(
            error: .emptyAudioFile,
            onDismiss: {},
            onRetry: {}
        )
    }
    .frame(width: 800, height: 400)
}

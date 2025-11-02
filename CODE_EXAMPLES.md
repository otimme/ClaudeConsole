# Error Handling Code Examples

## Real Code Snippets from Implementation

This document shows actual code snippets from the implementation to help understand how the error handling works.

## 1. Error Type Definition

### SpeechToTextError.swift

```swift
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
}
```

## 2. ErrorBanner UI Component

### SpeechToTextError.swift (continued)

```swift
/// A subtle, non-blocking error banner that appears at the top of the terminal area
struct ErrorBanner: View {
    let error: SpeechToTextError
    let onDismiss: () -> Void
    let onRetry: (() -> Void)?

    @State private var isVisible = false

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

                    // Dismiss button
                    Button(action: {
                        withAnimation(.easeOut(duration: 0.2)) {
                            isVisible = false
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            onDismiss()
                        }
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
        }
    }
}
```

## 3. Setting Errors in Managers

### SpeechRecognitionManager.swift

```swift
class SpeechRecognitionManager: ObservableObject {
    @Published var currentError: SpeechToTextError?

    private func initializeWhisper() async {
        do {
            await MainActor.run {
                self.isDownloadingModel = true
                self.downloadProgress = 0.0
                self.currentError = nil  // Clear previous errors
            }

            whisperKit = try await WhisperKit(model: "small")

            await MainActor.run {
                self.isDownloadingModel = false
                self.downloadProgress = 1.0
                self.isInitialized = true
            }
        } catch {
            await MainActor.run {
                self.isDownloadingModel = false

                // Determine error reason based on error details
                let errorMessage = error.localizedDescription
                if errorMessage.contains("network") || errorMessage.contains("connection") {
                    self.currentError = .modelDownloadFailed(
                        reason: "Check your internet connection and try again."
                    )
                } else if errorMessage.contains("space") || errorMessage.contains("disk") {
                    self.currentError = .modelDownloadFailed(
                        reason: "Insufficient disk space. The model requires ~500MB."
                    )
                } else {
                    self.currentError = .modelInitializationFailed
                }
            }
        }
    }

    func transcribe(audioURL: URL) async -> String? {
        guard let whisper = whisperKit else {
            await MainActor.run {
                self.isTranscribing = false
                self.currentError = .modelInitializationFailed
            }
            return nil
        }

        await MainActor.run {
            self.isTranscribing = true
            self.currentError = nil  // Clear previous errors
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
            let results = try await whisper.transcribe(audioPath: audioURL.path)

            await MainActor.run {
                self.isTranscribing = false
            }

            let transcription = results.first?.text ?? ""
            let trimmed = transcription.trimmingCharacters(in: .whitespacesAndNewlines)

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
                    self.currentError = .transcriptionFailed(
                        reason: "Audio format not supported."
                    )
                } else if errorMessage.contains("corrupted") || errorMessage.contains("invalid") {
                    self.currentError = .transcriptionFailed(
                        reason: "Audio file appears to be corrupted."
                    )
                } else {
                    self.currentError = .transcriptionFailed(
                        reason: "Please try recording again."
                    )
                }
            }
            return nil
        }
    }
}
```

### AudioRecorder.swift

```swift
class AudioRecorder: NSObject, ObservableObject {
    @Published var currentError: SpeechToTextError?

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

        guard let url = recordingURL else {
            DispatchQueue.main.async {
                self.currentError = .audioRecordingFailed(
                    reason: "Could not create temporary file."
                )
            }
            return
        }

        do {
            audioRecorder = try AVAudioRecorder(url: url, settings: settings)
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
            }
        } catch let error as NSError {
            if error.domain == NSOSStatusErrorDomain && error.code == -50 {
                DispatchQueue.main.async {
                    self.permissionDenied = true
                    self.currentError = .microphonePermissionDenied
                }
            } else {
                DispatchQueue.main.async {
                    self.currentError = .audioRecordingFailed(
                        reason: error.localizedDescription
                    )
                }
            }
        }
    }
}
```

## 4. Error Propagation with Combine

### SpeechToTextController.swift

```swift
class SpeechToTextController: ObservableObject {
    private let audioRecorder = AudioRecorder()
    let speechRecognition = SpeechRecognitionManager()

    @Published var currentError: SpeechToTextError?

    private var cancellables = Set<AnyCancellable>()

    init() {
        setupKeyboardCallbacks()
        observeSpeechRecognition()
    }

    private func observeSpeechRecognition() {
        // Observe errors from speech recognition
        speechRecognition.$currentError
            .receive(on: DispatchQueue.main)
            .sink { [weak self] error in
                if let error = error {
                    self?.currentError = error
                }
            }
            .store(in: &cancellables)

        // Observe errors from audio recorder
        audioRecorder.$currentError
            .receive(on: DispatchQueue.main)
            .sink { [weak self] error in
                if let error = error {
                    self?.currentError = error
                }
            }
            .store(in: &cancellables)
    }

    /// Clear current error (called when user dismisses error banner)
    func clearError() {
        currentError = nil
        speechRecognition.clearError()
        audioRecorder.clearError()
    }

    /// Retry after error (called from error banner retry button)
    func retryAfterError() {
        guard let error = currentError else { return }

        // Clear errors first
        clearError()

        // Retry based on error type
        switch error {
        case .modelDownloadFailed, .modelInitializationFailed:
            // Retry model initialization
            Task {
                await speechRecognition.retryInitialization()
            }
        case .audioRecordingFailed, .emptyAudioFile:
            // User can simply try recording again - no specific action needed
            break
        case .transcriptionFailed:
            // User can try recording again - no specific action needed
            break
        case .microphonePermissionDenied:
            // User needs to grant permission in System Settings
            break
        }
    }
}
```

## 5. UI Integration

### ContentView.swift

```swift
struct ContentView: View {
    @StateObject private var speechToText = SpeechToTextController()

    var body: some View {
        VStack(spacing: 0) {
            // Usage stats view
            RealUsageStatsView(usageMonitor: usageMonitor)
                .frame(height: 70)

            Divider()

            // Terminal in the middle with speech-to-text overlay
            ZStack(alignment: .top) {
                TerminalView(terminalController: $terminalController)
                    .frame(minWidth: 800, minHeight: 400)

                // Error banner (top)
                if let error = speechToText.currentError {
                    ErrorBanner(
                        error: error,
                        onDismiss: {
                            speechToText.clearError()
                        },
                        onRetry: error.canRetry ? {
                            speechToText.retryAfterError()
                        } : nil
                    )
                    .zIndex(100) // Ensure it appears above other content
                }

                // Model download indicator (center)
                if speechToText.speechRecognition.isDownloadingModel {
                    ModelDownloadIndicator(
                        progress: speechToText.speechRecognition.downloadProgress
                    )
                }

                // Speech-to-text status indicator (bottom-right)
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        if speechToText.isRecording || speechToText.isTranscribing {
                            SpeechStatusIndicator(
                                isRecording: speechToText.isRecording,
                                isTranscribing: speechToText.isTranscribing
                            )
                            .padding(16)
                        }
                    }
                }
            }

            Divider()

            // Context stats view
            ContextStatsView(contextMonitor: contextMonitor)
                .frame(height: 60)
        }
    }
}
```

## 6. Usage Examples

### Triggering an Error Programmatically

```swift
// Example 1: Network error during model download
await MainActor.run {
    self.currentError = .modelDownloadFailed(
        reason: "Check your internet connection and try again."
    )
}

// Example 2: Empty audio file
await MainActor.run {
    self.currentError = .emptyAudioFile
}

// Example 3: Permission denied
DispatchQueue.main.async {
    self.currentError = .microphonePermissionDenied
}

// Example 4: Transcription failure
await MainActor.run {
    self.currentError = .transcriptionFailed(
        reason: "Audio format not supported."
    )
}
```

### Clearing an Error

```swift
// From controller
speechToText.clearError()

// From manager
speechRecognition.clearError()
audioRecorder.clearError()
```

### Retrying After Error

```swift
// User clicks retry button
speechToText.retryAfterError()

// Which internally does:
switch error {
case .modelDownloadFailed, .modelInitializationFailed:
    Task {
        await speechRecognition.retryInitialization()
    }
case .audioRecordingFailed, .emptyAudioFile, .transcriptionFailed:
    // Just clear error, user will try recording again
    break
case .microphonePermissionDenied:
    // User needs to grant permission manually
    break
}
```

## 7. Preview Code for Testing

### SpeechToTextError.swift (Preview Support)

```swift
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
```

## 8. Complete Error Flow Example

```swift
// 1. User presses push-to-talk key
keyboardMonitor.onRecordingStarted = { [weak self] in
    self?.startRecording()
}

// 2. Recording starts (no permission)
func startRecording() {
    guard hasPermission else {
        // ERROR SET HERE
        DispatchQueue.main.async {
            self.currentError = .microphonePermissionDenied
        }
        return
    }
}

// 3. Error propagates via Combine
audioRecorder.$currentError
    .receive(on: DispatchQueue.main)
    .sink { [weak self] error in
        if let error = error {
            // ERROR RECEIVED IN CONTROLLER
            self?.currentError = error
        }
    }
    .store(in: &cancellables)

// 4. UI observes controller error
if let error = speechToText.currentError {
    // ERROR BANNER DISPLAYS
    ErrorBanner(
        error: error,
        onDismiss: { speechToText.clearError() },
        onRetry: nil  // Permission errors can't be retried
    )
}

// 5. User clicks "Open Settings"
Button("Open Settings") {
    NSWorkspace.shared.open(
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
    )
}

// 6. User clicks "Dismiss"
Button("Dismiss") {
    speechToText.clearError()
    // Banner animates out and disappears
}
```

## 9. Thread Safety Example

```swift
// ✅ CORRECT - Always use MainActor for UI updates
private func initializeWhisper() async {
    do {
        whisperKit = try await WhisperKit(model: "small")

        await MainActor.run {
            self.isInitialized = true
            self.currentError = nil  // ✅ On main thread
        }
    } catch {
        await MainActor.run {
            self.currentError = .modelInitializationFailed  // ✅ On main thread
        }
    }
}

// ✅ CORRECT - DispatchQueue.main.async for non-async contexts
func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
    if let error = error {
        DispatchQueue.main.async {
            self.currentError = .audioRecordingFailed(reason: error.localizedDescription)
            // ✅ On main thread
        }
    }
}

// ❌ WRONG - Never update @Published from background thread
func badExample() {
    DispatchQueue.global().async {
        self.currentError = .someError  // ❌ Will crash or cause issues
    }
}
```

## 10. Equatable Conformance

```swift
// SpeechToTextError conforms to Equatable for comparison
extension SpeechToTextError: Equatable {
    static func == (lhs: SpeechToTextError, rhs: SpeechToTextError) -> Bool {
        switch (lhs, rhs) {
        case (.modelDownloadFailed(let lReason), .modelDownloadFailed(let rReason)):
            return lReason == rReason
        case (.modelInitializationFailed, .modelInitializationFailed):
            return true
        case (.audioRecordingFailed(let lReason), .audioRecordingFailed(let rReason)):
            return lReason == rReason
        case (.transcriptionFailed(let lReason), .transcriptionFailed(let rReason)):
            return lReason == rReason
        case (.emptyAudioFile, .emptyAudioFile):
            return true
        case (.microphonePermissionDenied, .microphonePermissionDenied):
            return true
        default:
            return false
        }
    }
}

// Usage
if error == .microphonePermissionDenied {
    // Show "Open Settings" button
}
```

## Summary

These code examples show the complete implementation:

1. **Error Types**: Enum with associated values for context
2. **UI Component**: SwiftUI view with animations
3. **Error Detection**: Contextual error categorization
4. **State Management**: Combine publishers for reactive updates
5. **Thread Safety**: MainActor and DispatchQueue.main
6. **Retry Logic**: Smart retry based on error type
7. **UI Integration**: Clean SwiftUI integration
8. **Preview Support**: Easy testing in Xcode previews

All code follows Swift 6+ best practices, uses modern concurrency correctly, and maintains clean separation of concerns.

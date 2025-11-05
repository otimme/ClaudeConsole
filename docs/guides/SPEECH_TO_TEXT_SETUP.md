# Speech-to-Text Setup Guide

## Overview

ClaudeConsole now includes push-to-talk speech-to-text functionality using WhisperKit, allowing you to dictate text into the terminal by holding a keyboard key.

## Setup Instructions

### 1. Add WhisperKit Package Dependency

1. Open `ClaudeConsole.xcodeproj` in Xcode
2. Go to **File > Add Package Dependencies**
3. Enter the repository URL: `https://github.com/argmaxinc/whisperkit`
4. Click **Add Package**
5. Select your target (ClaudeConsole) and click **Add Package**

### 2. Add Files to Xcode Target

Make sure these new files are included in your Xcode project target:
- `KeyboardMonitor.swift`
- `AudioRecorder.swift`
- `SpeechRecognitionManager.swift`
- `SpeechToTextController.swift`

To add them:
1. In Xcode, right-click on the ClaudeConsole folder in the Project Navigator
2. Select "Add Files to ClaudeConsole..."
3. Select all the new Swift files
4. Ensure "Copy items if needed" is checked
5. Make sure the ClaudeConsole target is selected
6. Click "Add"

### 3. Update Info.plist for Microphone Permission

Add microphone usage description:
1. Open `ClaudeConsole/Info.plist` (or create it if it doesn't exist)
2. Add the following key:
   - **Key**: `NSMicrophoneUsageDescription`
   - **Type**: String
   - **Value**: "ClaudeConsole needs microphone access for speech-to-text input"

Alternatively, add this to your Info.plist file:
```xml
<key>NSMicrophoneUsageDescription</key>
<string>ClaudeConsole needs microphone access for speech-to-text input</string>
```

### 4. Update Minimum macOS Version

WhisperKit requires macOS 14.0+. Update your project settings:
1. Select the project in Xcode
2. Select the ClaudeConsole target
3. Go to "General" tab
4. Set "Minimum Deployments" to macOS 14.0

## Usage

### Default Key Binding

**Right Command Key** - Hold to record, release to transcribe and insert text

### How to Use

1. Launch ClaudeConsole
2. Wait for "WhisperKit initialized successfully" in console (first run downloads model ~150MB)
3. Navigate to your project and start Claude Code CLI
4. **Hold Right Command key** and speak
5. **Release the key** when done speaking
6. Text will automatically be transcribed and inserted into the terminal

### Visual Feedback

- **Red dot + "Recording..."** - Microphone is active
- **Spinner + "Transcribing..."** - Audio is being processed

### Testing Programming Terminology

Try these phrases to test accuracy:
- "async await function"
- "use state hook"
- "kubectl get pods"
- "docker compose up"
- "git commit dash m"
- "npm install react router dom"
- "const my variable equals"
- "import from react native"

## Changing the Push-to-Talk Key

To use a different key, modify `SpeechToTextController.swift`:

```swift
// In your ContentView or wherever you initialize SpeechToTextController
speechToText.setPushToTalkKey(49)  // Space bar
```

### Common Key Codes:
- Space: 49
- Right Command: 54 (default)
- Right Option: 61
- F13: 105
- F14: 107
- F15: 113

## Troubleshooting

### Model Download Issues
On first run, WhisperKit downloads the model (~150MB). If this fails:
- Check internet connection
- Check available disk space
- Try manually downloading from HuggingFace: `argmaxinc/whisperkit-coreml`

### Microphone Permission Denied
1. Go to **System Settings > Privacy & Security > Microphone**
2. Enable ClaudeConsole

### Poor Transcription Accuracy
1. Speak clearly and at moderate pace
2. Ensure good microphone quality
3. Minimize background noise
4. Consider upgrading to larger model (in `SpeechRecognitionManager.swift`):
   ```swift
   whisperKit = try await WhisperKit(model: "small")  // or "medium"
   ```

### High CPU/Memory Usage
- Default "base" model is optimized for speed
- For lower resource usage, try "tiny" model
- For better accuracy at cost of performance, try "small" or "medium"

## Model Options

| Model | Size | Speed | Accuracy | Best For |
|-------|------|-------|----------|----------|
| tiny | ~75MB | Fastest | Good | Quick commands |
| base | ~150MB | Fast | Very Good | Default (balanced) |
| small | ~500MB | Moderate | Excellent | Technical terms |
| medium | ~1.5GB | Slow | Superior | Maximum accuracy |

To change model, edit `SpeechRecognitionManager.swift` line 23:
```swift
whisperKit = try await WhisperKit(model: "small")
```

## Architecture

The speech-to-text system consists of four components:

1. **KeyboardMonitor** - Monitors Right Command key press/release
2. **AudioRecorder** - Records microphone audio in Whisper-compatible format (16kHz WAV)
3. **SpeechRecognitionManager** - Wraps WhisperKit for transcription
4. **SpeechToTextController** - Orchestrates the flow: key press → record → transcribe → insert

All processing happens **locally on your Mac** - no data is sent to the cloud.

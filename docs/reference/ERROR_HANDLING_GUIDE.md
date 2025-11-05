# Speech-to-Text Error Handling - Implementation Guide

## Overview

This document describes the comprehensive error handling UI added to the ClaudeConsole speech-to-text feature. All critical failures now display user-friendly error messages with options to retry or dismiss.

## Implementation Summary

### Files Modified

1. **SpeechToTextError.swift** (NEW)
   - Defines all error types for the speech-to-text pipeline
   - Implements the `ErrorBanner` UI component
   - Provides user-friendly error messages and icons

2. **SpeechRecognitionManager.swift**
   - Added `@Published var currentError: SpeechToTextError?`
   - Enhanced error handling in `initializeWhisper()`
   - Enhanced error handling in `transcribe(audioURL:)`
   - Added `retryInitialization()` method
   - Added `clearError()` method

3. **AudioRecorder.swift**
   - Added `@Published var currentError: SpeechToTextError?`
   - Enhanced error handling in `startRecording()`
   - Enhanced error handling in `audioRecorderEncodeErrorDidOccur()`
   - Added `clearError()` method

4. **SpeechToTextController.swift**
   - Added `@Published var currentError: SpeechToTextError?`
   - Added error observers for both `speechRecognition` and `audioRecorder`
   - Added `clearError()` method
   - Added `retryAfterError()` method for intelligent retry logic

5. **ContentView.swift**
   - Integrated `ErrorBanner` component at the top of terminal area
   - Connected error dismissal and retry actions
   - Maintained existing UI style consistency

## Error Scenarios Handled

### 1. Model Download Failed
**When**: WhisperKit model download fails
**Error Type**: `.modelDownloadFailed(reason: String)`
**User Message**: "Failed to download the Whisper speech recognition model. [reason]"
**Icon**: ⬇️ (arrow.down.circle.fill) - Red
**Can Retry**: Yes
**Retry Action**: Re-attempts model download

**Common Reasons**:
- Network connection lost
- Insufficient disk space (~500MB required)

### 2. Model Initialization Failed
**When**: Model download completes but initialization fails
**Error Type**: `.modelInitializationFailed`
**User Message**: "The speech recognition model couldn't be initialized. This might be due to insufficient disk space or a corrupted download."
**Icon**: ⬇️ (arrow.down.circle.fill) - Red
**Can Retry**: No
**Action**: User must resolve underlying issue and restart app

### 3. Audio Recording Failed
**When**: Audio recording cannot start or fails during recording
**Error Type**: `.audioRecordingFailed(reason: String)`
**User Message**: "Audio recording couldn't start. [reason]"
**Icon**: 🎤 (mic.slash.fill) - Red
**Can Retry**: Yes
**Retry Action**: User can try recording again

**Common Reasons**:
- Temporary file creation failed
- Encoding errors during recording
- Audio subsystem errors

### 4. Transcription Failed
**When**: Transcription process encounters an error
**Error Type**: `.transcriptionFailed(reason: String)`
**User Message**: "The audio couldn't be transcribed. [reason]"
**Icon**: 📝 (text.badge.xmark) - Red
**Can Retry**: Yes
**Retry Action**: User can try recording again

**Common Reasons**:
- Audio format not supported
- Corrupted audio file
- WhisperKit processing errors

### 5. Empty Audio File
**When**: Recorded audio file is empty or produces no transcription
**Error Type**: `.emptyAudioFile`
**User Message**: "The recorded audio file was empty. Try speaking closer to your microphone or checking your input volume."
**Icon**: 🎤 (mic.slash.fill) - Orange
**Can Retry**: Yes
**Retry Action**: User can try recording again

### 6. Microphone Permission Denied
**When**: User has not granted microphone permission
**Error Type**: `.microphonePermissionDenied`
**User Message**: "ClaudeConsole needs microphone access to use speech-to-text. Please enable it in System Settings."
**Icon**: 🔒 (lock.fill) - Yellow
**Can Retry**: No
**Action**: "Open Settings" button to launch System Settings

## UI Design

### ErrorBanner Component

The error banner appears at the **top of the terminal area** with a slide-down animation:

**Visual Style**:
- Semi-transparent black background (0.9 opacity)
- Colored border matching error severity (red/orange/yellow)
- Rounded corners (12pt radius)
- Drop shadow for elevation
- Left-aligned icon with color coding
- Error title (bold, 13pt)
- Error message (regular, 11pt)
- Action buttons (right-aligned)

**Animations**:
- Slide down from top with spring animation (0.4s)
- Fade out when dismissed (0.2s)

**Actions**:
- **Retry Button**: Appears for retryable errors, triggers `retryAfterError()`
- **Open Settings Button**: Appears for permission errors
- **Dismiss Button (X)**: Always available, triggers `clearError()`

### Integration Points

The error banner integrates seamlessly with existing indicators:
- **Model Download Indicator**: Center overlay (not affected)
- **Model Warmup Indicator**: Center overlay (not affected)
- **Speech Status Indicator**: Bottom-right corner (not affected)
- **Error Banner**: Top of terminal area (new)

## Architecture

### Error Flow

```
Error Occurs
    ↓
SpeechRecognitionManager.currentError or AudioRecorder.currentError set
    ↓
SpeechToTextController observes error via Combine
    ↓
SpeechToTextController.currentError updated
    ↓
ContentView displays ErrorBanner
    ↓
User interacts: Dismiss or Retry
    ↓
SpeechToTextController.clearError() or retryAfterError()
```

### State Management

All error state is managed via `@Published` properties and Combine publishers:
- Ensures UI updates on main thread
- Maintains single source of truth
- Enables reactive error propagation

### Retry Logic

The `retryAfterError()` method intelligently handles retries:
- **Model errors**: Re-calls `retryInitialization()` to download/init again
- **Audio/Transcription errors**: Clears error (user tries recording again)
- **Permission errors**: No retry (user must grant permission)

## Testing Guide

### Prerequisites

1. Build and run the app in Xcode
2. Grant microphone permission when prompted (for most tests)

### Test 1: Model Download Failure

**Scenario**: Simulate network failure during model download

**Steps**:
1. Delete WhisperKit model cache:
   ```bash
   rm -rf ~/Library/Caches/argmaxinc.WhisperKit
   ```
2. Disconnect from the internet
3. Launch ClaudeConsole
4. Wait for download to start and fail

**Expected Result**:
- Error banner appears at top of terminal
- Title: "Model Download Failed"
- Message: "Failed to download the Whisper speech recognition model. Check your internet connection and try again."
- Red download icon
- "Retry" button present
- "Dismiss" (X) button present

**Verify**:
- [ ] Error banner displays
- [ ] Error message is clear and helpful
- [ ] Retry button triggers new download attempt
- [ ] Dismiss button clears error

### Test 2: Empty Audio Recording

**Scenario**: Record without speaking

**Steps**:
1. Ensure app is fully initialized (model downloaded)
2. Press and hold the push-to-talk key (default: Caps Lock)
3. Don't speak into microphone
4. Release the key immediately (very short recording)
5. Wait for transcription to complete

**Expected Result**:
- Error banner appears at top of terminal
- Title: "No Audio Detected"
- Message: "The recorded audio file was empty. Try speaking closer to your microphone or checking your input volume."
- Orange microphone icon
- "Retry" button present (clears error for new recording)

**Verify**:
- [ ] Error banner displays
- [ ] Error is categorized as warning (orange, not red)
- [ ] Message provides helpful guidance
- [ ] Can record again after dismissing

### Test 3: Microphone Permission Denied

**Scenario**: Deny microphone permission

**Steps**:
1. Revoke microphone permission:
   - System Settings > Privacy & Security > Microphone
   - Uncheck ClaudeConsole
2. Relaunch ClaudeConsole
3. Try to use speech-to-text (press push-to-talk key)

**Expected Result**:
- Error banner appears at top of terminal
- Title: "Microphone Permission Required"
- Message: "ClaudeConsole needs microphone access to use speech-to-text. Please enable it in System Settings."
- Yellow lock icon
- "Open Settings" button present
- "Dismiss" button present
- NO "Retry" button (permission must be granted first)

**Verify**:
- [ ] Error banner displays
- [ ] "Open Settings" button launches System Settings
- [ ] System Settings opens to correct pane (Privacy & Security > Microphone)
- [ ] After granting permission, recording works

### Test 4: Transcription Failure (Simulated)

**Scenario**: Corrupt the audio file format

**Steps**:
This is difficult to trigger naturally. To test the UI:

1. Temporarily modify `SpeechRecognitionManager.swift` line ~137:
   ```swift
   // Add before transcribe call:
   await MainActor.run {
       self.currentError = .transcriptionFailed(reason: "Audio format not supported.")
       self.isTranscribing = false
   }
   return nil
   ```
2. Run app and try recording
3. Revert changes

**Expected Result**:
- Error banner appears at top of terminal
- Title: "Transcription Failed"
- Message: "The audio couldn't be transcribed. Audio format not supported."
- Red text icon
- "Retry" button present

**Verify**:
- [ ] Error banner displays
- [ ] Error message shows specific reason
- [ ] Retry clears error for new attempt

### Test 5: Audio Recording Failure

**Scenario**: Trigger recording initialization failure

**Steps**:
This is difficult to trigger naturally. To test the UI:

1. Temporarily modify `AudioRecorder.swift` line ~99:
   ```swift
   // Replace success check with:
   let success = false // Force failure
   ```
2. Run app and try recording
3. Revert changes

**Expected Result**:
- Error banner appears at top of terminal
- Title: "Microphone Permission Required" (since forced failure triggers permission path)
- Appropriate icon and message

**Verify**:
- [ ] Error banner displays
- [ ] UI handles recording failures gracefully

### Test 6: Multiple Rapid Errors

**Scenario**: Ensure only one error displays at a time

**Steps**:
1. Trigger an error (e.g., deny microphone permission)
2. While error banner is visible, trigger another action that might error
3. Observe error banner behavior

**Expected Result**:
- Only the most recent error displays
- Previous error is replaced
- No error banner stacking

**Verify**:
- [ ] Single error banner at a time
- [ ] Latest error takes precedence

### Test 7: Error During Model Download Progress

**Scenario**: Error appears while download indicator is showing

**Steps**:
1. Delete model cache
2. Launch app (download starts)
3. While "Downloading Whisper Model..." shows, disconnect internet
4. Wait for download to fail

**Expected Result**:
- Download indicator disappears
- Error banner appears at top
- Both indicators don't overlap (download is centered, error is top)

**Verify**:
- [ ] Visual separation between indicators
- [ ] Error banner clearly visible
- [ ] No UI overlap issues

### Test 8: Dismiss and Retry Flow

**Scenario**: Verify error clearing and retry logic

**Steps**:
1. Trigger any retryable error (e.g., model download failure)
2. Click "Dismiss" (X) button
3. Trigger same error again
4. Click "Retry" button

**Expected Result**:
- Dismiss: Error banner fades out, error state cleared
- Retry: Error banner fades out, retry action executes, new download/attempt starts

**Verify**:
- [ ] Dismiss clears error completely
- [ ] Retry triggers appropriate action
- [ ] Animations are smooth
- [ ] State management is correct

### Test 9: Error Banner Animations

**Scenario**: Verify smooth animations

**Steps**:
1. Trigger any error
2. Observe slide-down animation
3. Click dismiss
4. Observe fade-out animation

**Expected Result**:
- Slide down: Spring animation (0.4s), smooth entry from top
- Fade out: Ease-out animation (0.2s), smooth exit

**Verify**:
- [ ] Entry animation feels responsive
- [ ] Exit animation is quick but not jarring
- [ ] No visual glitches

### Test 10: Long Error Messages

**Scenario**: Ensure UI handles long error descriptions

**Steps**:
1. Temporarily modify error message to be very long (e.g., add Lorem Ipsum)
2. Trigger error
3. Verify banner layout

**Expected Result**:
- Error message wraps to multiple lines
- Banner expands vertically as needed
- All content remains readable
- Action buttons stay right-aligned

**Verify**:
- [ ] Text wraps correctly
- [ ] No text truncation
- [ ] Banner maintains visual hierarchy
- [ ] Buttons don't overlap text

## Visual Examples

### Error Banner Appearance

```
╔══════════════════════════════════════════════════════════════════════╗
║  [!]  Model Download Failed                    [Retry] [X]          ║
║       Failed to download the Whisper speech recognition model.       ║
║       Check your internet connection and try again.                  ║
╚══════════════════════════════════════════════════════════════════════╝
```

### UI Layout

```
┌─────────────────────────────────────────────────────────────┐
│                      Usage Stats View                       │
├─────────────────────────────────────────────────────────────┤
│ ┌─────────────────────────────────────────────────────────┐ │
│ │  [ERROR BANNER - appears here at top]                   │ │
│ │                                                          │ │
│ │                Terminal View                             │ │
│ │                                                          │ │
│ │  [MODEL DOWNLOAD INDICATOR - center if downloading]     │ │
│ │                                                          │ │
│ │                                           [STATUS]  →    │ │ ← Bottom-right corner
│ └─────────────────────────────────────────────────────────┘ │
├─────────────────────────────────────────────────────────────┤
│                   Context Stats View                        │
└─────────────────────────────────────────────────────────────┘
```

## Code Examples

### Triggering an Error

```swift
// In SpeechRecognitionManager
await MainActor.run {
    self.currentError = .transcriptionFailed(reason: "Audio format not supported.")
}
```

### Observing Errors

```swift
// In SpeechToTextController
speechRecognition.$currentError
    .receive(on: DispatchQueue.main)
    .sink { [weak self] error in
        if let error = error {
            self?.currentError = error
        }
    }
    .store(in: &cancellables)
```

### Displaying Error Banner

```swift
// In ContentView
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
}
```

## Best Practices

### For Developers

1. **Always set error context**: Include helpful reasons in error messages
2. **Clear errors when appropriate**: Call `clearError()` when starting new operations
3. **Test error paths**: Don't just test happy paths
4. **Use semantic error types**: Choose the most specific error type
5. **Maintain consistency**: Follow existing error message patterns

### For Users

1. **Read error messages**: They provide specific guidance
2. **Use retry when available**: Most errors are transient
3. **Check System Settings**: Permission errors require manual intervention
4. **Verify microphone input**: Empty audio often indicates hardware issues

## Future Enhancements

### Potential Improvements

1. **Error logging**: Store errors for debugging
2. **Analytics**: Track error frequency to identify issues
3. **Help links**: Add "Learn More" buttons with documentation links
4. **Error history**: Show recent errors in a list
5. **Auto-retry**: Automatically retry certain errors after delay
6. **Contextual help**: Different messages based on app state

### Known Limitations

1. **Network detection**: Cannot always distinguish network vs. other download errors
2. **Disk space**: No proactive disk space check before download
3. **Audio quality**: Cannot detect poor audio quality before transcription
4. **Error recovery**: Some errors require app restart

## Maintenance

### Adding New Error Types

1. Add case to `SpeechToTextError` enum
2. Implement `title`, `message`, `canRetry`, `iconName`, `iconColor`
3. Add to appropriate manager (`SpeechRecognitionManager` or `AudioRecorder`)
4. Update `retryAfterError()` if retry logic needed
5. Add preview and test case

### Modifying Error Messages

1. Update message text in `SpeechToTextError` enum
2. Keep messages user-friendly (no technical jargon)
3. Provide actionable guidance
4. Test message display in UI

## Summary

The error handling implementation provides:

✅ **User-friendly errors**: Clear, actionable messages
✅ **Comprehensive coverage**: All critical failure points handled
✅ **Retry capability**: Users can recover from transient errors
✅ **Consistent UI**: Matches existing indicator design
✅ **Non-intrusive**: Subtle banner at top, easily dismissed
✅ **Animated feedback**: Smooth animations for better UX
✅ **Intelligent retry**: Context-aware retry logic
✅ **Accessibility**: Clear visual hierarchy and readable text

Users will no longer experience silent failures. Every error is surfaced with helpful information and options to resolve the issue.

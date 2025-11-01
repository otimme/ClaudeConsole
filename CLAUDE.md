# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ClaudeConsole is a macOS application that wraps the Claude Code CLI with real-time usage and context statistics monitoring. It provides an integrated terminal experience with visual feedback on token usage and context limits.

## Build & Run

```bash
# Open project in Xcode
open ClaudeConsole.xcodeproj

# Build and run from Xcode: ⌘R
```

**Requirements:**
- macOS 13.0+
- Xcode 15.0+
- Claude Code CLI installed (`npm install -g @anthropics/claude-code`)

## Architecture

### Core Components

**ContentView**: Main container organizing three sections vertically:
- Top: `RealUsageStatsView` (usage limits)
- Middle: `TerminalView` (SwiftTerm-based terminal)
- Bottom: `ContextStatsView` (context token breakdown)

**TerminalView**: Custom SwiftTerm implementation with output monitoring
- Extends `LocalProcessTerminalView` as `MonitoredLocalProcessTerminalView`
- Monitors terminal output to detect when `claude` command is executed
- Posts `claudeCodeStarted` notification when Claude session begins
- Posts `terminalOutput` notifications for context parsing

**UsageMonitor**: Background PTY session for automated usage polling
- Spawns hidden Claude Code session via `posix_spawn`
- Sends `/usage` command every 60 seconds (with retry logic)
- Parses daily/weekly usage percentages from CLI output
- Uses regex to strip ANSI codes before parsing

**ContextMonitor**: On-demand context statistics
- Sends `/context` command to visible terminal when user clicks refresh
- Listens to `terminalOutput` notifications to capture response
- Waits 1 second after last output before parsing
- Extracts token breakdown by category (system, messages, agents, etc.)

### Communication Pattern

Components communicate via `NotificationCenter`:
- `.claudeCodeStarted`: Posted when `claude` command is detected
- `.terminalOutput`: Posted for each terminal output chunk
- `.terminalControllerAvailable`: Posted when terminal is ready

### PTY Implementation Details

**UsageMonitor** creates a background pseudo-terminal:
1. Finds `claude` executable via `which` command or fallback paths
2. Creates PTY pair using `openpty()`
3. Spawns `node` process running the Claude CLI script
4. Maintains non-blocking read on master FD
5. Sends Escape + `/usage ` + Enter sequence periodically
6. Includes retry logic (3 attempts) to handle CLI startup delays

### Parsing Logic

Both monitors strip ANSI escape sequences using regex: `\u{001B}\[[0-9;]*[a-zA-Z]`

**UsageMonitor** expects format:
```
Current session
  ██▌                                                5% used
Current week (all models)
  █████████▌                                         19% used
Current week (Opus)
  ██                                                 4% used
```

**ContextMonitor** expects format:
```
69k/200k tokens (34%)
System prompt: 12.3k tokens
System tools: 45.6k tokens
Messages: 10.2k tokens
Free space: 131k
```

## Speech-to-Text Feature

**Push-to-Talk with WhisperKit**: Hold Right Command key to record speech, release to transcribe and insert into terminal.

**Components:**
- `KeyboardMonitor`: Monitors keyboard events for push-to-talk key (Right Command)
- `AudioRecorder`: Captures microphone audio in 16kHz WAV format (Whisper-compatible)
- `SpeechRecognitionManager`: Wraps WhisperKit for local, on-device transcription
- `SpeechToTextController`: Coordinates keyboard → recording → transcription → terminal insertion

**Flow:**
1. User holds Right Command key → `KeyboardMonitor` detects press
2. `AudioRecorder` starts recording microphone audio
3. User releases key → recording stops
4. `SpeechRecognitionManager` transcribes audio using WhisperKit (local processing)
5. Transcribed text is sent to terminal via `terminalController.send()`

**Model:** Uses WhisperKit "base" model by default (~150MB, downloaded on first run). Excellent accuracy with programming terminology (async/await, React hooks, kubectl commands, etc.).

**Visual Feedback:** Red dot overlay shows "Recording...", spinner shows "Transcribing..."

See `SPEECH_TO_TEXT_SETUP.md` for detailed setup instructions.

## Key Implementation Notes

- `UsageMonitor` runs on background queue to avoid UI thread blocking during initialization
- Terminal starts with `/bin/zsh -l` (login shell) to load full environment
- Claude executable discovery tries `which` first, then fallback to common nvm paths
- PATH environment is captured from login shell for spawned processes
- Output buffers limited to prevent memory growth (5000 chars for usage, managed by timer for context)
- Visual terminal and background session are completely separate processes
- WhisperKit initializes asynchronously on app launch, ~5-10 seconds for first-time model download

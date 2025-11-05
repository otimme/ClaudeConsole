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

## PS4 Controller Support

**DualShock 4 Integration**: Full PlayStation 4 controller support with customizable button-to-key mappings and visual feedback.

**Components:**
- `PS4ControllerMonitor`: Monitors controller connection and input using GameController framework
- `PS4ButtonMapping`: Persistent storage for button-to-key/key-combination mappings
- `PS4ControllerController`: Orchestrates controller input and terminal integration
- `PS4ControllerView`: Visual representation of controller with real-time button state
- `PS4ControllerStatusBar`: Top status bar showing all button mappings at a glance
- `PS4ConfigurationView`: Settings panel for customizing button mappings

**Features:**
- **Complete Button Support**: All DualShock 4 buttons including face buttons (✕○□△), shoulders (L1/R1/L2/R2), D-pad, analog sticks (L3/R3), and center buttons (Options/Share/Touchpad)
- **Visual Feedback**: Buttons light up with colored indicators when pressed, both in the controller panel and status bar
- **Customizable Mappings**: Each button can be mapped to any key or key combination with modifiers (⌃⌥⇧⌘)
- **Preset Configurations**: Built-in presets for Vim mode, Navigation mode, Terminal mode, or Custom
- **Status Bar**: Two display modes - Full (shows all buttons) or Compact (shows only pressed buttons)
- **Battery Monitoring**: Real-time battery level display with charging indicator
- **Connection Notifications**: System notifications on controller connect/disconnect

**Flow:**
1. Controller connects via Bluetooth or USB → `PS4ControllerMonitor` detects via GameController framework
2. User presses button → Monitor captures input and looks up mapping in `PS4ButtonMapping`
3. Mapped KeyCommand is converted to terminal data and sent via `terminalController.send()`
4. Visual feedback shown in both status bar and optional controller panel

**Implementation Details:**
- Uses Apple's GameController framework for native controller support
- Mappings stored in UserDefaults with Codable models
- Deferred initialization to prevent crashes: `DispatchQueue.main.async { self?.setupControllerCallbacks() }`
- Safe battery access with weak self capture to avoid crashes during connection
- OptionSet for modifier keys using `.contains()` method for proper bit checking
- Explicit `SwiftUI.Color` to avoid conflicts with SwiftTerm's Color type

**Default Mappings:**
- Cross (✕) → Enter, Circle (○) → Escape, Square (□) → Space, Triangle (△) → Tab
- D-Pad → Arrow keys, L1/R1 → Page Up/Down, L2/R2 → Home/End
- Options → Ctrl+C, Share → Ctrl+Z, L3/R3 → Ctrl+A/E

See `PS4_CONTROLLER_GUIDE.md` for detailed setup and usage instructions.

## Radial Menu System

**Context-Aware Command Menus**: L1/R1 shoulder buttons trigger radial menus with 8-directional selection using the right analog stick.

**Components:**
- `RadialMenuController`: Orchestrates menu display, segment selection, and action execution
- `RadialMenuModels`: Data models for menus, profiles, and segments (Codable for persistence)
- `RadialMenuProfileManager`: Manages profiles with UserDefaults persistence and import/export
- `RadialMenuProfileSelector`: Compact widget in PS4 panel showing active profile
- `RadialMenuConfigurationView`: Full-featured modal editor for profiles and segments
- `RadialMenuView`: SwiftUI overlay displaying the radial menu with visual feedback

**Features:**
- **8-Direction Selection**: N, NE, E, SE, S, SW, W, NW segments
- **Profile System**: 6 default profiles (Default, Docker, NPM, Navigation, Claude, Dev Tools)
- **Profile Management**: Create, duplicate, delete, reset to defaults
- **Import/Export**: Share profiles via JSON files
- **4 Action Types**: Key commands, text macros, app commands, shell commands
- **L1 & R1 Menus**: Separate menu configurations for each shoulder button
- **Visual Preview**: Interactive segment preview in configuration UI
- **Persistent Storage**: All profiles saved to UserDefaults automatically

**Flow:**
1. User holds L1 or R1 → `RadialMenuController` shows menu overlay after 300ms
2. User moves right analog stick → Selects direction (N/NE/E/SE/S/SW/W/NW)
3. Selected segment highlights with visual feedback
4. User releases L1/R1 → Executes configured action for that segment
5. Menu fades out

**Configuration UI:**
- **Split View Layout**: Segment list (left) + editor (right)
- **Visual Radial Preview**: Interactive 8-segment pie chart
- **Action Editor**: Configure key commands, text macros, app commands, or shell commands
- **Profile Selector**: Quick dropdown to switch between profiles
- **Import/Export**: Native file pickers for JSON backup/restore

**Default Profiles:**
- **Default**: Quick Actions (L1: copy/paste/clear) + Git Commands (R1: status/push/pull)
- **Docker**: Quick Actions (L1) + Docker commands (R1: ps/logs/restart)
- **NPM**: Quick Actions (L1) + NPM commands (R1: install/build/test)
- **Navigation**: Quick Actions (L1) + Terminal navigation (R1: cd shortcuts)
- **Claude**: Claude commands (L1: /usage/context) + Git (R1)
- **Dev Tools**: Development tools (L1: linters/formatters) + Git (R1)

**Implementation Details:**
- Uses Apple's GameController framework for analog stick input
- 50ms debounce on segment selection to prevent flickering
- Segments rotated -90° to align North with screen top
- Notification-based action execution integrates with existing button system
- Profile data stored as JSON in UserDefaults (`radialMenuProfiles` key)
- Custom `RadialSegmentShape` using SwiftUI Shape protocol for pie slices
- Key capture prevents Tab/Enter/Escape from affecting UI navigation

**Action Types:**
1. **Key Command**: Keyboard shortcuts with modifiers (⌘⌃⌥⇧)
2. **Text Macro**: Type text into terminal (with optional auto-enter)
3. **App Command**: Built-in app functions (/usage, /context, speech-to-text, etc.)
4. **Shell Command**: Execute arbitrary shell commands (⚠️ with full permissions)

See `RADIAL_MENU_IMPLEMENTATION_PLAN.md` for detailed implementation guide and `PHASE_2_TESTING_CHECKLIST.md` for comprehensive testing instructions.

## Key Implementation Notes

- `UsageMonitor` runs on background queue to avoid UI thread blocking during initialization
- Terminal starts with `/bin/zsh -l` (login shell) to load full environment
- Claude executable discovery tries `which` first, then fallback to common nvm paths
- PATH environment is captured from login shell for spawned processes
- Output buffers limited to prevent memory growth (5000 chars for usage, managed by timer for context)
- Visual terminal and background session are completely separate processes
- WhisperKit initializes asynchronously on app launch, ~5-10 seconds for first-time model download

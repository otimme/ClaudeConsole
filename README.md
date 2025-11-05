# ClaudeConsole

A macOS app that wraps the Claude Code CLI with real-time usage and context statistics, featuring PS4 controller integration with game-style radial menus.

![ClaudeConsole](screenshot.png)

## Features

### 🎮 PS4 Controller Integration
- **Full DualShock 4 Support**: Control your terminal with PlayStation 4 controller
- **Radial Menu System**: Game-style weapon wheel interface for quick command access
  - **L1 Menu**: 8 customizable actions triggered by holding L1
  - **R1 Menu**: 8 additional actions triggered by holding R1
  - Analog stick navigation with visual feedback
  - Hold-to-preview tooltips with color-coded action types
- **Customizable Button Mappings**: Map any button to:
  - Key commands with modifiers (⌃⌥⇧⌘)
  - Text macros with auto-enter
  - Application commands (speech-to-text, UI toggles)
  - Shell commands
- **Profile System**: 6 built-in profiles ready to use
  - Default, Docker, NPM, Navigation, Claude, Dev Tools
  - Create, edit, duplicate, and share custom profiles
  - Import/export profiles as JSON
- **Visual Feedback**: Real-time button press indicators and battery monitoring
- **Status Bar**: Shows current button mappings (full or compact mode)

### 🎤 Push-to-Talk Speech-to-Text
- Hold Right Command key to dictate text into the terminal
- State-of-the-art WhisperKit (OpenAI Whisper) for accurate transcription
- Excellent recognition of programming terminology (async/await, React hooks, kubectl, etc.)
- Completely free and runs locally on your Mac (no cloud API costs)
- Visual feedback for recording and transcription status

### 📊 Real-Time Monitoring
- **Usage Statistics**: Real-time monitoring of daily and weekly token limits
  - Current session usage
  - Weekly usage (all models)
  - Weekly Opus usage
  - Auto-updates every minute
- **Context Statistics**: Manual refresh to view current session context
  - Total tokens used
  - System prompt and tools breakdown
  - Custom agents usage
  - Messages and buffer statistics
  - Free space remaining

### 💻 Integrated Terminal
- Full-featured terminal running Claude Code CLI with SwiftTerm
- Seamless integration with controller and keyboard input
- Full shell environment with login shell support

## Requirements

- macOS 13.0+ (macOS 14.0+ required for speech-to-text)
- Xcode 15.0+
- Claude Code CLI installed (`npm install -g @anthropics/claude-code`)
- **Optional**: PS4 DualShock 4 controller (Bluetooth or USB)
- **Optional**: Microphone access (for speech-to-text feature)

## Installation

1. Clone this repository:
   ```bash
   git clone https://github.com/yourusername/ClaudeConsole.git
   cd ClaudeConsole
   ```

2. Open `ClaudeConsole.xcodeproj` in Xcode

3. Build and run (⌘R)

## Usage

### Getting Started

1. Launch ClaudeConsole
2. The terminal starts with your default shell (zsh)
3. Navigate to your project directory
4. Type `claude` to start a Claude Code session
5. Usage stats automatically update every minute
6. Click the refresh button (↻) next to "Context Usage" to update context stats

### PS4 Controller

**Quick Start:**
1. Connect your PS4 controller via Bluetooth or USB
2. The controller status appears in the top-right corner
3. **Hold L1 or R1** to open the radial menu
4. **Push right analog stick** in any direction to select an action
5. **Release L1/R1** to execute the selected action

**Configuration:**
1. Click "Configure Radial Menu" in the PS4 controller panel
2. Select a profile or create your own
3. Click any segment to edit its action
4. Choose from 4 action types:
   - **Key Press**: Send keyboard shortcuts
   - **Text Macro**: Insert text strings
   - **App Command**: Trigger app features
   - **Shell Command**: Execute shell commands
5. Import/export profiles to share with others

**Profiles Included:**
- **Default**: Common terminal shortcuts (Ctrl+C, Ctrl+Z, arrows, etc.)
- **Docker**: Docker commands (ps, logs, build, compose, etc.)
- **NPM**: Node.js package management (install, run, test, build)
- **Navigation**: Directory navigation (ls, cd, pwd, find)
- **Claude**: Claude CLI shortcuts (usage, context, help)
- **Dev Tools**: Development tools (git status, build, test)

See [PS4_CONTROLLER_GUIDE.md](PS4_CONTROLLER_GUIDE.md) for detailed instructions.

### Speech-to-Text

**Push-to-Talk**: Hold Right Command key, speak, then release to transcribe text into terminal

See [SPEECH_TO_TEXT_SETUP.md](SPEECH_TO_TEXT_SETUP.md) for detailed setup instructions including:
- Adding WhisperKit dependency
- Configuring microphone permissions
- Changing the push-to-talk key
- Troubleshooting and model options

## How It Works

### PS4 Controller System
- **GameController Framework**: Native macOS support for DualShock 4
- **Radial Menu Controller**: Manages L1/R1 trigger detection and menu state
- **Profile Manager**: Handles profile storage with UserDefaults (JSON import/export)
- **Action Execution**: Converts controller input to terminal commands via SwiftTerm
- **Visual Feedback**: SwiftUI overlays with smooth animations and real-time highlighting

### Usage Statistics
- Runs a background Claude Code session
- Sends `/usage` command every 60 seconds
- Parses the response to display daily/weekly limits

### Context Statistics
- Sends `/context` command to your visible terminal when you click refresh
- Captures and parses the output
- Displays breakdown of token usage by category

## Architecture

- **SwiftUI**: Modern macOS UI with declarative layouts
- **SwiftTerm**: Terminal emulation with full ANSI support
- **GameController**: Native PS4 controller support
- **Notification-based**: Components communicate via NotificationCenter
- **PTY (pseudo-terminal)**: Background session for usage stats
- **Direct terminal control**: Context stats from visible session
- **Codable Models**: Type-safe JSON serialization for profiles and configurations

## Documentation

Comprehensive guides are available in the repository:

- **[PS4_CONTROLLER_GUIDE.md](PS4_CONTROLLER_GUIDE.md)**: Complete guide to controller features and setup
- **[RADIAL_MENU_IMPLEMENTATION_PLAN.md](RADIAL_MENU_IMPLEMENTATION_PLAN.md)**: Technical design document for radial menu system
- **[SPEECH_TO_TEXT_SETUP.md](SPEECH_TO_TEXT_SETUP.md)**: Speech-to-text feature setup and configuration
- **[CLAUDE.md](CLAUDE.md)**: Project overview and architecture for Claude Code AI assistant
- **[PHASE_2_TESTING_CHECKLIST.md](PHASE_2_TESTING_CHECKLIST.md)**: Testing guide with 200+ test cases

## License

MIT

## Author

Built with Claude Code

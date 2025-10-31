# ClaudeConsole

A macOS app that wraps the Claude Code CLI with real-time usage and context statistics.

![ClaudeConsole](screenshot.png)

## Features

- **Integrated Terminal**: Full-featured terminal running Claude Code CLI with SwiftTerm
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

## Requirements

- macOS 13.0+
- Xcode 15.0+
- Claude Code CLI installed (`npm install -g @anthropics/claude-code`)

## Installation

1. Clone this repository:
   ```bash
   git clone https://github.com/yourusername/ClaudeConsole.git
   cd ClaudeConsole
   ```

2. Open `ClaudeConsole.xcodeproj` in Xcode

3. Build and run (⌘R)

## Usage

1. Launch ClaudeConsole
2. The terminal starts with your default shell (zsh)
3. Navigate to your project directory
4. Type `claude` to start a Claude Code session
5. Usage stats automatically update every minute
6. Click the refresh button (↻) next to "Context Usage" to update context stats

## How It Works

### Usage Statistics
- Runs a background Claude Code session
- Sends `/usage` command every 60 seconds
- Parses the response to display daily/weekly limits

### Context Statistics
- Sends `/context` command to your visible terminal when you click refresh
- Captures and parses the output
- Displays breakdown of token usage by category

## Architecture

- **SwiftUI**: Modern macOS UI
- **SwiftTerm**: Terminal emulation
- **Notification-based**: Components communicate via NotificationCenter
- **PTY (pseudo-terminal)**: Background session for usage stats
- **Direct terminal control**: Context stats from visible session

## License

MIT

## Author

Built with Claude Code

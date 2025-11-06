# ClaudeConsole - Main Application Plan

**Date Created:** 2025-11-05
**Status:** Active Development
**Version:** 1.0

---

## Project Overview

ClaudeConsole is a macOS terminal application that wraps the Claude Code CLI with enhanced features including real-time usage monitoring, PS4 controller integration, speech-to-text input, and radial menu command shortcuts.

**Core Technologies:**
- SwiftUI for native macOS UI
- SwiftTerm for terminal emulation
- GameController framework for PS4 DualShock 4 support
- WhisperKit for local speech-to-text
- Notification-based component architecture

---

## Completed Features ✅

### 1. Terminal Integration
**Status:** ✅ Complete
**Description:** SwiftTerm-based terminal with Claude Code CLI monitoring

**Features:**
- Login shell (`/bin/zsh -l`) with full environment
- Output monitoring for Claude session detection
- Real-time command execution
- ANSI escape sequence support

---

### 2. Usage & Context Monitoring
**Status:** ✅ Complete
**Description:** Real-time tracking of Claude Code usage limits and context tokens

**Features:**
- Background PTY session for usage polling (60s interval)
- Daily/weekly usage percentages by model
- On-demand context statistics (`/context` command)
- Token breakdown by category (system, messages, agents)
- Visual progress bars and statistics panels

---

### 3. PS4 Controller Integration
**Status:** ✅ Complete (5 of 7 phases)
**Plan:** [PS4_CONTROLLER_ENHANCEMENT_PLAN.md](PS4_CONTROLLER_ENHANCEMENT_PLAN.md)

**Completed Features:**
- Full DualShock 4 button mapping
- Customizable key commands with modifiers
- Text macros with auto-enter support
- Application commands (speech, clipboard, terminal control)
- Shell command execution
- System commands (app switching, AppleScript, URLs)
- Visual button feedback and battery monitoring
- Configuration UI with preset profiles

**Phases Complete:**
- ✅ Phase 1: Core Data Model Extension
- ✅ Phase 2: Text Macros & Basic Actions
- ✅ Phase 3: Application Commands
- ✅ Phase 4: Enhanced Configuration UI
- ✅ Phase 7: System Integration

**Deferred Phases:**
- ⏸️ Phase 5: Button Combinations (design flaw identified)
- ⏸️ Phase 6: Context Awareness (manual switching preferred)

---

### 4. Radial Menu System
**Status:** ✅ Complete (All 4 phases)
**Plan:** [RADIAL_MENU_IMPLEMENTATION_PLAN.md](RADIAL_MENU_IMPLEMENTATION_PLAN.md)

**Features:**
- L1/R1 triggered radial menus (8 segments each)
- Right analog stick navigation with dead zones
- 8 default profiles (Default, Docker, NPM, Navigation, Claude, Dev Tools, Git Advanced, Testing)
- Profile management with import/export
- Full configuration UI
- Visual polish with spring animations and glow effects
- Hold-to-preview tooltips
- Color-coded action badges

**Phases Complete:**
- ✅ Phase 1: Core Radial Menu
- ✅ Phase 2: Configuration & Profiles
- ✅ Phase 3: Visual Polish & UX
- ✅ Phase 4: Polish & Testing

**Total Development:** ~18 hours, 11 commits, 3000+ lines of code

---

### 5. Profile Switcher
**Status:** ✅ Complete
**Description:** Touchpad-triggered radial menu for quick profile switching

**Features:**
- Touchpad button opens profile switcher
- Left analog stick selects from 8 profiles
- Visual radial menu with profile icons
- Active profile indicator (green dot)
- Instant profile switching on touchpad release

---

### 6. Speech-to-Text Integration
**Status:** ✅ Complete
**Description:** Push-to-talk speech input with local processing

**Features:**
- Right Command key for push-to-talk
- WhisperKit (OpenAI Whisper) local transcription
- Excellent programming terminology recognition
- Visual recording/transcription feedback
- No cloud costs, on-device processing

---

### 7. Drag-and-Drop File Path Insertion
**Status:** ✅ Complete
**Description:** Native macOS drag-and-drop support for file path insertion

**Features:**
- Drag files, folders, or images into terminal
- Backslash escaping for special characters (matches Terminal.app)
- Tilde (~) expansion for home directory paths
- Multiple file support (space-separated)
- Visual blue border overlay during drag-over
- Automatic focus restoration after drop
- Paths inserted at cursor position (no auto-execution)

**Implementation Details:**
- Added to `TerminalView.swift` (101 lines)
- NSView drag delegate methods (draggingEntered, performDragOperation)
- Smart path formatting with backslash escaping
- Escapes: space, special chars `( ) & ; | < > $ \` " ' * ? [ ] ! # { } \`
- Focus restoration: NSApp.activate + makeKeyAndOrderFront + makeFirstResponder

**Development Time:** ~2 hours (faster than 4-6h estimate)

---

### 8. Project Launcher with CLAUDE.md Detection
**Status:** ✅ Complete
**Description:** Startup modal for quick project selection and auto-launch

**Features:**
- Scans directories for CLAUDE.md files to detect projects
- SwiftUI modal with grouped project list
- Search/filter by name or path
- Groups by parent directory, sorts by modified date
- Git branch detection and display
- Remembers last selected project
- 5-minute cache to prevent slow scans
- Settings panel for search paths and configuration
- Auto-launches on app startup (configurable)
- Skip button to bypass launcher

**Implementation Details:**
- 5 new Swift files (701 lines total)
- ProjectModel: Data structures with Codable support
- ProjectScanner: Async directory scanning with recursion
- ProjectCache: UserDefaults-based caching with expiration
- ProjectLauncherController: State management with @Published
- ProjectLauncherView: SwiftUI with search, grouping, settings
- Integration: .sheet presentation in ContentView
- Launch sequence: cd [path] + claude command with delays

**Default Settings:**
- Search paths: ~/Documents/Projects, ~/Code, ~/Development
- Max depth: 3 levels
- Exclude patterns: node_modules, .git, venv, __pycache__, .build, Pods
- Cache expiration: 5 minutes

**Development Time:** ~4 hours (faster than 8-10h estimate!)

---

## Planned Features 🚀

*No features currently planned. Feature 1 & 2 complete ahead of schedule!*

See "Future Enhancements" sections below for potential Tier 2 and Tier 3 features.

---

## Future Enhancements (Tier 2)

### Terminal Enhancements
- Split panes (horizontal/vertical)
- Tab support for multiple terminals
- Session persistence (restore on restart)
- Custom color schemes and fonts
- Find/search in terminal output
- Copy mode with keyboard selection

### PS4 Controller Advanced Features
- Haptic feedback patterns per action type
- LED color customization
- Touchpad gesture support (swipe, tap)
- Motion controls (gyroscope, accelerometer)
- Audio jack support (route to controller)

### Radial Menu Tier 2 Features
- Sub-menus (nested radial menus)
- Recent actions quick access
- Quick flick gestures
- Custom colors per segment
- Animated icons
- Context-aware profile switching
- Command history integration
- Macro recording

### Speech-to-Text Enhancements
- Custom voice commands (e.g., "clear terminal")
- Multiple language support
- Larger model option (medium/large)
- Background noise filtering
- Custom vocabulary for project-specific terms

### Monitoring & Stats
- Historical usage graphs (daily/weekly/monthly)
- Token usage predictions
- Model performance comparison
- Session time tracking
- Command frequency analysis

---

## Future Enhancements (Tier 3)

### AI Integration
- AI command suggestions based on context
- Natural language to CLI translation
- Error explanation and fix suggestions
- Code snippet completion

### Collaboration
- Profile sharing community
- Configuration marketplace
- Cloud sync for settings and profiles
- Team profile templates

### Advanced Customization
- Theme engine with visual editor
- Plugin system for extensions
- Custom action types
- Scripting language for automation

---

## Implementation Priority

**Completed:**
1. ✅ Feature 1: Drag-and-Drop File Paths (~2 hours)
2. ✅ Feature 2: Project Launcher (~4 hours)

**Short-term (1-2 months):**
- Terminal split panes
- Tab support
- Session persistence

**Medium-term (3-6 months):**
- Radial menu sub-menus
- Advanced PS4 controller features
- Historical usage analytics

**Long-term (6+ months):**
- AI integration features
- Plugin system
- Community features

---

## Development Metrics

**Current State:**
- **Lines of Code:** ~8,800+ Swift
- **Files:** 40+ Swift files
- **Documentation:** 13 markdown files
- **Development Time:** ~56+ hours
- **Features Complete:** 8 major features ✅
- **Test Coverage:** Manual testing (200+ test cases for radial menu)

**Completed for v2.0:**
- ✅ Drag-and-drop support (Feature 1)
- ✅ Project launcher (Feature 2)

**Target for v2.0:**
- Split panes
- Tab support
- 90%+ feature completeness for core terminal experience

---

## Architecture Notes

**Component Communication:**
- NotificationCenter for loose coupling
- Combine for reactive state management
- @Published properties for UI updates
- Weak references to prevent retain cycles

**Performance Considerations:**
- Background threads for file operations
- Debouncing for high-frequency inputs (analog sticks)
- Caching for expensive operations (project scanning)
- Efficient terminal output parsing

**Code Quality:**
- SwiftLint for style consistency
- Comprehensive inline documentation
- Modular architecture for testability
- Error handling with graceful degradation

---

**Last Updated:** 2025-11-06
**Next Review:** After Feature 2 (Project Launcher) implementation

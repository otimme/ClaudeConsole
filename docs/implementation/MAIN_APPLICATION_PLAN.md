# ClaudeConsole - Main Application Plan

**Date Created:** 2025-01-05
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

## Planned Features 🚀

### Feature 1: Drag-and-Drop File Path Insertion
**Status:** 📋 Planned
**Priority:** High
**Estimated Effort:** 4-6 hours

#### Description
Add native macOS drag-and-drop support to the terminal, matching the behavior of Terminal.app. Users can drag files, folders, or images into the terminal and have their paths automatically inserted at the cursor position.

#### Requirements

**Supported Drop Types:**
- Files (any type)
- Folders/directories
- Images (PNG, JPG, etc.)
- Multiple items (space-separated paths)

**Path Handling:**
- Full absolute paths
- Automatic escaping of spaces (e.g., `/Users/name/My\ Documents/`)
- Quote wrapping for paths with special characters
- Proper handling of symbolic links

**User Experience:**
- Visual drop target indicator (highlight terminal area)
- Cursor changes to indicate drop is valid
- Path inserted at current cursor position
- No execution until user presses Enter
- Support for multiple simultaneous drops

#### Implementation Plan

**Phase 1: Basic Drop Support (2 hours)**
- Implement `NSView` drop delegate methods in SwiftTerm wrapper
- Register accepted UTI types (public.file-url, public.folder)
- Extract file paths from drag operation
- Insert path string at cursor position

**Phase 2: Path Formatting (1 hour)**
- Escape spaces and special characters
- Add quote wrapping when needed
- Handle multiple paths (space-separated)
- Test with various file types and names

**Phase 3: Visual Feedback (1 hour)**
- Add drop target highlight overlay
- Cursor feedback during drag-over
- Animation for successful drop
- Error handling for invalid drops

**Phase 4: Edge Cases (1-2 hours)**
- Handle symbolic links
- Very long paths (>1000 chars)
- Non-ASCII characters in filenames
- Permission-denied files
- Network volumes and remote paths
- Multiple drops in quick succession

#### Technical Details

**Components to Modify:**
- `TerminalView.swift` - Add drop delegate
- `MonitoredLocalProcessTerminalView` - Extend with drop handling
- New: `TerminalDropHandler.swift` - Drop logic and path formatting

**Key Methods:**
```swift
// NSView drop delegate
func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation
func draggingExited(_ sender: NSDraggingInfo?)
func performDragOperation(_ sender: NSDraggingInfo) -> Bool

// Path formatting
func formatPathForTerminal(_ url: URL) -> String
func escapeSpecialCharacters(_ path: String) -> String
```

**Testing Checklist:**
- [ ] Single file drop
- [ ] Single folder drop
- [ ] Image file drop
- [ ] Multiple files (5+ at once)
- [ ] Path with spaces
- [ ] Path with special chars (`$`, `&`, `*`, etc.)
- [ ] Symbolic link drop
- [ ] Network volume path
- [ ] Very long path (>500 chars)
- [ ] Non-ASCII filename (emoji, Chinese chars)
- [ ] Drop during command execution
- [ ] Drop with text selected in terminal

---

### Feature 2: Project Launcher with CLAUDE.md Detection
**Status:** 📋 Planned
**Priority:** High
**Estimated Effort:** 8-10 hours

#### Description
Add a startup screen that displays a list of Claude-enabled projects (identified by `CLAUDE.md` files) and automatically navigates to the selected project folder before starting the Claude CLI. This provides a quick way to resume work on any active project.

#### Requirements

**Project Detection:**
- Scan user-specified directories for `CLAUDE.md` files
- Configurable search paths (e.g., `~/Documents/Projects`, `~/Code`)
- Configurable max depth (default: 3 levels)
- Background scanning with progress indicator
- Cache results to avoid slow startup

**Project List Display:**
- Modal window on app launch (before terminal)
- Sorted by:
  1. Folder structure (group by parent directory)
  2. Modified date (most recent first)
- Show for each project:
  - Project name (folder name)
  - Full path (truncated for display)
  - Last modified date
  - Parent folder hierarchy
  - Optional: Git branch name if in repo

**Project Selection:**
- Click to select, Enter to launch
- Search/filter by project name or path
- Keyboard navigation (arrow keys, type to filter)
- "Skip" or "Browse" button to open terminal without project
- Remember last selected project (pre-select on next launch)

**Launch Behavior:**
- Navigate to selected project directory (`cd /path/to/project`)
- Execute `claude` command automatically
- Terminal immediately ready for use
- Show "Starting Claude in [project name]..." message

#### Implementation Plan

**Phase 1: Project Scanner (2-3 hours)**
- Create `ProjectScanner` class
- Scan directories for `CLAUDE.md` files
- Extract project metadata (name, path, modified date)
- Handle symlinks and permission errors
- Cache results in UserDefaults (5-minute TTL)

**Phase 2: Project Launcher UI (3-4 hours)**
- Create `ProjectLauncherView` SwiftUI modal
- Project list with sorting and grouping
- Search/filter functionality
- Keyboard navigation support
- "Skip" and "Refresh" buttons
- Settings button to configure search paths

**Phase 3: Terminal Integration (2 hours)**
- Delay terminal startup until project selected
- Pass selected project path to terminal
- Execute `cd` + `claude` commands
- Show loading state during startup
- Handle errors (project deleted, permission denied)

**Phase 4: Configuration & Settings (1-2 hours)**
- Settings panel for search paths
- Max depth configuration
- Enable/disable auto-launch
- Exclude patterns (e.g., `node_modules`, `.git`)
- Cache management (clear, refresh interval)

#### Technical Details

**New Components:**
- `ProjectScanner.swift` - File system scanning logic
- `ProjectModel.swift` - Project data structure
- `ProjectLauncherView.swift` - SwiftUI launcher modal
- `ProjectLauncherController.swift` - State management
- `ProjectCache.swift` - Result caching with expiration

**Key Classes:**

```swift
struct Project: Identifiable, Codable {
    let id: UUID
    let name: String
    let path: URL
    let claudeMdPath: URL
    let lastModified: Date
    let parentPath: String
    var gitBranch: String?
}

class ProjectScanner {
    func scanForProjects(in paths: [URL], maxDepth: Int) async -> [Project]
    func findCLAUDEmd(in directory: URL) -> URL?
    func getProjectMetadata(for path: URL) -> Project?
}

class ProjectLauncherController: ObservableObject {
    @Published var projects: [Project] = []
    @Published var isScanning: Bool = false
    @Published var searchText: String = ""

    var filteredProjects: [Project] { /* filter + sort */ }
    func selectProject(_ project: Project)
    func skipLauncher()
}
```

**Configuration Storage:**

```swift
struct ProjectLauncherSettings: Codable {
    var searchPaths: [String] = [
        "~/Documents/Projects",
        "~/Code",
        "~/Development"
    ]
    var maxDepth: Int = 3
    var enableAutoLaunch: Bool = true
    var excludePatterns: [String] = [
        "node_modules",
        ".git",
        "venv",
        "__pycache__"
    ]
    var cacheExpirationMinutes: Int = 5
}
```

**Sorting Logic:**

```swift
func sortProjects(_ projects: [Project]) -> [Project] {
    projects.sorted { p1, p2 in
        // First, group by parent directory
        if p1.parentPath != p2.parentPath {
            return p1.parentPath < p2.parentPath
        }
        // Then, sort by modified date (newest first)
        return p1.lastModified > p2.lastModified
    }
}
```

**Launch Sequence:**

```swift
func launchProject(_ project: Project) {
    // 1. Show launching message
    showMessage("Starting Claude in \(project.name)...")

    // 2. Navigate to directory
    terminalController.send("cd \"\(project.path.path)\"\n")

    // 3. Wait for prompt (100ms delay)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
        // 4. Start Claude
        terminalController.send("claude\n")
    }
}
```

**Testing Checklist:**
- [ ] Scan finds all CLAUDE.md files in search paths
- [ ] Max depth setting respected
- [ ] Sorting by folder structure works correctly
- [ ] Sorting by modified date (newest first)
- [ ] Search/filter narrows list correctly
- [ ] Keyboard navigation (up/down/enter)
- [ ] Skip button bypasses launcher
- [ ] Selected project launches Claude correctly
- [ ] Handle project folder deleted between scan and launch
- [ ] Handle permission denied on project folder
- [ ] Cache prevents slow re-scans
- [ ] Settings persist between launches
- [ ] Git branch detection works (if in repo)
- [ ] Very long project paths display correctly
- [ ] Non-ASCII project names work
- [ ] Multiple projects in same parent folder
- [ ] Exclude patterns work (ignore node_modules, etc.)
- [ ] Refresh button re-scans immediately
- [ ] Last selected project remembered

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

**Immediate (Next Sprint):**
1. Feature 1: Drag-and-Drop File Paths (4-6 hours)
2. Feature 2: Project Launcher (8-10 hours)

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
- **Lines of Code:** ~8,000+ Swift
- **Files:** 35+ Swift files
- **Documentation:** 13 markdown files
- **Development Time:** ~50+ hours
- **Features Complete:** 6 major features
- **Test Coverage:** Manual testing (200+ test cases for radial menu)

**Target for v2.0:**
- Drag-and-drop support
- Project launcher
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

**Last Updated:** 2025-01-05
**Next Review:** After Feature 1 & 2 implementation

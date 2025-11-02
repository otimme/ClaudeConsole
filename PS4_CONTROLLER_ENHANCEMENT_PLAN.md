# PS4 Controller Enhancement Plan
*Living Document - Last Updated: 2025-11-02*
*Phase 4 Completed: 2025-11-02*

## Project Overview

### Goal
Transform the PS4 controller from a simple key-mapping device into a comprehensive terminal control system supporting text macros, application commands, and intelligent multi-action sequences.

### Current Limitations
- Only supports single key or key+modifier combinations
- No text string/macro support
- Cannot trigger application features (speech-to-text, UI toggles)
- No multi-step actions or sequences
- Static mappings without context awareness

### Expected Outcomes
- Rich action system supporting multiple command types
- Seamless integration with app features
- Improved productivity with text macros
- Extensible architecture for future enhancements
- Maintained backward compatibility

## Technical Architecture

### New ButtonAction System

```swift
enum ButtonAction: Codable {
    case keyCommand(KeyCommand)           // Current functionality
    case textMacro(String, autoEnter: Bool) // Send text string
    case applicationCommand(AppCommand)    // Trigger app features
    case sequence([ButtonAction])          // Multi-step actions
    case shellCommand(String)              // Execute shell command
    case systemCommand(SystemCommand)      // macOS system functions
}

enum AppCommand: String, Codable {
    case triggerSpeechToText
    case stopSpeechToText
    case togglePS4Panel
    case toggleStatusBar
    case copyToClipboard
    case pasteFromClipboard
    case executeNamedMacro(String)
}

enum SystemCommand: String, Codable {
    case switchApplication(String)
    case takeScreenshot
    case openURL(String)
    case runAppleScript(String)
}
```

### Versioned Codable Implementation

```swift
struct PS4ButtonMappingData: Codable {
    let version: Int
    let mappings: [PS4Button: ButtonAction]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1

        switch version {
        case 1: // Legacy KeyCommand format
            let oldMappings = try container.decode([PS4Button: KeyCommand].self, forKey: .mappings)
            self.mappings = oldMappings.mapValues { ButtonAction.keyCommand($0) }
            self.version = 2

        case 2: // Current ButtonAction format
            self.mappings = try container.decode([PS4Button: ButtonAction].self, forKey: .mappings)
            self.version = 2

        default:
            throw DecodingError.dataCorrupted(...)
        }
    }
}
```

## Implementation Phases

### Phase 1: Core Data Model Extension ✅ (Completed - 2 hours)

**Tasks:**
- [x] Create `ButtonAction` enum with all action types
- [x] Create `AppCommand` and `SystemCommand` enums
- [x] Update `PS4ButtonMapping` to use new model
- [x] Implement versioned Codable with migration logic
- [x] Update UserDefaults save/load methods
- [x] Update PS4ControllerController to handle new action types
- [x] Update PS4ConfigurationView to use new ButtonAction
- [x] Test backward compatibility with existing mappings
- [x] Fix compilation issues and verify build success

**Implementation Notes:**
- Created new `ButtonAction.swift` file with comprehensive enum system
- Successfully implemented versioned Codable with automatic migration
- Updated all references from KeyCommand to ButtonAction
- Maintained backward compatibility with existing saved mappings
- Added legacy support methods for smooth transition

**Key Files Modified:**
- `ButtonAction.swift` - New file with action system
- `PS4ButtonMapping.swift` - Updated to use ButtonAction
- `PS4ControllerController.swift` - Added action executors
- `PS4ConfigurationView.swift` - Updated UI to use new model

**Testing Completed:**
- ✅ Project builds successfully
- ✅ V1 data automatically migrates to V2
- ✅ New action types (text macros, app commands) functional
- ✅ Presets updated with example mixed actions

### Phase 2: Text Macros & Basic Actions ✅ (Completed - 1.5 hours)

**Tasks:**
- [x] Add `sendTextMacroToTerminal()` method
- [x] Implement text escaping for special characters
- [x] Add auto-Enter option for macros
- [x] Create macro preset library
- [x] Add macro validation (max length, special chars)
- [x] Implement macro preview in UI
- [x] Add common presets:
  - [x] Git commands (status, add, commit, push)
  - [x] NPM commands (install, run dev, test)
  - [x] Docker commands (ps, logs, exec)
  - [x] Directory navigation
- [x] Create enhanced configuration UI with action type selection
- [x] Build preset picker/browser interface
- [x] Add dynamic replacements (date, time, user, pwd)

**Implementation Notes:**
- Created comprehensive `PS4EnhancedConfigView` with modern UI
- Implemented action type selector with segmented control
- Built specialized editors for each action type
- Added escape sequence processing (\\n, \\t, \\r, etc.)
- Implemented dynamic replacements:
  - `$(date)` - Current date/time
  - `$(time)` - Current time
  - `$(user)` - Username
  - `$(pwd)` - Working directory
- Created preset library with categorized macros
- Added character count validation (1000 char limit)
- Implemented action preview with color coding

**Key Features Added:**
- Text macro editor with live character count
- Preset browser with search and category filtering
- Special character reference guide
- Dynamic text replacements for common variables
- Auto-Enter toggle for each macro
- Visual preview of action before saving

**Preset Library Structure:**
```swift
struct MacroPreset {
    let name: String
    let category: String
    let macro: String
    let description: String
    let autoEnter: Bool
}
```

### Phase 3: Application Commands ⬜ (3-4 hours)

**Tasks:**
- [ ] Create `AppCommandExecutor` class
- [ ] Add public methods to `SpeechToTextController`:
  - [ ] `startRecordingViaController()`
  - [ ] `stopRecordingViaController()`
- [ ] Wire controller reference in `PS4ControllerController`
- [ ] Implement push-to-talk mode
- [ ] Implement toggle recording mode
- [ ] Add UI panel toggles
- [ ] Implement clipboard operations
- [ ] Add shell command execution with safety checks
- [ ] Create notification system for command feedback

**Implementation Notes:**
```swift
class AppCommandExecutor {
    weak var speechController: SpeechToTextController?
    weak var contentView: ContentView?

    func execute(_ command: AppCommand) {
        switch command {
        case .triggerSpeechToText:
            speechController?.startRecordingViaController()
        // ...
        }
    }
}
```

**Speech Integration Patterns:**
- Push-to-talk: Hold button → record → release → transcribe
- Toggle: Press → start recording → press again → stop
- Hybrid: Short press = single command, long hold = continuous

### Phase 4: Enhanced Configuration UI ✅ (Completed - 4 hours)

**Tasks:**
- [x] Add action type selector (segmented control)
- [x] Create `ButtonActionEditor` view (as `ActionEditorView`)
- [x] Implement conditional UI based on action type:
  - [x] Key capture field for KeyCommand
  - [x] Text input with preview for TextMacro
  - [x] Dropdown selector for AppCommand
  - [x] Shell command editor for ShellCommand
- [x] Add validation for each action type
- [x] Create action preview component
- [x] Add preset manager UI (MacroPresetPicker, PresetLibraryView)
- [x] Implement change tracking for save button
- [x] Add ScrollView for overflow content
- [ ] Implement import/export configuration (deferred)
- [ ] Create action testing mode (deferred)
- [ ] Add help tooltips for each action type (deferred)

**Implementation Notes:**
- Created comprehensive `PS4EnhancedConfigView` with modern UI
- Implemented specialized editors for each action type:
  - `KeyCommandEditor` with key capture functionality
  - `TextMacroEditor` with character count and preset browser
  - `AppCommandEditor` with radio button picker
  - `ShellCommandEditor` with text field
- Built preset library system with categories and search
- Added visual action preview with color-coded type badges
- Implemented smart save button with change tracking and success feedback
- Fixed critical button selection bug where clicking buttons loaded wrong data

**Key Bugs Fixed:**
1. **Button selection bug**: When clicking buttons in the list, the wrong action would load
   - Root cause: `onChange(of: button)` was reading stale `button` property
   - Fix: Changed `loadCurrentSettings()` to accept parameter `loadCurrentSettings(for: targetButton)`
2. **Action type not switching**: Clicking buttons didn't switch to correct tab (Key/Text/App/Shell)
   - Fix: Implemented `loadedActionType` tracking to prevent unwanted resets
   - Load data BEFORE changing `selectedActionType` to ensure proper state updates
3. **Preview labels not updating**: Button preview labels weren't refreshing after save
   - Fix: Added `objectWillChange.send()` and unique `.id()` modifiers
4. **Save button always enabled**: Button didn't reflect save state properly
   - Fix: Implemented `hasChanges` computed property and success indicator

**UI Components Created:**
- `PS4EnhancedConfigView` - Main container
- `ButtonListView` - Left panel with button selection
- `ButtonRow` - Individual button rows with preview labels
- `ActionEditorView` - Right panel with action editing
- `KeyCommandEditor`, `TextMacroEditor`, `AppCommandEditor`, `ShellCommandEditor` - Specialized editors
- `ActionPreview` - Visual preview of current action
- `MacroPresetPicker` - Preset browser with search and categories
- `PresetLibraryView` - Full preset set manager

**Key Files Modified:**
- `PS4EnhancedConfigView.swift` - Complete rewrite with all UI components
- `PS4ControllerView.swift` - Updated to use PS4EnhancedConfigView
- `ContentView.swift` - Updated PS4ControllerView initialization
- `PS4ButtonMapping.swift` - Added objectWillChange notifications

**Testing Completed:**
- ✅ All action types load correctly when clicking buttons
- ✅ Save button change tracking works properly
- ✅ Preview labels update after saving
- ✅ ScrollView handles content overflow
- ✅ Preset library functional with search and categories
- ✅ Button selection bug fixed (loads correct data)

### Phase 5: Button Combinations ⬜ (2-3 hours)

**Tasks:**
- [ ] Track modifier button states (L1/R1/L2/R2)
- [ ] Create `ModifierState` tracking system
- [ ] Implement secondary mapping layer
- [ ] Update mapping structure to support combinations
- [ ] Add visual feedback for active modifiers
- [ ] Update status bar to show combinations
- [ ] Create chord chart view
- [ ] Add combination validation (prevent conflicts)

**Implementation Notes:**
```swift
struct ButtonCombo: Hashable {
    let button: PS4Button
    let modifiers: Set<PS4Button>  // L1, R1, L2, R2
}

var comboMappings: [ButtonCombo: ButtonAction] = [:]
```

### Phase 6: Context Awareness ⬜ (Optional, 4-5 hours)

**Tasks:**
- [ ] Create `TerminalStateMonitor` class
- [ ] Implement process detection (ps, regex matching)
- [ ] Create profile system
- [ ] Add auto-switching logic
- [ ] Build default profiles:
  - [ ] Vim mode
  - [ ] Git mode
  - [ ] Docker mode
  - [ ] SSH mode
- [ ] Add profile management UI
- [ ] Implement profile import/export
- [ ] Create profile inheritance system

**Profile Structure:**
```swift
struct ControllerProfile {
    let name: String
    let triggers: [String]  // Process names or patterns
    let mappings: [PS4Button: ButtonAction]
    let parent: String?  // Inherit from another profile
}
```

### Phase 7: System Integration ⬜ (Optional, 3-4 hours)

**Tasks:**
- [ ] Request Accessibility permissions
- [ ] Implement application switching via Accessibility API
- [ ] Create AppleScript bridge
- [ ] Add system-wide hotkey support
- [ ] Implement screenshot capture
- [ ] Add URL opening support
- [ ] Create security permission checker
- [ ] Add sandboxing considerations

## Testing Checklist

### Unit Tests
- [ ] ButtonAction Codable encoding/decoding
- [ ] Version migration from v1 to v2
- [ ] Text macro escaping
- [ ] Button combo detection
- [ ] Profile trigger matching

### Integration Tests
- [ ] Terminal command execution
- [ ] Speech-to-text triggering
- [ ] UI panel toggling
- [ ] Configuration saving/loading
- [ ] Multi-step sequences

### User Acceptance Criteria
- [ ] Existing mappings preserved after update
- [ ] All buttons remain configurable
- [ ] Visual feedback works for all action types
- [ ] No terminal lag with complex actions
- [ ] Configuration UI intuitive for new users

## Technical Decisions Log

### Decision 1: Enum vs Protocol for ButtonAction
- **Chosen:** Enum with associated values
- **Rationale:** Simpler Codable implementation, exhaustive switching
- **Alternative:** Protocol-based with concrete types
- **Trade-off:** Less extensible but more maintainable

### Decision 2: Speech-to-Text Integration
- **Chosen:** Direct controller reference with weak binding
- **Rationale:** Simple, avoids complex event chains
- **Alternative:** NotificationCenter events
- **Trade-off:** Tighter coupling but clearer flow

### Decision 3: Versioning Strategy
- **Chosen:** Integer version with migration chain
- **Rationale:** Simple, proven pattern
- **Alternative:** Semantic versioning
- **Trade-off:** Less granular but sufficient for needs

## Performance Considerations

- **Memory:** Limit macro length to 1000 characters
- **CPU:** Debounce rapid button presses (50ms)
- **Latency:** Pre-compile terminal escape sequences
- **Storage:** Compress configuration for large macro libraries

## Issues & Solutions

| Issue | Solution | Status |
|-------|----------|--------|
| Button selection loads wrong action data | Changed `loadCurrentSettings()` to accept button parameter to use fresh value from `onChange` | ✅ Fixed |
| Action type tab doesn't switch when clicking buttons | Implemented `loadedActionType` tracking to distinguish programmatic vs manual tab changes | ✅ Fixed |
| Preview labels don't update after saving | Added `objectWillChange.send()` and unique `.id()` modifiers based on action content | ✅ Fixed |
| Save button always enabled | Implemented `hasChanges` computed property comparing current state with `savedAction` | ✅ Fixed |
| App Command UI overflows window | Wrapped content in ScrollView with fixed header/footer | ✅ Fixed |
| onChange handler resets fields during load | Load field data BEFORE changing `selectedActionType`, use `loadedActionType` to skip reset | ✅ Fixed |

## Future Development

### Tier 1: High-Impact Enhancements

#### 1. Analog Stick Functionality 🕹️
- **Left Stick:** Scroll terminal output (vertical) and command history (horizontal)
- **Right Stick:** Mouse cursor control for clicking terminal links
- **Stick Clicks (L3/R3):** Quick access to frequently used macros
- **Velocity Sensitivity:** Faster movement = increased scroll speed

#### 2. LED Bar Feedback System 💡
- Green: Command succeeded
- Red: Command failed
- Yellow: Long-running process
- Blue: Awaiting input
- Purple: SSH/remote session active
- Pulsing: Recording macro
- Rainbow: Claude Code active

#### 3. Pressure-Sensitive Triggers 🎚️
- Light press: Preview command without executing
- Full press: Execute command
- Variable pressure: Control key repeat rate
- Pressure thresholds: Different actions at 25%, 50%, 75%, 100%

#### 4. Visual Command Palette 📊
- Hold PS button for radial menu
- Categories: Git, Docker, NPM, Navigation, Custom
- Analog stick navigation
- Recently used commands bubble to top
- Search-as-you-type with on-screen keyboard

#### 5. Haptic Feedback 🎮
- Success/failure vibration patterns
- Gentle pulse on modifier hold
- Strong warning for dangerous commands
- Custom patterns per action type
- Adjustable intensity settings

### Tier 2: Advanced Features

#### 6. Recording & Playback System 📹
- Press Share+Options to start recording
- Record terminal input sequences
- Save as named, reusable macros
- Variable-speed playback
- Export/share macro libraries
- Version control for macros

#### 7. Intelligent Command Suggestions 🤖
- ML-based command prediction
- Context-aware suggestions based on directory
- Usage pattern learning
- Adaptive button remapping based on frequency
- Command completion with partial matching

#### 8. Multi-Controller Support 🎮🎮
- Use multiple controllers simultaneously
- Assign different roles (navigation vs macros)
- User-specific controller profiles
- Hot-swapping support
- Controller identification by LED color

#### 9. Gesture Support 👆
Using DualShock 4 gyroscope:
- Shake to clear terminal
- Tilt for tab switching
- Rotate for history scrolling
- Quick flick for last command
- Custom gesture recording

#### 10. Contextual Profile Auto-Detection 🔄
- Process-based profile switching
- Directory-based profiles
- Git branch-aware mappings
- SSH host-specific configurations
- Time-of-day profiles

### Tier 3: Ecosystem Features

#### 11. Advanced Sequence Builder 🔗
- Conditional logic (if/then/else)
- Loops and iterations
- Variable substitution
- User input prompts
- Delay/timing controls
- Error handling

#### 12. Terminal State Awareness 🧠
- Detect input prompts (password, y/n)
- Auto-map buttons to likely responses
- Conflict detection and resolution helpers
- Syntax error prevention
- Command validation before execution

#### 13. Clipboard Integration Plus 📋
- Clipboard history navigation with D-pad
- Format-aware pasting:
  - X: Raw paste
  - Square: Quoted paste
  - Triangle: URL-encoded
  - Circle: JSON-escaped
- Clipboard transformation pipelines

#### 14. Network Actions 🌐
- One-button SSH to favorites
- Quick port forwarding
- VPN toggle
- Network diagnostics suite
- API testing shortcuts

#### 15. Development Workflow Integration 👨‍💻
**Git Flow:**
- L1+D-pad: Branch operations
- R1+Face: Commit operations
- L2+R2: Push/pull

**Docker:**
- Container management overlay
- Quick compose commands
- Log streaming controls

**Testing:**
- Test runner integration
- Coverage visualization
- Watch mode toggle

#### 16. Claude Code Integration 🤖
- Direct `/usage` and `/context` mappings
- "Ask Claude about last error" button
- Save Claude suggestions as macros
- Context injection shortcuts
- Model switching

#### 17. Accessibility Suite ♿
- Sticky modifiers (double-tap to lock)
- One-handed operation modes
- Voice feedback for actions
- Visual feedback enhancements
- Customizable timing/sensitivity
- Colorblind-friendly themes

#### 18. Session Management 💾
- Save/restore terminal states
- Workspace quick-switching
- Session templates
- Bookmark specific states
- Session sharing between devices

#### 19. Time-Based Actions ⏰
- Schedule macro execution
- Time-of-day profiles
- Pomodoro timer integration
- Meeting-aware quiet modes
- Daily standup automations

#### 20. Chording System 🎹
- Multi-button combinations
- Visual chord chart
- Conflict detection
- Training mode
- Custom chord definitions

### Implementation Priority Matrix

| Feature | Impact | Complexity | Priority |
|---------|--------|------------|----------|
| Analog Sticks | High | Medium | P1 |
| LED Feedback | High | Low | P1 |
| Pressure Triggers | High | Medium | P1 |
| Command Palette | High | Medium | P1 |
| Haptic Feedback | Medium | Low | P2 |
| Recording System | High | High | P2 |
| Smart Suggestions | High | High | P3 |
| Gesture Support | Medium | Medium | P3 |
| Multi-Controller | Low | High | P4 |

### Technical Requirements for Future Features

**Hardware Access:**
- GameController framework extensions
- IOKit for LED control
- Core Motion for gyroscope
- AVFoundation for haptics

**Machine Learning:**
- Core ML for command prediction
- Natural Language framework
- CreateML for pattern learning

**System Integration:**
- Accessibility API permissions
- AppleScript bridge
- Notification Center integration
- CloudKit for sync

## Notes

- This document is actively maintained during development
- Check git history for change tracking
- Report issues in GitHub Issues
- Feature requests welcome via PR

---

*End of Document - Version 1.0*
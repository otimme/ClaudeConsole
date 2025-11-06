# Theme Customization Implementation Plan

**Date Created:** 2025-11-06
**Status:** Research Complete - Implementation Pending
**Estimated Time:** 15-20 days

---

## Executive Summary

This document outlines a comprehensive theme customization system for ClaudeConsole that allows users to customize terminal colors, UI panels, PS4 controller visualizations, and radial menus. The system will support preset themes, custom theme creation, and import/export capabilities.

---

## Current Implementation Analysis

### 1. Terminal Colors (TerminalView.swift)

**Current State:**
- Lines 382-386: Hardcoded terminal colors using system defaults
  ```swift
  terminalView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
  terminalView.nativeForegroundColor = NSColor.textColor
  terminalView.nativeBackgroundColor = NSColor.textBackgroundColor
  ```

**SwiftTerm Capabilities:**
- `nativeForegroundColor` - Terminal text color (NSColor)
- `nativeBackgroundColor` - Terminal background color (NSColor)
- `configureNativeColors()` - Method to apply OS defaults
- Supports ANSI 16-color palette, 256-color mode, and TrueColor (24-bit RGB)

### 2. UI Panel Colors

**Stats Panels:**
- `RealUsageStatsView.swift`
  - Lines 94-102: Dynamic progress bar colors (green/orange/red based on usage)
  - Line 103: Uses `Color(NSColor.controlBackgroundColor)` for background

- `ContextStatsView.swift`
  - Lines 52-57: StatPill colors (.blue, .purple, .orange, .gray, .green)
  - Lines 63-71: Progress bar colors based on percentage

**ContentView:**
- Lines 103, 244: Uses `Color(NSColor.controlBackgroundColor)`
- Lines 178: Uses `Color(NSColor.windowBackgroundColor)`

### 3. PS4 Controller Visualization

**PS4ControllerView.swift:**
- Lines 204-217: Button colors defined per type:
  - Cross: `.blue`
  - Circle: `.red`
  - Square: `.pink`
  - Triangle: `.green`
  - Shoulders (L1/R1/L2/R2): `.orange`
  - D-pad: `.gray`
  - Analog sticks (L3/R3): `.purple`
  - Options/Share: `.cyan`
  - Touchpad: `.indigo`

**PS4ControllerStatusBar.swift:**
- Lines 137-150: Button highlight colors with opacity variations
- Lines 204-217: Duplicates button color logic from main view

### 4. Radial Menu System

**RadialMenuView.swift:**
- Lines 30-35: Dark theme with custom hex colors:
  - Background: `#1A1A1A` with 95% opacity
  - Selected: `#4A9EFF` (blue)
  - Default: `#2A2A2A` (dark gray)
- Lines 289-297: Action type colors:
  - Key command: `.blue`
  - Text macro: `.green`
  - App command: `.purple`
  - Shell command: `.orange`
  - System command: `.red`
  - Sequence: `.cyan`

**ProfileSwitcherView.swift:**
- Lines 30-35: Similar dark theme with `#1A1A2E` background
- Lines 175, 195-198: Active profile indicator in green (`#4CAF50`)
- Lines 191-199: State-based fill colors (selected/active/default)

---

## Industry Standard Theme Formats

### Terminal.app (.terminal format)
Standard macOS Terminal themes include:
- Background color
- Foreground/text color
- ANSI colors (16 colors: 8 standard + 8 bright variants)
- Cursor color
- Selection color
- Bold text color

### iTerm2 Color Schemes
More comprehensive with:
- All ANSI colors
- Background/foreground
- Selection color
- Cursor color
- Link color
- Badge color

### Popular Theme Examples
- **Dracula**: Dark purple background, soft colors
- **Solarized Dark/Light**: Scientific color palette
- **Atom One Dark**: Syntax-highlighted style
- **Nord**: Arctic-inspired palette
- **Monokai**: Sublime Text classic
- **Gruvbox**: Retro groove colors

---

## Proposed Theme System Architecture

### Data Models

```swift
// Core theme model
struct Theme: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var author: String
    var description: String

    // Terminal colors
    var terminal: TerminalColors

    // UI colors
    var ui: UIColors

    // Controller visualization colors
    var controller: ControllerColors

    // Radial menu colors
    var radialMenu: RadialMenuColors

    // Metadata
    var createdDate: Date
    var modifiedDate: Date
    var isBuiltIn: Bool
}

// Terminal color scheme
struct TerminalColors: Codable, Equatable {
    var background: CodableColor
    var foreground: CodableColor
    var cursor: CodableColor
    var selection: CodableColor

    // ANSI colors (0-15)
    var ansiBlack: CodableColor
    var ansiRed: CodableColor
    var ansiGreen: CodableColor
    var ansiYellow: CodableColor
    var ansiBlue: CodableColor
    var ansiMagenta: CodableColor
    var ansiCyan: CodableColor
    var ansiWhite: CodableColor

    // Bright variants
    var ansiBrightBlack: CodableColor
    var ansiBrightRed: CodableColor
    var ansiBrightGreen: CodableColor
    var ansiBrightYellow: CodableColor
    var ansiBrightBlue: CodableColor
    var ansiBrightMagenta: CodableColor
    var ansiBrightCyan: CodableColor
    var ansiBrightWhite: CodableColor
}

// UI panel colors
struct UIColors: Codable, Equatable {
    var windowBackground: CodableColor
    var panelBackground: CodableColor
    var divider: CodableColor

    // Stats view colors
    var progressLow: CodableColor      // < 70%
    var progressMedium: CodableColor   // 70-90%
    var progressHigh: CodableColor     // > 90%

    // Context stat pills
    var systemColor: CodableColor
    var agentsColor: CodableColor
    var messagesColor: CodableColor
    var bufferColor: CodableColor
    var freeSpaceColor: CodableColor
}

// PS4 Controller colors
struct ControllerColors: Codable, Equatable {
    var crossButton: CodableColor
    var circleButton: CodableColor
    var squareButton: CodableColor
    var triangleButton: CodableColor
    var shoulderButtons: CodableColor
    var dpadButtons: CodableColor
    var analogSticks: CodableColor
    var centerButtons: CodableColor
    var touchpad: CodableColor
    var psButton: CodableColor
}

// Radial menu colors
struct RadialMenuColors: Codable, Equatable {
    var background: CodableColor
    var selectedSegment: CodableColor
    var defaultSegment: CodableColor
    var activeProfile: CodableColor

    // Action type colors
    var keyCommandAction: CodableColor
    var textMacroAction: CodableColor
    var appCommandAction: CodableColor
    var shellCommandAction: CodableColor
    var systemCommandAction: CodableColor
    var sequenceAction: CodableColor
}

// Color wrapper for Codable support
struct CodableColor: Codable, Equatable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    init(nsColor: NSColor) {
        let converted = nsColor.usingColorSpace(.deviceRGB)!
        self.red = Double(converted.redComponent)
        self.green = Double(converted.greenComponent)
        self.blue = Double(converted.blueComponent)
        self.alpha = Double(converted.alphaComponent)
    }

    var nsColor: NSColor {
        NSColor(
            red: CGFloat(red),
            green: CGFloat(green),
            blue: CGFloat(blue),
            alpha: CGFloat(alpha)
        )
    }

    var swiftUIColor: Color {
        Color(nsColor: nsColor)
    }
}
```

### Theme Manager

```swift
class ThemeManager: ObservableObject {
    @Published var activeTheme: Theme
    @Published var availableThemes: [Theme]

    private let userDefaultsKey = "selectedThemeID"
    private let customThemesKey = "customThemes"

    init() {
        // Load built-in themes
        self.availableThemes = ThemeManager.builtInThemes()

        // Load custom themes from UserDefaults
        self.availableThemes.append(contentsOf: ThemeManager.loadCustomThemes())

        // Load active theme from UserDefaults or use default
        if let savedThemeID = UserDefaults.standard.string(forKey: userDefaultsKey),
           let theme = availableThemes.first(where: { $0.id.uuidString == savedThemeID }) {
            self.activeTheme = theme
        } else {
            self.activeTheme = availableThemes[0]
        }
    }

    // Apply theme to application
    func applyTheme(_ theme: Theme) {
        activeTheme = theme
        UserDefaults.standard.set(theme.id.uuidString, forKey: userDefaultsKey)

        // Post notification for components to update
        NotificationCenter.default.post(
            name: .themeChanged,
            object: nil,
            userInfo: ["theme": theme]
        )
    }

    // Save custom theme
    func saveCustomTheme(_ theme: Theme) {
        if !theme.isBuiltIn {
            if let index = availableThemes.firstIndex(where: { $0.id == theme.id }) {
                availableThemes[index] = theme
            } else {
                availableThemes.append(theme)
            }
            saveCustomThemes()
        }
    }

    // Delete custom theme
    func deleteTheme(_ theme: Theme) {
        guard !theme.isBuiltIn else { return }
        availableThemes.removeAll { $0.id == theme.id }
        saveCustomThemes()

        if activeTheme.id == theme.id {
            applyTheme(availableThemes[0])
        }
    }

    // Export theme to JSON
    func exportTheme(_ theme: Theme) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(theme),
              let json = String(data: data, encoding: .utf8) else {
            return nil
        }
        return json
    }

    // Import theme from JSON
    func importTheme(from json: String) -> Theme? {
        guard let data = json.data(using: .utf8),
              var theme = try? JSONDecoder().decode(Theme.self, from: data) else {
            return nil
        }

        // Assign new ID and mark as custom
        theme.id = UUID()
        theme.isBuiltIn = false
        theme.modifiedDate = Date()

        availableThemes.append(theme)
        saveCustomThemes()

        return theme
    }

    // MARK: - Private Methods

    private func saveCustomThemes() {
        let customThemes = availableThemes.filter { !$0.isBuiltIn }
        if let data = try? JSONEncoder().encode(customThemes) {
            UserDefaults.standard.set(data, forKey: customThemesKey)
        }
    }

    private static func loadCustomThemes() -> [Theme] {
        guard let data = UserDefaults.standard.data(forKey: "customThemes"),
              let themes = try? JSONDecoder().decode([Theme].self, from: data) else {
            return []
        }
        return themes
    }

    // MARK: - Built-in Themes

    private static func builtInThemes() -> [Theme] {
        return [
            defaultTheme(),
            draculaTheme(),
            solarizedDarkTheme(),
            solarizedLightTheme(),
            nordTheme(),
            monokaiTheme(),
            atomOneDarkTheme(),
            gruvboxDarkTheme(),
            oceanTheme(),
            materialTheme()
        ]
    }

    // Theme presets defined here...
}

// Notification for theme changes
extension Notification.Name {
    static let themeChanged = Notification.Name("themeChanged")
}
```

---

## UI Implementation

### 1. Theme Selector (Toolbar/Menu)

Add to ContentView toolbar:
```swift
ToolbarItem(placement: .primaryAction) {
    Menu {
        ForEach(themeManager.availableThemes) { theme in
            Button(theme.name) {
                themeManager.applyTheme(theme)
            }
        }

        Divider()

        Button("Edit Themes...") {
            showThemeEditor = true
        }
    } label: {
        Image(systemName: "paintpalette")
    }
}
```

### 2. Theme Editor View

Full-featured editor with:
- **Theme list** (left panel)
- **Color editor** (right panel)
- **Live preview** (terminal + UI samples)
- **Import/Export buttons**

```swift
struct ThemeEditorView: View {
    @ObservedObject var themeManager: ThemeManager
    @State private var selectedTheme: Theme?
    @State private var editingTheme: Theme?

    var body: some View {
        HSplitView {
            // Left: Theme list
            ThemeListPanel(
                themes: themeManager.availableThemes,
                selectedTheme: $selectedTheme,
                onDuplicate: { /* ... */ },
                onDelete: { /* ... */ },
                onNew: { /* ... */ }
            )

            // Right: Color editor
            if let theme = editingTheme {
                ThemeColorEditorPanel(
                    theme: $editingTheme,
                    onSave: { themeManager.saveCustomTheme(theme) }
                )
            }
        }
        .frame(width: 1000, height: 700)
    }
}

struct ThemeColorEditorPanel: View {
    @Binding var theme: Theme
    let onSave: () -> Void

    @State private var selectedSection: ThemeSection = .terminal

    enum ThemeSection: String, CaseIterable {
        case terminal = "Terminal"
        case ui = "UI Panels"
        case controller = "Controller"
        case radialMenu = "Radial Menu"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Section picker
            Picker("Section", selection: $selectedSection) {
                ForEach(ThemeSection.allCases, id: \.self) { section in
                    Text(section.rawValue).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            Divider()

            // Color editors based on section
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch selectedSection {
                    case .terminal:
                        TerminalColorsEditor(colors: $theme.terminal)
                    case .ui:
                        UIColorsEditor(colors: $theme.ui)
                    case .controller:
                        ControllerColorsEditor(colors: $theme.controller)
                    case .radialMenu:
                        RadialMenuColorsEditor(colors: $theme.radialMenu)
                    }
                }
                .padding()
            }

            Divider()

            // Action buttons
            HStack {
                Button("Reset to Default") {
                    // Reset current section to defaults
                }

                Spacer()

                Button("Save") {
                    onSave()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
    }
}

// Color picker row component
struct ColorPickerRow: View {
    let label: String
    @Binding var color: CodableColor

    var body: some View {
        HStack {
            Text(label)
                .frame(width: 150, alignment: .leading)

            ColorPicker("", selection: Binding(
                get: { color.swiftUIColor },
                set: { color = CodableColor(nsColor: NSColor($0)) }
            ))
            .labelsHidden()

            // Hex display
            Text(colorToHex(color))
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
        }
    }

    private func colorToHex(_ color: CodableColor) -> String {
        let r = Int(color.red * 255)
        let g = Int(color.green * 255)
        let b = Int(color.blue * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
```

### 3. Integration Points

**TerminalView.swift** (lines 381-386):
```swift
// Replace hardcoded colors with theme
func applyTheme(_ theme: Theme) {
    self.nativeForegroundColor = theme.terminal.foreground.nsColor
    self.nativeBackgroundColor = theme.terminal.background.nsColor
    // Apply ANSI palette colors via SwiftTerm API
}
```

**RealUsageStatsView.swift** (lines 94-102):
```swift
private func colorForPercentage(_ percentage: Double, theme: Theme) -> Color {
    if percentage >= 90 {
        return theme.ui.progressHigh.swiftUIColor
    } else if percentage >= 70 {
        return theme.ui.progressMedium.swiftUIColor
    } else {
        return theme.ui.progressLow.swiftUIColor
    }
}
```

**PS4ControllerView.swift** (lines 204-217):
```swift
var buttonColor: Color {
    switch button {
    case .cross: return themeManager.activeTheme.controller.crossButton.swiftUIColor
    case .circle: return themeManager.activeTheme.controller.circleButton.swiftUIColor
    // ... etc
    }
}
```

**RadialMenuView.swift** (lines 30-35, 100):
```swift
Circle()
    .fill(themeManager.activeTheme.radialMenu.background.swiftUIColor)
    // ...
```

---

## Preset Themes to Include

### 1. **Default** (Current)
- Clean system colors
- Light/dark mode adaptive

### 2. **Dracula**
- Background: `#282a36`
- Foreground: `#f8f8f2`
- Selection: `#44475a`
- Purple/pink accent colors

### 3. **Solarized Dark**
- Background: `#002b36`
- Foreground: `#839496`
- Scientific color palette

### 4. **Solarized Light**
- Background: `#fdf6e3`
- Foreground: `#657b83`
- Light variant

### 5. **Nord**
- Background: `#2e3440`
- Foreground: `#d8dee9`
- Arctic-inspired blues/greens

### 6. **Monokai**
- Background: `#272822`
- Foreground: `#f8f8f2`
- Vibrant syntax colors

### 7. **Atom One Dark**
- Background: `#282c34`
- Foreground: `#abb2bf`
- GitHub-inspired

### 8. **Gruvbox Dark**
- Background: `#282828`
- Foreground: `#ebdbb2`
- Retro warm colors

### 9. **Ocean**
- Background: `#1c1f24`
- Foreground: `#c0c5ce`
- Blue-tinted dark theme

### 10. **Material**
- Background: `#263238`
- Foreground: `#eeffff`
- Material Design colors

---

## Implementation Phases

### Phase 1: Core Infrastructure (2-3 days)
- Create data models (Theme, TerminalColors, UIColors, ControllerColors, RadialMenuColors)
- Implement ThemeManager with persistence
- Add theme change notifications
- Create CodableColor wrapper

**Files to create:**
- `/ClaudeConsole/Theme/Theme.swift`
- `/ClaudeConsole/Theme/ThemeManager.swift`

### Phase 2: Terminal Integration (1-2 days)
- Apply theme colors to TerminalView
- Research SwiftTerm ANSI palette API
- Implement terminal color updates on theme change
- Test color rendering

**Files to modify:**
- `/ClaudeConsole/TerminalView.swift`

### Phase 3: UI Panel Integration (2 days)
- Update RealUsageStatsView with theme colors
- Update ContextStatsView with theme colors
- Update ContentView backgrounds
- Ensure all panels respond to theme changes

**Files to modify:**
- `/ClaudeConsole/RealUsageStatsView.swift`
- `/ClaudeConsole/ContextStatsView.swift`
- `/ClaudeConsole/ContentView.swift`

### Phase 4: Controller Integration (1-2 days)
- Update PS4ControllerView button colors
- Update PS4ControllerStatusBar colors
- Maintain visual feedback/pressed states

**Files to modify:**
- `/ClaudeConsole/PS4ControllerView.swift`
- `/ClaudeConsole/PS4ControllerStatusBar.swift`

### Phase 5: Radial Menu Integration (1 day)
- Update RadialMenuView colors
- Update ProfileSwitcherView colors
- Maintain selection/active state visuals

**Files to modify:**
- `/ClaudeConsole/RadialMenuView.swift`
- `/ClaudeConsole/ProfileSwitcherView.swift`

### Phase 6: Theme Editor UI (3-4 days)
- Build theme list panel
- Build color editor panel
- Add live preview
- Implement save/duplicate/delete

**Files to create:**
- `/ClaudeConsole/Theme/ThemeEditorView.swift`
- `/ClaudeConsole/Theme/ThemeListPanel.swift`
- `/ClaudeConsole/Theme/ThemeColorEditorPanel.swift`
- `/ClaudeConsole/Theme/ColorPickerRow.swift`
- `/ClaudeConsole/Theme/ThemePreview.swift`

### Phase 7: Preset Themes (2 days)
- Implement 10 built-in themes
- Test each theme across all components
- Fine-tune colors for consistency

**Files to create:**
- `/ClaudeConsole/Theme/ThemePresets.swift`

### Phase 8: Import/Export (1 day)
- Add JSON export functionality
- Add JSON import with validation
- File picker integration
- Error handling

**Files to modify:**
- `/ClaudeConsole/Theme/ThemeManager.swift`
- `/ClaudeConsole/Theme/ThemeEditorView.swift`

### Phase 9: Polish & Testing (2-3 days)
- Keyboard shortcuts for theme switching
- Theme preview thumbnails
- Transition animations
- Comprehensive testing
- Documentation

**Files to modify:**
- `/ClaudeConsole/ContentView.swift`
- `/ClaudeConsole/ClaudeConsoleApp.swift`

**Total Estimated Time: 15-20 days**

---

## Technical Considerations

### 1. SwiftTerm ANSI Color Palette
Need to research SwiftTerm's API for setting ANSI colors (0-15). Likely methods:
- `terminal.setAnsiColor(index:color:)` or similar
- May need to access Terminal instance from TerminalView

### 2. Color Persistence
Use UserDefaults for:
- Active theme ID
- Custom theme definitions (JSON)

### 3. Theme Transitions
Smooth color transitions when switching themes:
```swift
.animation(.easeInOut(duration: 0.3), value: themeManager.activeTheme)
```

### 4. Light/Dark Mode
Option 1: Separate themes for light/dark
Option 2: Single theme with adaptive colors
**Recommendation:** Option 1 for more control

### 5. Import Validation
Validate imported JSON:
- Check all required color fields
- Verify color values in valid range (0-1)
- Handle missing fields with defaults

---

## Files Summary

### New Files (8)
1. `/ClaudeConsole/Theme/Theme.swift` - Data models
2. `/ClaudeConsole/Theme/ThemeManager.swift` - Theme management
3. `/ClaudeConsole/Theme/ThemePresets.swift` - Built-in themes
4. `/ClaudeConsole/Theme/ThemeEditorView.swift` - Main editor
5. `/ClaudeConsole/Theme/ThemeListPanel.swift` - Theme selector
6. `/ClaudeConsole/Theme/ThemeColorEditorPanel.swift` - Color editing
7. `/ClaudeConsole/Theme/ColorPickerRow.swift` - Reusable component
8. `/ClaudeConsole/Theme/ThemePreview.swift` - Live preview

### Modified Files (9)
1. `/ClaudeConsole/TerminalView.swift` - Apply terminal colors
2. `/ClaudeConsole/ContentView.swift` - Add theme manager, toolbar
3. `/ClaudeConsole/RealUsageStatsView.swift` - Use theme colors
4. `/ClaudeConsole/ContextStatsView.swift` - Use theme colors
5. `/ClaudeConsole/PS4ControllerView.swift` - Use theme colors
6. `/ClaudeConsole/PS4ControllerStatusBar.swift` - Use theme colors
7. `/ClaudeConsole/RadialMenuView.swift` - Use theme colors
8. `/ClaudeConsole/ProfileSwitcherView.swift` - Use theme colors
9. `/ClaudeConsole/ClaudeConsoleApp.swift` - Initialize theme manager

---

## Success Criteria

1. ✅ Users can select from 10+ preset themes
2. ✅ All UI elements update instantly when theme changes
3. ✅ Terminal colors fully customizable (background, foreground, ANSI palette)
4. ✅ Theme editor allows per-color customization
5. ✅ Custom themes persist across app launches
6. ✅ Import/export themes as JSON files
7. ✅ No visual glitches during theme transitions
8. ✅ Themes remain consistent across light/dark mode
9. ✅ PS4 controller visualizations maintain clarity with custom colors
10. ✅ Radial menu remains readable with all themes

---

## Future Enhancements

- **iTerm2 Import**: Parse and import iTerm2 color schemes
- **Terminal.app Import**: Parse .terminal files
- **Theme Marketplace**: Community sharing platform
- **Dynamic Themes**: Time-based theme switching (light during day, dark at night)
- **Per-Profile Themes**: Different themes for different PS4 controller profiles
- **Color Palette Generator**: Auto-generate complementary colors
- **Accessibility Mode**: High-contrast themes for better readability

---

**Last Updated:** 2025-11-06
**Status:** Ready for implementation when prioritized

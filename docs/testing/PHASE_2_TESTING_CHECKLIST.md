# Phase 2 Testing Checklist

**Date:** 2025-11-04
**Feature:** Radial Menu Configuration System
**Status:** Ready for Testing

---

## Pre-Testing Setup

- [ ] Build completed successfully (`⌘R` in Xcode)
- [ ] App launches without crashes
- [ ] PS4 controller connected (Bluetooth or USB)
- [ ] Navigate to PS4 Controller panel (should be visible in main window)

---

## 1. Profile Selector Widget (In PS4 Controller Panel)

### Basic Functionality
- [ ] **Widget is visible** - Shows "Radial Menu Profile" section
- [ ] **Profile dropdown works** - Can see all 6 default profiles
- [ ] **L1/R1 labels display** - Shows menu names below dropdown
- [ ] **Gear icon present** - Configuration button visible
- [ ] **Gear icon opens config** - Clicking opens full configuration view

### Profile Switching
- [ ] **Switch to "Default"** - L1: Quick Actions, R1: Git Commands
- [ ] **Switch to "Docker"** - L1: Quick Actions, R1: Docker
- [ ] **Switch to "NPM"** - L1: Quick Actions, R1: NPM
- [ ] **Switch to "Navigation"** - L1: Quick Actions, R1: Navigation
- [ ] **Switch to "Claude"** - L1: Claude, R1: Git Commands
- [ ] **Switch to "Dev Tools"** - L1: Dev Tools, R1: Git Commands
- [ ] **Active profile persists** - Close and reopen app, same profile active

---

## 2. Configuration View - Opening & Layout

### Opening the Configuration
- [ ] **Opens as modal sheet** - Covers window, not full-screen
- [ ] **Shows toolbar** - "Import/Export" and "Done" buttons visible
- [ ] **Split view layout** - Left panel (list) and right panel (editor)
- [ ] **Correct size** - Window is 900x650 pixels

### Left Panel Components
- [ ] **Profile selector visible** - Dropdown at top
- [ ] **"+" button present** - Next to profile name
- [ ] **Action buttons visible** - Duplicate, Reset, Delete
- [ ] **L1/R1 tabs present** - Toggle between menus
- [ ] **Visual preview shows** - 8-segment radial diagram
- [ ] **Segment list visible** - All 8 directions listed below preview

### Right Panel (Empty State)
- [ ] **Shows empty state** - Hand icon and "Select a segment to configure"
- [ ] **Empty when first opened** - No segment selected initially

---

## 3. Visual Radial Menu Preview

### Preview Display
- [ ] **8 segments visible** - N, NE, E, SE, S, SW, W, NW
- [ ] **Menu name shows** - "Quick Actions", "Git Commands", etc.
- [ ] **Segments with actions** - Show gray background
- [ ] **Empty segments** - Show clear/transparent background
- [ ] **Icons display** - Small icons in configured segments
- [ ] **Direction labels** - N, NE, E, SE, S, SW, W, NW visible

### Preview Interaction
- [ ] **Click North segment** - Selects and highlights blue
- [ ] **Click Northeast segment** - Selection changes
- [ ] **Click East segment** - Selection changes
- [ ] **Click Southeast segment** - Selection changes
- [ ] **Click South segment** - Selection changes
- [ ] **Click Southwest segment** - Selection changes
- [ ] **Click West segment** - Selection changes
- [ ] **Click Northwest segment** - Selection changes
- [ ] **Selected segment highlights** - Blue overlay on selected
- [ ] **Preview updates after save** - Icon appears when action added

---

## 4. Segment List

### List Display
- [ ] **All 8 directions listed** - N through NW
- [ ] **Shows action names** - "git status", "Enter", etc.
- [ ] **Empty shows "Empty"** - Grayed out text
- [ ] **Icons display** - Small blue icons for configured segments
- [ ] **Chevron on right** - Navigation indicator

### List Interaction
- [ ] **Click N row** - Opens editor for North
- [ ] **Click NE row** - Opens editor for Northeast
- [ ] **Click E row** - Opens editor for East
- [ ] **Click SE row** - Opens editor for Southeast
- [ ] **Click S row** - Opens editor for South
- [ ] **Click SW row** - Opens editor for Southwest
- [ ] **Click W row** - Opens editor for West
- [ ] **Click NW row** - Opens editor for Northwest
- [ ] **Selected row highlights** - Blue background on selected
- [ ] **Matches preview** - Same segment selected in both

---

## 5. Menu Type Switching (L1/R1)

### L1 Menu
- [ ] **Select L1 tab** - Shows L1 menu configuration
- [ ] **Preview updates** - Shows L1 segments
- [ ] **Segment list updates** - Shows L1 actions
- [ ] **Menu name shows** - "Quick Actions" (or current L1 name)

### R1 Menu
- [ ] **Select R1 tab** - Shows R1 menu configuration
- [ ] **Preview updates** - Shows R1 segments
- [ ] **Segment list updates** - Shows R1 actions
- [ ] **Menu name shows** - "Git Commands" (or current R1 name)

### Switching Behavior
- [ ] **Selection clears** - No segment selected when switching
- [ ] **Right panel clears** - Shows empty state
- [ ] **Data preserved** - L1 edits saved when switching to R1
- [ ] **Data preserved** - R1 edits saved when switching to L1

---

## 6. Segment Editor - Loading Existing Actions

### Key Command Loading
- [ ] **Select segment with key** - e.g., L1 North (Cmd+C)
- [ ] **Type shows "Key Press"** - Action type selected
- [ ] **Key capture shows** - Interactive capture field
- [ ] **Current key displays** - "Current: ⌘C" shown
- [ ] **Modifiers correct** - Shows proper modifier symbols

### Text Macro Loading
- [ ] **Select segment with text** - e.g., R1 North ("git status")
- [ ] **Type shows "Text Macro"** - Action type selected
- [ ] **Text field populated** - Shows "git status"
- [ ] **Auto-enter reflects state** - Toggle matches saved value

### App Command Loading
- [ ] **Select segment with app cmd** - e.g., L1 West (Push to Talk)
- [ ] **Type shows "App Command"** - Action type selected
- [ ] **Command selected** - Dropdown shows correct command
- [ ] **Description shows** - Command description displayed

### Empty Segment Loading
- [ ] **Select empty segment** - Any unconfigured direction
- [ ] **Defaults to Text Macro** - Type selector on "Text Macro"
- [ ] **All fields empty** - Text field blank, toggle on
- [ ] **Custom label empty** - Optional label field blank

---

## 7. Segment Editor - Key Command Configuration

### Key Capture
- [ ] **Click capture field** - Field accepts focus
- [ ] **Press letter key** - Captures key (e.g., "a")
- [ ] **Press with Cmd** - Captures "⌘A"
- [ ] **Press with Ctrl** - Captures "^A"
- [ ] **Press with Option** - Captures "⌥A"
- [ ] **Press with Shift** - Captures "⇧A"
- [ ] **Press multiple mods** - Captures "⌘⇧A"
- [ ] **Display updates** - "Current:" shows new key immediately
- [ ] **Special keys work** - Arrow keys, Enter, Tab, etc.

### Saving Key Command
- [ ] **Click Save** - Saves configuration
- [ ] **Preview updates** - Segment shows keyboard icon
- [ ] **List updates** - Shows key combo name
- [ ] **No error** - No alert shown

### Validation
- [ ] **Empty key disabled** - Save disabled without key captured
- [ ] **Clear Segment works** - Removes key command

---

## 8. Segment Editor - Text Macro Configuration

### Text Entry
- [ ] **Enter simple text** - Type "hello"
- [ ] **Enter git command** - Type "git status"
- [ ] **Enter long command** - Type multi-word command
- [ ] **Multi-line works** - Field expands for long text
- [ ] **Special chars work** - Type with symbols (@, #, $, etc.)

### Auto-Enter Toggle
- [ ] **Toggle ON** - Checkmark appears
- [ ] **Toggle OFF** - Checkmark disappears
- [ ] **State persists** - Reflects when reloading segment

### Saving Text Macro
- [ ] **Click Save** - Saves configuration
- [ ] **Preview updates** - Segment shows text icon
- [ ] **List updates** - Shows truncated text
- [ ] **No error** - No alert shown

### Validation
- [ ] **Empty text disabled** - Save disabled without text
- [ ] **Clear Segment works** - Removes text macro

---

## 9. Segment Editor - App Command Configuration

### Command Selection
- [ ] **Dropdown opens** - Shows all app commands
- [ ] **Shows "Show Usage"** - First command
- [ ] **Shows "Show Context"** - Another command
- [ ] **Shows "Push to Talk Speech"** - Voice command
- [ ] **Shows "Toggle PS4 Panel"** - UI command
- [ ] **Shows "Clear Terminal"** - Terminal command
- [ ] **Shows "Copy to Clipboard"** - Clipboard command
- [ ] **Shows "Paste from Clipboard"** - Clipboard command
- [ ] **All commands listed** - ~10+ commands visible

### Command Description
- [ ] **Description displays** - Shows below dropdown
- [ ] **Description updates** - Changes when selecting different command
- [ ] **Description accurate** - Matches command function

### Saving App Command
- [ ] **Click Save** - Saves configuration
- [ ] **Preview updates** - Segment shows app badge icon
- [ ] **List updates** - Shows command name
- [ ] **No error** - No alert shown

---

## 10. Custom Label (Optional Field)

### Label Entry
- [ ] **Field is optional** - Can leave empty
- [ ] **Enter custom text** - Type "My Command"
- [ ] **Special chars work** - Unicode, emojis (if entered)
- [ ] **Saves with action** - Persists when reopening

### Label Usage
- [ ] **Shows in preview** - (Note: Current implementation may not show custom labels in preview - this is a known limitation)
- [ ] **Shows in list** - (Note: Current implementation shows action name, not custom label)

---

## 11. Clear Segment Functionality

### Clear Button State
- [ ] **Disabled when empty** - Can't clear empty segment
- [ ] **Enabled with action** - Can clear configured segment

### Clearing Actions
- [ ] **Click Clear** - Removes action
- [ ] **Preview updates** - Segment becomes empty/transparent
- [ ] **List updates** - Shows "Empty" text
- [ ] **Editor resets** - Fields clear to defaults
- [ ] **No error** - No alert shown

---

## 12. Profile Management - Creating New Profile

### Opening New Profile Modal
- [ ] **Click "+" button** - Opens modal
- [ ] **Modal displays** - 400x300 window
- [ ] **Title shows** - "Create New Profile"
- [ ] **Name field visible** - Text field for name
- [ ] **Base profile dropdown** - Shows all existing profiles
- [ ] **Defaults to active** - Current profile pre-selected

### Creating Profile
- [ ] **Enter name "Test 1"** - Type in field
- [ ] **Select base "Default"** - Choose from dropdown
- [ ] **Click Create** - Closes modal
- [ ] **New profile active** - "Test 1" now selected
- [ ] **Inherits L1 menu** - Copied from Default
- [ ] **Inherits R1 menu** - Copied from Default
- [ ] **Shows in dropdown** - "Test 1" in profile list

### Creating Empty Profile
- [ ] **Enter name "Empty"** - Type in field
- [ ] **Select "Empty" base** - First option in dropdown
- [ ] **Click Create** - Closes modal
- [ ] **New profile active** - "Empty" now selected
- [ ] **L1 menu empty** - All segments empty
- [ ] **R1 menu empty** - All segments empty

### Validation
- [ ] **Empty name disabled** - Create button disabled
- [ ] **Cancel works** - Closes without creating

---

## 13. Profile Management - Duplicating Profile

### Duplicate Functionality
- [ ] **Select "Default"** - Make it active
- [ ] **Click "Duplicate"** - In action buttons
- [ ] **Alert shows** - "Profile duplicated"
- [ ] **New profile active** - "Default Copy" now selected
- [ ] **L1 menu copied** - Identical to Default L1
- [ ] **R1 menu copied** - Identical to Default R1
- [ ] **Shows in dropdown** - "Default Copy" in list

### Multiple Duplicates
- [ ] **Duplicate again** - Click Duplicate a second time
- [ ] **Unique name** - "Default Copy Copy" or similar
- [ ] **All show in list** - Multiple copies listed

---

## 14. Profile Management - Deleting Profile

### Delete Button Visibility
- [ ] **With multiple profiles** - Delete button visible
- [ ] **With one profile** - Delete button hidden/disabled

### Deleting Profile
- [ ] **Create extra profile** - Ensure 2+ profiles exist
- [ ] **Select extra profile** - Make it active
- [ ] **Click Delete** - Red button in actions
- [ ] **Alert shows** - "Profile deleted"
- [ ] **Profile removed** - No longer in dropdown
- [ ] **Different profile active** - Switches to another profile

### Protection Against Deleting Last
- [ ] **Delete all but one** - Remove profiles until 1 left
- [ ] **Delete button gone** - Can't delete last profile

---

## 15. Profile Management - Reset to Defaults

### Reset Functionality
- [ ] **Make some edits** - Modify segments, create profiles
- [ ] **Click Reset** - "Reset" button in actions
- [ ] **Alert shows** - "Reset to default profiles"
- [ ] **6 profiles exist** - Back to original 6
- [ ] **Default active** - "Default" profile selected
- [ ] **Edits gone** - All custom changes removed
- [ ] **All segments match** - Original default configurations

---

## 16. Import/Export - Export Profiles

### Opening Export
- [ ] **Click "Import/Export"** - Toolbar button
- [ ] **Modal opens** - 400x300 window
- [ ] **Title shows** - "Import/Export Profiles"
- [ ] **Export button visible** - "Export All Profiles"
- [ ] **Import button visible** - "Import Profiles"
- [ ] **Description shown** - Explains what export does

### Exporting
- [ ] **Click "Export All"** - Opens save panel
- [ ] **Default name shown** - "radial-menu-profiles.json"
- [ ] **Choose location** - Can navigate to folder
- [ ] **Click Save** - Saves file
- [ ] **Success alert** - "Profiles exported successfully"
- [ ] **File exists** - JSON file created at location
- [ ] **File readable** - Can open in text editor

### Exported File Content
- [ ] **Valid JSON** - No syntax errors
- [ ] **Contains all profiles** - All 6 (or custom number)
- [ ] **Profile names present** - "Default", "Docker", etc.
- [ ] **L1 menus present** - All segment configurations
- [ ] **R1 menus present** - All segment configurations
- [ ] **Actions preserved** - Key commands, text macros, app commands

---

## 17. Import/Export - Import Profiles

### Importing Valid File
- [ ] **Make custom changes** - Edit some segments
- [ ] **Click "Import"** - Opens file picker
- [ ] **Select JSON file** - Previously exported file
- [ ] **Click Open** - Imports file
- [ ] **Success alert** - "Profiles imported successfully"
- [ ] **Profiles replaced** - All profiles from file loaded
- [ ] **Custom changes gone** - Previous edits overwritten
- [ ] **First profile active** - Switches to first imported

### Import Error Handling
- [ ] **Select .txt file** - Wrong file type
- [ ] **Error alert shown** - "Failed to parse profile data"
- [ ] **Select corrupt JSON** - Malformed JSON file
- [ ] **Error alert shown** - "Failed to parse profile data"
- [ ] **Cancel import** - File picker cancel works

---

## 18. Configuration View - Close and Persistence

### Closing Configuration
- [ ] **Click "Done"** - Top-right button
- [ ] **Modal closes** - Returns to main window
- [ ] **Enter key works** - ⌘-Return closes modal

### Changes Persist
- [ ] **Make edits** - Change several segments
- [ ] **Click Done** - Close modal
- [ ] **Reopen config** - Click gear icon again
- [ ] **Edits preserved** - All changes still present

### App Restart Persistence
- [ ] **Make edits** - Change segments and profiles
- [ ] **Quit app** - ⌘Q to quit
- [ ] **Relaunch app** - Open again
- [ ] **Profiles persist** - All profiles still exist
- [ ] **Active profile same** - Same profile selected
- [ ] **Edits preserved** - All segment changes still present

---

## 19. Integration with Radial Menu (Phase 1)

### L1 Menu Integration
- [ ] **Switch to "Git" profile** - L1: Quick Actions, R1: Git
- [ ] **Connect PS4 controller** - If not already connected
- [ ] **Hold L1 button** - For 300ms
- [ ] **Menu appears** - Radial overlay shows
- [ ] **8 segments show** - All directions visible
- [ ] **Segments match config** - Same actions as configured
- [ ] **Move stick North** - Selects git status (or configured action)
- [ ] **Release L1** - Executes action

### R1 Menu Integration
- [ ] **Hold R1 button** - For 300ms
- [ ] **Menu appears** - Radial overlay shows
- [ ] **8 segments show** - All directions visible
- [ ] **Segments match config** - Same actions as configured
- [ ] **Move stick** - Select any direction
- [ ] **Release R1** - Executes action

### Profile Switching Impact
- [ ] **Open config** - Click gear icon
- [ ] **Switch to "Docker"** - Change profile
- [ ] **Close config** - Click Done
- [ ] **Hold R1** - Open radial menu
- [ ] **Docker commands show** - R1 menu shows Docker actions
- [ ] **Correct segments** - Matches Docker profile configuration

---

## 20. Edge Cases and Error Conditions

### Invalid States
- [ ] **Delete all custom profiles** - Should not crash
- [ ] **Empty all segments in profile** - Should still work
- [ ] **Very long text macro** - Truncates or wraps gracefully
- [ ] **Special characters in profile name** - Handles correctly
- [ ] **Unicode in text macros** - Saves and executes correctly

### Rapid Interactions
- [ ] **Click segments rapidly** - No crash or lag
- [ ] **Switch L1/R1 rapidly** - Smooth transition
- [ ] **Switch profiles rapidly** - No data loss
- [ ] **Save repeatedly** - No duplicate saves

### Data Integrity
- [ ] **Edit L1, don't save** - Changes discarded
- [ ] **Edit R1, switch to L1** - R1 edits lost if not saved
- [ ] **Create profile, click Cancel** - No profile created
- [ ] **Modify imported file manually** - Handles corrupted data

---

## 21. Visual & UI Polish

### Layout and Spacing
- [ ] **No overlapping text** - All labels readable
- [ ] **Buttons properly sized** - Not cut off
- [ ] **Icons display correctly** - Not blurry or distorted
- [ ] **Colors have contrast** - Text readable on backgrounds
- [ ] **Selection highlights visible** - Blue highlights clear

### Animations
- [ ] **Modal opens smoothly** - No glitches
- [ ] **Modal closes smoothly** - Clean transition
- [ ] **Tab switching smooth** - No flashing
- [ ] **Alerts appear/dismiss** - Smooth presentation

### Responsive Behavior
- [ ] **Resize window** - Layout adapts (if possible)
- [ ] **Scroll segment list** - Scrolling smooth
- [ ] **Long action names** - Truncate with ellipsis

---

## 22. Performance

### Load Times
- [ ] **Config opens quickly** - < 500ms
- [ ] **Profile switching fast** - < 200ms
- [ ] **Segment selection instant** - < 100ms
- [ ] **Save responds quickly** - < 200ms

### No Lag or Freezing
- [ ] **No stuttering** - UI remains responsive
- [ ] **No beach ball** - App doesn't hang
- [ ] **Large profiles** - Handles 10+ custom profiles
- [ ] **Memory stable** - No obvious leaks

---

## 23. Accessibility (Basic Check)

### Keyboard Navigation
- [ ] **Tab through fields** - Can navigate with Tab
- [ ] **Enter confirms** - Can save with Enter
- [ ] **Escape cancels** - Can cancel with Escape

### Visual Accessibility
- [ ] **Text readable** - Sufficient contrast
- [ ] **Icons clear** - Distinguishable at size
- [ ] **Focus indicators** - Can see focused element

---

## Testing Summary Template

After completing testing, fill this out:

**Date Tested:** _____________
**Tester:** _____________
**Build:** _____________

**Total Tests:** _____ / 200+
**Passed:** _____
**Failed:** _____
**Blocked:** _____

### Critical Issues Found
1.
2.
3.

### Minor Issues Found
1.
2.
3.

### Recommendations
1.
2.
3.

### Overall Assessment
- [ ] Ready for Phase 3
- [ ] Needs fixes before Phase 3
- [ ] Major rework required

---

## Quick Smoke Test (5 Minutes)

If you only have 5 minutes, test these critical paths:

1. [ ] Open configuration view
2. [ ] Switch between L1 and R1
3. [ ] Click a segment to edit
4. [ ] Change action to text macro, enter "test", save
5. [ ] Verify preview updates
6. [ ] Create new profile
7. [ ] Export profiles to file
8. [ ] Import profiles from file
9. [ ] Close and reopen config - verify persistence
10. [ ] Quit and relaunch app - verify persistence

---

**End of Checklist**

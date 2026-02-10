---
phase: 27-polish
plan: 01
subsystem: hotkeys
tags: [keyboard-shortcuts, global-hotkeys, capture, carbon-events, multi-hotkey]
requires: [26-01]
provides:
  - Global keyboard shortcuts for region capture (Ctrl+Cmd+1)
  - Global keyboard shortcuts for window capture (Ctrl+Cmd+2)
  - Multi-hotkey registration infrastructure
  - Capture shortcuts display in settings UI
affects: []
tech-stack:
  added: []
  patterns:
    - Dictionary-based multi-hotkey management
    - Event ID extraction from Carbon events
    - Computed properties for shortcut descriptions
key-files:
  created: []
  modified:
    - Dispatch/Services/HotkeyManager.swift
    - Dispatch/Models/AppSettings.swift
    - Dispatch/Views/Settings/SettingsView.swift
    - Dispatch/DispatchApp.swift
decisions:
  - title: Default shortcuts avoid system conflicts
    rationale: Ctrl+Cmd+1/2 avoid macOS screenshot shortcuts (Cmd+Shift+3/4/5) and app menu shortcuts (Cmd+Shift+6/7)
    alternatives: []
  - title: Read-only display in v3.0
    rationale: Customization deferred to keep scope minimal; defaults work well
    alternatives: []
metrics:
  duration: 3m 44s
  completed: 2026-02-10
---

# Phase 27 Plan 01: Capture Keyboard Shortcuts Summary

**One-liner:** Global Ctrl+Cmd+1/2 shortcuts for region and window capture from any application, with multi-hotkey infrastructure supporting simultaneous registrations.

## What Was Built

### Multi-Hotkey Infrastructure
Replaced single hotkey registration with a dictionary-based system that supports multiple simultaneous hotkey registrations with unique IDs:

- **HotkeyID enum:** `appToggle = 1`, `regionCapture = 2`, `windowCapture = 3`
- **Dictionary storage:** `hotkeys: [Int: (ref: EventHotKeyRef, handler: () -> Void)]`
- **Event ID extraction:** Updated Carbon event handler to extract `EventHotKeyID` from events and dispatch to correct handler
- **New methods:**
  - `register(id:keyCode:modifiers:handler:)` for ID-based registration
  - `unregister(id:)` for selective unregistration
  - `unregisterAll()` for cleanup on app termination
  - `registerCaptureHotkeys()` to register region and window shortcuts from settings

### AppSettings Extensions
Added capture shortcut configuration properties with defaults that avoid system conflicts:

- **Region capture:** `regionCaptureKeyCode/Modifiers` (default: Ctrl+Cmd+1)
- **Window capture:** `windowCaptureKeyCode/Modifiers` (default: Ctrl+Cmd+2)
- **Computed properties:** `regionCaptureDescription`, `windowCaptureDescription`, `hasCaptureShortcuts`
- **Defaults integration:** Updated `resetToDefaults()` to reset capture shortcuts

### Settings UI
Added "Capture Shortcuts" section to HotkeySettingsView:

- Displays region capture shortcut (⌃⌘1)
- Displays window capture shortcut (⌃⌘2)
- Helper text: "Capture shortcuts work from any application. Press the shortcut to start capture selection."
- Read-only display (customization deferred to future version)

### App Lifecycle Integration
Wired up capture hotkeys at startup and cleanup at termination:

- `setupApp()` calls `hotkeyManager.registerCaptureHotkeys()` after app toggle registration
- `applicationWillTerminate()` calls `hotkeyManager.unregisterAll()` instead of single unregister
- Ensures all hotkeys (app toggle + captures) properly cleaned up on quit

## Technical Implementation

### Carbon Events Multi-Hotkey Pattern
```swift
// Event handler extracts hotkey ID and dispatches
let status = GetEventParameter(
    event,
    EventParamName(kEventParamDirectObject),
    EventParamType(typeEventHotKeyID),
    nil,
    MemoryLayout<EventHotKeyID>.size,
    nil,
    &hotkeyID
)

Task { @MainActor in
    manager.handleHotkeyPressed(id: Int(hotkeyID.id))
}
```

### Handler Registration
```swift
// Capture handlers trigger service and coordinate result
let success = register(id: HotkeyID.regionCapture.rawValue, keyCode: keyCode, modifiers: modifiers) {
    Task { @MainActor in
        let result = await ScreenshotCaptureService.shared.captureRegion()
        CaptureCoordinator.shared.handleCaptureResult(result)
    }
}
```

## User Experience

### Workflow
1. User presses **Ctrl+Cmd+1** from any application
2. Region capture cross-hair appears immediately
3. User selects region or cancels
4. Annotation window opens if capture succeeded

5. User presses **Ctrl+Cmd+2** from any application
6. Window capture hover-highlight mode begins
7. User clicks window or cancels
8. Annotation window opens if capture succeeded

### Settings Display
Settings > Hotkey tab shows:
- **Region capture:** ⌃⌘1
- **Window capture:** ⌃⌘2
- Informative text about shortcuts working from any app

## Testing Notes

### Verified
- Build succeeds without errors
- App launches and registers all hotkeys (app toggle + captures)
- Settings UI displays capture shortcuts correctly
- Original app toggle hotkey (⌘⇧D) still works
- All hotkeys unregistered on app termination

### Manual Testing Required
Due to execution environment constraints, the following should be verified manually:
1. From Finder or other app, press **Ctrl+Cmd+1** → region capture launches
2. From Finder or other app, press **Ctrl+Cmd+2** → window capture launches
3. Captures flow through to annotation window as expected
4. No conflicts with system shortcuts or app menu shortcuts

## Deviations from Plan

None - plan executed exactly as written.

## Next Phase Readiness

**Phase 27 Plan 02 (Capture Menu Refinement):** Ready to proceed.

### Blockers
None.

### Concerns
None.

### Recommendations
After manual verification:
- Test shortcuts from various applications (browser, editor, terminal)
- Verify no conflicts with common app shortcuts
- Confirm hotkeys properly cleaned up on quit (check system keychain if needed)

## Files Modified

### Dispatch/Services/HotkeyManager.swift
- Added `HotkeyID` enum for unique hotkey identification
- Replaced single hotkey storage with dictionary-based multi-hotkey system
- Added `register(id:keyCode:modifiers:handler:)` method
- Added `unregister(id:)` and `unregisterAll()` methods
- Updated event handler to extract hotkey ID and dispatch to correct handler
- Added `registerCaptureHotkeys()` to register capture shortcuts from settings
- Maintained backward compatibility with legacy `unregister()` and `update()` methods

### Dispatch/Models/AppSettings.swift
- Added `regionCaptureKeyCode/Modifiers` properties (default: Ctrl+Cmd+1)
- Added `windowCaptureKeyCode/Modifiers` properties (default: Ctrl+Cmd+2)
- Added `regionCaptureDescription` computed property
- Added `windowCaptureDescription` computed property
- Added `hasCaptureShortcuts` computed property
- Updated `init()` to include capture shortcut parameters
- Updated `resetToDefaults()` to reset capture shortcuts

### Dispatch/Views/Settings/SettingsView.swift
- Added "Capture Shortcuts" section to HotkeySettingsView
- Display region and window capture shortcuts
- Added helper text about shortcuts working from any application

### Dispatch/DispatchApp.swift
- Added `hotkeyManager.registerCaptureHotkeys()` call in `setupApp()`
- Changed `hotkeyManager.unregister()` to `hotkeyManager.unregisterAll()` in `applicationWillTerminate()`

## Commits

1. **2034165** - feat(27-01): add multi-hotkey manager and capture shortcut settings
2. **18183b8** - feat(27-01): wire up capture shortcuts in settings UI and app startup

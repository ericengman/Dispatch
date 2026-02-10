# Phase 27: Polish (Keyboard Shortcuts) - Research

**Researched:** 2026-02-09
**Domain:** macOS global keyboard shortcuts for screenshot capture
**Confidence:** HIGH

## Summary

This phase adds global keyboard shortcuts for triggering region and window capture modes. The app already uses Carbon Event Manager APIs via a custom HotkeyManager for the main app toggle (⌘⇧D). The same Carbon-based approach will work for capture shortcuts, but we should also evaluate the modern KeyboardShortcuts library which offers better SwiftUI integration, automatic conflict detection, and UserDefaults persistence.

**Key findings:**
- Carbon's RegisterEventHotKey remains the standard API for global shortcuts (not deprecated for this use case)
- HotkeyManager already implements the pattern; can register multiple shortcuts with unique EventHotKeyIDs
- KeyboardShortcuts library (by Sindre Sorhus) provides modern SwiftUI recorder UI and automatic conflict detection
- Safe default shortcuts: Ctrl+Cmd+A for region, Ctrl+Cmd+W for window (avoid conflicts with system screenshot shortcuts)

**Primary recommendation:** Extend existing HotkeyManager to support multiple hotkey registrations with distinct handlers. Add settings UI for customization. Consider KeyboardShortcuts library for settings UI recorder component only.

## Standard Stack

The established libraries/tools for global keyboard shortcuts on macOS:

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Carbon Event Manager | System | RegisterEventHotKey API for global shortcuts | Only API for sandboxed global hotkeys; used by all screenshot apps |
| AppSettings (SwiftData) | Current | Store keyCode/modifiers for shortcuts | Already in use for main hotkey settings |
| UserDefaults | System | Alternative lightweight storage | Suitable for simple key-value persistence |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| KeyboardShortcuts | 2.x | SwiftUI recorder + conflict detection | If building custom settings UI from scratch |
| HotKey | 0.2.0 | Swift wrapper for Carbon hotkeys | Alternative to custom HotkeyManager (already have one) |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Carbon RegisterEventHotKey | CGEventTap | More powerful but requires accessibility permissions; overkill for simple hotkeys |
| Custom HotkeyManager | KeyboardShortcuts library | Library handles conflicts/UI but adds dependency; current manager works fine |
| AppSettings storage | UserDefaults directly | Simpler for hotkeys-only, but inconsistent with existing settings pattern |

**Installation:**
```bash
# If using KeyboardShortcuts library (optional)
# Add via Xcode SPM: https://github.com/sindresorhus/KeyboardShortcuts
```

## Architecture Patterns

### Current HotkeyManager Pattern
The app already has a working HotkeyManager singleton that:
- Registers one hotkey at a time with Carbon's RegisterEventHotKey
- Uses EventHotKeyID with signature "DISP" and id: 1
- Stores handler closure and current keyCode/modifiers
- Provides conflict detection for common system shortcuts

**To support multiple hotkeys:**
- Change EventHotKeyID to use unique IDs (1 = main app, 2 = region capture, 3 = window capture)
- Store array of (hotkeyRef, handler) tuples instead of single values
- Register/unregister specific hotkeys by ID

### Recommended Settings Storage
```swift
// In AppSettings.swift (existing model)
// Add new properties:

/// Key code for region capture hotkey (Carbon key codes)
var regionCaptureKeyCode: Int?

/// Modifier flags for region capture hotkey
var regionCaptureModifiers: Int?

/// Key code for window capture hotkey
var windowCaptureKeyCode: Int?

/// Modifier flags for window capture hotkey
var windowCaptureModifiers: Int?
```

### Pattern 1: Multi-Hotkey Manager
**What:** Extend HotkeyManager to support multiple simultaneous hotkey registrations
**When to use:** When app needs more than one global shortcut
**Example:**
```swift
// Source: Existing HotkeyManager.swift pattern
@MainActor
final class HotkeyManager: ObservableObject {
    // Change from single hotkey to dictionary
    private var hotkeys: [Int: (ref: EventHotKeyRef, handler: () -> Void)] = [:]

    func register(id: Int, keyCode: Int, modifiers: Int, handler: @escaping () -> Void) -> Bool {
        // Use EventHotKeyID with custom id
        let hotkeyId = EventHotKeyID(signature: OSType(0x44495350), id: UInt32(id))

        // Register and store in dictionary
        var hotkeyRef: EventHotKeyRef?
        let result = RegisterEventHotKey(
            UInt32(keyCode),
            convertModifiers(modifiers),
            hotkeyId,
            GetApplicationEventTarget(),
            0,
            &hotkeyRef
        )

        guard result == noErr, let ref = hotkeyRef else { return false }
        hotkeys[id] = (ref, handler)
        return true
    }

    func unregister(id: Int) {
        guard let (ref, _) = hotkeys[id] else { return }
        UnregisterEventHotKey(ref)
        hotkeys.removeValue(forKey: id)
    }
}
```

### Pattern 2: Settings UI for Capture Shortcuts
**What:** Add capture shortcuts section to existing SettingsView
**When to use:** Users need to customize shortcuts or see current bindings
**Example:**
```swift
// In SettingsView.swift - new section in HotkeySettingsView
Section("Capture Shortcuts") {
    // Region capture
    HStack {
        Text("Region capture:")
        Spacer()
        Text(regionCaptureDescription)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
    }

    // Window capture
    HStack {
        Text("Window capture:")
        Spacer()
        Text(windowCaptureDescription)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
    }

    Button("Reset to Defaults") {
        resetCaptureShortcuts()
    }
}
```

### Anti-Patterns to Avoid
- **Don't conflict with system shortcuts:** ⌘⇧4, ⌘⇧5 are macOS screenshot shortcuts - avoid these
- **Don't use single modifiers:** RegisterEventHotKey with only Option or Option+Shift fails on macOS 15
- **Don't forget accessibility permissions:** If users can't trigger shortcuts, guide them to System Settings > Privacy > Accessibility
- **Don't block main thread:** Capture operations are async - handlers should use Task { @MainActor in ... }

## Don't Hand-Roll

Problems that look simple but have existing solutions:

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Keyboard shortcut recorder UI | Custom key event listener | KeyboardShortcuts.Recorder | Handles edge cases (Fn keys, media keys, conflicts) |
| Shortcut conflict detection | Manual system shortcut list | KeyboardShortcuts or HotkeyManager.checkForConflicts | System shortcuts change between macOS versions |
| Carbon modifier conversion | Bit manipulation from scratch | Existing HotkeyManager pattern | Carbon uses different constants than NSEvent |
| Shortcut display formatting | String concatenation | HotkeyManager.hotkeyDescription | Proper symbol order (⌃⌥⇧⌘) |

**Key insight:** Global keyboard shortcuts require Carbon APIs on macOS. Don't try to use NSEvent local monitors or SwiftUI keyboardShortcut modifiers - those only work within the app window.

## Common Pitfalls

### Pitfall 1: Conflicting with System Screenshot Shortcuts
**What goes wrong:** Users' global shortcuts don't work because system shortcuts take priority
**Why it happens:** macOS reserves ⌘⇧3, ⌘⇧4, ⌘⇧5, ⌘⇧6 for screenshots
**How to avoid:**
- Use different modifier combinations (add Ctrl, or use different keys)
- Recommended: Ctrl+Cmd+A (region), Ctrl+Cmd+W (window)
- Document conflicts in settings UI
**Warning signs:** Shortcut registers successfully but never fires

### Pitfall 2: Single EventHotKeyID for Multiple Shortcuts
**What goes wrong:** Only one shortcut works; registering second overwrites first
**Why it happens:** EventHotKeyID must be unique per registered hotkey
**How to avoid:** Use unique ID values in EventHotKeyID (e.g., 1 for main, 2 for region, 3 for window)
**Warning signs:** Last registered shortcut works, earlier ones stop responding

### Pitfall 3: Handler Not Called on Main Actor
**What goes wrong:** UI updates from hotkey handler cause crashes or warnings
**Why it happens:** Carbon event handler runs on background thread
**How to avoid:** Wrap handler body in `Task { @MainActor in ... }`
**Warning signs:** "Publishing changes from background threads is not allowed" runtime warnings

### Pitfall 4: Memory Leaks with Event Handlers
**What goes wrong:** Hotkeys stop working after app lifecycle events
**Why it happens:** EventHandlerRef not properly cleaned up in deinit
**How to avoid:**
- Current HotkeyManager handles this correctly (singleton pattern)
- Ensure unregister() is called in applicationWillTerminate
**Warning signs:** Shortcuts work initially but fail after sleep/wake

### Pitfall 5: Missing Accessibility Permissions
**What goes wrong:** RegisterEventHotKey succeeds but shortcuts never trigger
**Why it happens:** macOS requires accessibility permission for some global shortcuts (especially with media keys)
**How to avoid:**
- Check AXIsProcessTrusted() before registering
- Show alert directing to System Settings if denied
- Most keyboard shortcuts don't need this, but good to handle
**Warning signs:** Registration returns noErr but handlers never called

## Code Examples

Verified patterns from existing codebase and Carbon API documentation:

### Registering Multiple Hotkeys
```swift
// Source: Adapted from existing HotkeyManager.swift
enum HotkeyID: Int {
    case mainAppToggle = 1
    case regionCapture = 2
    case windowCapture = 3
}

// In app startup (DispatchApp.swift)
func registerCaptureHotkeys() {
    guard let settings = SettingsManager.shared.settings else { return }

    // Register region capture shortcut
    if let keyCode = settings.regionCaptureKeyCode,
       let modifiers = settings.regionCaptureModifiers {
        _ = HotkeyManager.shared.register(
            id: HotkeyID.regionCapture.rawValue,
            keyCode: keyCode,
            modifiers: modifiers
        ) {
            Task { @MainActor in
                await ScreenshotCaptureService.shared.captureRegion()
            }
        }
    }

    // Register window capture shortcut
    if let keyCode = settings.windowCaptureKeyCode,
       let modifiers = settings.windowCaptureModifiers {
        _ = HotkeyManager.shared.register(
            id: HotkeyID.windowCapture.rawValue,
            keyCode: keyCode,
            modifiers: modifiers
        ) {
            Task { @MainActor in
                await ScreenshotCaptureService.shared.captureWindow()
            }
        }
    }
}
```

### Default Capture Shortcut Values
```swift
// Source: Pattern from AppSettingsDefaults
enum AppSettingsDefaults {
    // Existing defaults...

    // Region capture: Ctrl+Cmd+A
    static let regionCaptureKeyCode: Int = .init(kVK_ANSI_A)
    static let regionCaptureModifiers: Int = .init(cmdKey | controlKey)

    // Window capture: Ctrl+Cmd+W
    static let windowCaptureKeyCode: Int = .init(kVK_ANSI_W)
    static let windowCaptureModifiers: Int = .init(cmdKey | controlKey)
}
```

### Integration with Existing Capture Flow
```swift
// Source: Existing QuickCaptureSidebarSection.swift pattern
// Hotkey handler calls same service methods as UI buttons

// Current UI button handler:
private func triggerRegionCapture() {
    Task {
        let result = await ScreenshotCaptureService.shared.captureRegion()
        handleCaptureResult(result)
    }
}

// Hotkey handler should use same flow:
HotkeyManager.shared.register(id: 2, ...) {
    Task { @MainActor in
        let result = await ScreenshotCaptureService.shared.captureRegion()
        CaptureCoordinator.shared.handleCaptureResult(result)
    }
}
```

### Settings UI Bindings
```swift
// Source: Pattern from existing HotkeySettingsView
private var regionCaptureDescription: String {
    guard let keyCode = settingsManager.settings?.regionCaptureKeyCode,
          let modifiers = settingsManager.settings?.regionCaptureModifiers else {
        return "Not Set"
    }
    return HotkeyManager.hotkeyDescription(keyCode: keyCode, modifiers: modifiers)
}

private func resetCaptureShortcuts() {
    settingsManager.settings?.regionCaptureKeyCode = AppSettingsDefaults.regionCaptureKeyCode
    settingsManager.settings?.regionCaptureModifiers = AppSettingsDefaults.regionCaptureModifiers
    settingsManager.settings?.windowCaptureKeyCode = AppSettingsDefaults.windowCaptureKeyCode
    settingsManager.settings?.windowCaptureModifiers = AppSettingsDefaults.windowCaptureModifiers
    settingsManager.save()

    // Re-register hotkeys with new values
    registerCaptureHotkeys()
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| NSEvent local monitors | Carbon RegisterEventHotKey | Since macOS 10.0 | NSEvent can't monitor global events outside app |
| Single global hotkey | Multiple hotkeys per app | Always available | Apps can offer shortcuts for multiple actions |
| Hardcoded shortcuts | User-customizable in settings | Industry standard | Users can avoid conflicts with their other apps |
| Manual UI for shortcut input | KeyboardShortcuts.Recorder | ~2020 (library) | Better UX with automatic validation |

**Deprecated/outdated:**
- NSEvent.addGlobalMonitorForEvents: Removed in macOS 10.15; required accessibility permissions and was security risk
- CGEventTapCreate without accessibility: No longer works for keyboard events since macOS 10.14
- Option-only modifiers: Broken on macOS 15 (FB15168205); must combine with Cmd/Ctrl/Shift

## Open Questions

Things that couldn't be fully resolved:

1. **Should we add a recorder UI for customization?**
   - What we know: KeyboardShortcuts library provides excellent recorder component
   - What's unclear: Whether users will want to customize capture shortcuts or just use defaults
   - Recommendation: Start with fixed defaults in settings (displayed but not editable). Can add recorder in future phase if users request it

2. **Do we need accessibility permissions?**
   - What we know: Basic RegisterEventHotKey works without accessibility for standard keys
   - What's unclear: Whether Ctrl+Cmd combinations require accessibility on all macOS versions
   - Recommendation: Test on macOS 14/15 to verify. If needed, add permission check and settings guidance

3. **Should shortcuts work when app is not active?**
   - What we know: Global hotkeys work regardless of active app
   - What's unclear: Whether capture UI (screencapture -i, WindowCaptureSession) behaves correctly when invoked from background
   - Recommendation: Test thoroughly. May need to activate app before showing capture UI for proper window layering

## Sources

### Primary (HIGH confidence)
- [Existing HotkeyManager.swift implementation](file:///Users/eric/Dispatch/Dispatch/Services/HotkeyManager.swift) - Current working pattern
- [Existing AppSettings.swift model](file:///Users/eric/Dispatch/Dispatch/Models/AppSettings.swift) - Settings storage pattern
- [Building a Better RegisterEventHotKey (Medium)](https://medium.com/@avaidyam/building-a-better-registereventhotkey-900afd68f11f) - Carbon API deep dive
- [Apple Developer: Handling Key Events](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/EventOverview/HandlingKeyEvents/HandlingKeyEvents.html) - Official documentation

### Secondary (MEDIUM confidence)
- [KeyboardShortcuts library GitHub](https://github.com/sindresorhus/KeyboardShortcuts) - Modern Swift library for shortcuts
- [HotKey library GitHub](https://github.com/soffes/HotKey) - Alternative Swift wrapper
- [macOS 15 Option-only hotkey bug (FB15168205)](https://github.com/feedback-assistant/reports/issues/552) - Known macOS 15 issue
- [Mac Screenshot Shortcuts Guide 2026](https://www.screensnap.pro/blog/mac-screenshot-shortcuts) - System shortcuts reference
- [CleanShot X shortcuts](https://www.pie-menu.com/shortcuts/cleanshot) - Example third-party screenshot app defaults

### Tertiary (LOW confidence)
- Various web searches for safe keyboard combinations - no definitive source for "available" shortcuts
- Community discussions about Carbon deprecation - officially not deprecated for hotkeys

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - Carbon RegisterEventHotKey is the only option; existing HotkeyManager proves it works
- Architecture: HIGH - Existing implementation provides tested pattern; extension is straightforward
- Pitfalls: HIGH - Most derived from existing code review and documented macOS issues
- Default shortcuts: MEDIUM - Ctrl+Cmd+A/W appear safe but should verify with testing
- Accessibility permissions: LOW - Conflicting information about when required; needs testing

**Research date:** 2026-02-09
**Valid until:** 2026-03-09 (30 days - stable APIs, but macOS updates may affect behavior)

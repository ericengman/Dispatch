# Stack Research: Screenshot Capture APIs

**Project:** Dispatch v3.0 Quick Screenshot Capture
**Researched:** 2026-02-09
**Target:** macOS 14+ (Sonoma)
**Confidence:** HIGH

## Executive Summary

macOS provides two primary paths for screenshot capture:

1. **ScreenCaptureKit** (macOS 12.3+) - Modern, performant framework with picker UI and screenshot APIs
2. **screencapture CLI** - System command with `-i` for interactive mode (cross-hair selection)

For Dispatch's use case, a hybrid approach is recommended: invoke `screencapture -i` for native region selection UX, and use ScreenCaptureKit for window capture with picker UI.

---

## Recommended Stack

### Core Screenshot APIs

| API | Use Case | macOS Version | Why |
|-----|----------|---------------|-----|
| `screencapture -i` | Cross-hair region selection | All | Native macOS UX, zero implementation overhead, users already know the interaction |
| `SCContentSharingPicker` | Window/app picker UI | 14.0+ | System-provided picker, no Screen Recording permission needed, professional UX |
| `SCScreenshotManager` | Capture selected window | 14.0+ | Modern replacement for deprecated CGWindowListCreateImage |

**Confidence: HIGH** - Verified via Apple WWDC23 documentation and developer forums.

---

### Region Selection: `screencapture` Command

For cross-hair region selection, invoke the native screencapture command.

**Command syntax:**
```bash
screencapture -i -x /path/to/output.png
```

| Flag | Purpose |
|------|---------|
| `-i` | Interactive mode (cross-hair selection) |
| `-x` | No sound |
| `-o` | No window shadow (for window mode) |
| `-U` | Show interactive toolbar |
| `-R x,y,w,h` | Capture specific rectangle (skip interaction) |
| `-w` | Window selection mode only |
| `-s` | Selection mode only |

**Why this approach:**
- Native macOS selection UX that users already know
- No need to implement custom overlay windows
- Handles multi-monitor correctly
- Respects system preferences (e.g., screenshot location)
- Works without Screen Recording permission (user-initiated)

**Integration pattern:**
```swift
import Foundation

func captureRegion(to path: URL) async throws -> Bool {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    process.arguments = ["-i", "-x", path.path]

    try process.run()
    process.waitUntilExit()

    return process.terminationStatus == 0 && FileManager.default.fileExists(atPath: path.path)
}
```

**User interaction notes:**
- Space bar toggles between selection and window mode
- Escape cancels
- Holding Shift locks aspect ratio
- Holding Option expands from center

**Confidence: HIGH** - Verified via ss64 man page documentation.

---

### Window Capture: ScreenCaptureKit

For window capture with app/window picker, use `SCContentSharingPicker` (macOS 14+).

**Key advantage:** `SCContentSharingPicker` does NOT require Screen Recording permission because it's user-initiated via system UI.

**Implementation pattern:**
```swift
import ScreenCaptureKit

@MainActor
class WindowCaptureController: NSObject, SCContentSharingPickerObserver {

    private var completionHandler: ((CGImage?) -> Void)?

    func captureWindow(completion: @escaping (CGImage?) -> Void) {
        self.completionHandler = completion

        let picker = SCContentSharingPicker.shared

        // Configure picker
        var config = SCContentSharingPickerConfiguration()
        config.allowedPickingModes = [.singleWindow]
        // Optionally: .singleApplication, .multipleWindows
        picker.configuration = config

        // Add self as observer
        picker.add(self)

        // Present picker (system UI appears)
        picker.present()
    }

    // MARK: - SCContentSharingPickerObserver

    func contentSharingPicker(_ picker: SCContentSharingPicker,
                              didUpdateWith filter: SCContentFilter,
                              for stream: SCStream?) {
        Task {
            do {
                let config = SCStreamConfiguration()
                // Use actual window dimensions or set specific size
                config.capturesAudio = false

                let image = try await SCScreenshotManager.captureImage(
                    contentFilter: filter,
                    configuration: config
                )

                await MainActor.run {
                    completionHandler?(image)
                    completionHandler = nil
                }
            } catch {
                await MainActor.run {
                    completionHandler?(nil)
                    completionHandler = nil
                }
            }
        }
    }

    func contentSharingPickerDidCancel(_ picker: SCContentSharingPicker) {
        completionHandler?(nil)
        completionHandler = nil
    }
}
```

**Picker configuration options:**
- `allowedPickingModes`: `.singleWindow`, `.singleApplication`, `.multipleWindows`, `.multipleApplications`
- `excludedBundleIDs`: Array of bundle IDs to exclude from picker
- `excludedWindowIDs`: Array of window IDs to exclude

**Confidence: HIGH** - Verified via WWDC23 session and developer forum confirmations.

---

### Live Window Preview

For showing live previews of windows in a custom picker UI:

```swift
import ScreenCaptureKit

func getWindowThumbnails() async throws -> [(window: SCWindow, image: CGImage)] {
    // NOTE: This requires Screen Recording permission
    let content = try await SCShareableContent.excludingDesktopWindows(
        false,
        onScreenWindowsOnly: true
    )

    var thumbnails: [(SCWindow, CGImage)] = []

    for window in content.windows {
        // Skip windows we don't want
        guard window.isOnScreen,
              !(window.title?.isEmpty ?? true) else { continue }

        let filter = SCContentFilter(desktopIndependentWindow: window)

        let config = SCStreamConfiguration()
        config.width = 200  // Thumbnail size
        config.height = 200
        config.scalesToFit = true

        let image = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: config
        )

        thumbnails.append((window, image))
    }

    return thumbnails
}
```

**Important:** This approach requires Screen Recording permission. For permission-free previews, rely on `SCContentSharingPicker` which shows its own preview thumbnails.

**Recommendation:** Use `SCContentSharingPicker` unless you need a highly customized picker UI. The system picker is polished and permission-free.

**Confidence: MEDIUM** - SCShareableContent requires permission; picker approach avoids this.

---

### Window Enumeration

For enumerating windows (e.g., finding iOS Simulator):

```swift
import ScreenCaptureKit

// Modern approach - ScreenCaptureKit (requires permission)
func findSimulatorWindows() async throws -> [SCWindow] {
    let content = try await SCShareableContent.excludingDesktopWindows(
        false,
        onScreenWindowsOnly: true
    )

    return content.windows.filter { window in
        window.owningApplication?.bundleIdentifier == "com.apple.iphonesimulator"
    }
}
```

**Legacy approach (still works for metadata only):**
```swift
import CoreGraphics

func getWindowList() -> [[String: Any]]? {
    let options = CGWindowListOption(arrayLiteral: .optionOnScreenOnly, .excludeDesktopElements)
    let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]
    return windowList
}
```

**Note:** `CGWindowListCopyWindowInfo` is NOT deprecated and works for window metadata. Only `CGWindowListCreateImage` is deprecated.

**Confidence: HIGH** - Verified via Apple documentation.

---

### iOS Simulator Detection

For detecting running iOS Simulator windows:

```swift
import ScreenCaptureKit

func findSimulatorWindows() async throws -> [SCWindow] {
    let content = try await SCShareableContent.excludingDesktopWindows(
        false,
        onScreenWindowsOnly: true
    )

    let simulatorBundleID = "com.apple.iphonesimulator"

    return content.windows.filter { window in
        window.owningApplication?.bundleIdentifier == simulatorBundleID &&
        window.isOnScreen &&
        window.windowLayer == 0  // Normal window layer
    }
}

// Alternative: Using xcrun simctl for device list
func getBootedSimulators() async throws -> [String] {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    process.arguments = ["simctl", "list", "devices", "booted", "-j"]

    let pipe = Pipe()
    process.standardOutput = pipe

    try process.run()
    process.waitUntilExit()

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    // Parse JSON for device UDIDs and names
    return []
}
```

**Confidence: HIGH** - Bundle identifier is stable Apple convention.

---

## NOT Recommended

### Custom Region Selection UI

**What:** Building a custom transparent overlay window with cross-hair selection from scratch.

**Why avoid:**
- Significant implementation complexity (multi-monitor support, coordinate systems)
- Users expect native macOS selection behavior (space to move, escape to cancel)
- The native `screencapture -i` command provides all this for free
- Edge cases: menu bar, Dock, spaces/mission control

**Reference:** Apple's own screencapture uses 5 separate windows and private APIs for its selection UI. This is not worth replicating.

**Exception:** If you need PROGRAMMATIC region selection (no user interaction), you must build custom UI or use `screencapture -R x,y,w,h`.

---

### CGWindowListCreateImage

**What:** Legacy API for capturing windows to CGImage.

**Status:**
- Deprecated in macOS 14 (Sonoma)
- Obsoleted/unavailable in macOS 15 (Sequoia)

**Why avoid:**
- ScreenCaptureKit provides superior performance (15% less RAM, 50% less CPU)
- ScreenCaptureKit delivers 60 fps vs 7 fps with legacy API
- Missing modern features (HDR support, better color spaces)

**Migration:** Use `SCScreenshotManager.captureImage(contentFilter:configuration:)` instead.

---

### Direct SCShareableContent for Window Lists (as picker)

**What:** Using `SCShareableContent.excludingDesktopWindows()` to build your own window picker.

**Why avoid:**
- Requires Screen Recording permission upfront
- Permission prompts every month in macOS 15+ (Sequoia)
- `SCContentSharingPicker` is system-provided and permission-free

**When acceptable:**
- Listing windows for automation (not user-facing picker)
- Capturing windows in background without user interaction
- Already have Screen Recording permission for other features

---

### AVCaptureScreenInput

**What:** AVFoundation-based screen capture.

**Why avoid:**
- Designed for video recording, not screenshots
- More complex setup for single-frame capture
- ScreenCaptureKit is the modern replacement

---

## Integration Points

### Existing Dispatch Architecture

The new screenshot capture integrates with existing components:

| Existing Component | Integration |
|--------------------|-------------|
| `Screenshot` model | Extend to support "quick capture" source type |
| `ScreenshotWatcherService` | Add captured screenshots to existing file system structure |
| `AnnotationWindow` | Open after capture for annotation |
| `EmbeddedTerminalService` | Dispatch annotated screenshots to Claude Code |

### Suggested New Components

| Component | Purpose |
|-----------|---------|
| `ScreenCaptureService` | Orchestrates capture modes (region, window) |
| `WindowPickerController` | Wraps SCContentSharingPicker for SwiftUI |
| `CaptureCoordinator` | Handles capture -> annotation -> dispatch flow |

### Flow Integration

```
User triggers capture (hotkey or menu)
         |
         v
   +-----------+
   | Region?   |---> screencapture -i --> File saved --> Open in AnnotationWindow
   +-----------+
         |
         v (Window)
   +-----------+
   | Picker    |---> SCContentSharingPicker --> SCScreenshotManager --> AnnotationWindow
   +-----------+
```

---

## Permissions

### Screen Recording Permission Matrix

| Approach | Permission Required? |
|----------|---------------------|
| `screencapture -i` (interactive) | NO - user-initiated |
| `SCContentSharingPicker` | NO - system picker is user-initiated |
| `SCShareableContent.excludingDesktopWindows()` | YES |
| `SCScreenshotManager.captureImage()` with custom filter | YES (if not from picker) |

### Entitlements

For App Store distribution:

```xml
<!-- Info.plist -->
<key>NSScreenCaptureUsageDescription</key>
<string>Dispatch needs screen recording access to capture windows for annotation.</string>
```

For direct distribution (non-sandboxed):
- No special entitlements needed for `screencapture` command
- Screen Recording permission handled by system preferences

### Sandbox Considerations

If sandboxed:
- `screencapture` command may not work (process isolation)
- Must use ScreenCaptureKit exclusively
- Add `com.apple.security.temporary-exception.files.home-relative-path.read-write` for saving files

**Observation:** Dispatch appears to be non-sandboxed based on existing AppleScript Terminal integration. This simplifies capture implementation.

---

## Performance Considerations

### CGWindowListCreateImage vs SCScreenshotManager

| Metric | CGWindowListCreateImage | SCScreenshotManager |
|--------|------------------------|---------------------|
| Frame rate (continuous) | ~7 fps | ~60 fps |
| CPU usage | Higher | ~50% less |
| RAM usage | Higher | ~15% less |
| Async support | Synchronous only | Native async/await |

### Async Considerations

`SCScreenshotManager.captureImage` is async. For mouse-tracking scenarios (like live preview during drag), the async nature can cause lag. For such cases, consider:
1. Throttling capture requests
2. Using preview thumbnails instead of real-time capture
3. Caching recent captures

---

## Sources

### Official Documentation (HIGH confidence)
- [ScreenCaptureKit | Apple Developer Documentation](https://developer.apple.com/documentation/screencapturekit/)
- [SCContentSharingPicker | Apple Developer Documentation](https://developer.apple.com/documentation/screencapturekit/sccontentsharingpicker)
- [What's new in ScreenCaptureKit - WWDC23](https://developer.apple.com/videos/play/wwdc2023/10136/)
- [screencapture Man Page - SS64](https://ss64.com/mac/screencapture.html)

### Technical Articles (MEDIUM confidence)
- [A look at ScreenCaptureKit on macOS Sonoma | Nonstrict](https://nonstrict.eu/blog/2023/a-look-at-screencapturekit-on-macos-sonoma/)
- [Deconstructing and Reimplementing macOS' screencapture CLI | Eternal Storms](https://blog.eternalstorms.at/2016/09/10/deconstructing-and-reimplementing-macos-screencapture-cli/)

### Developer Forums (MEDIUM confidence)
- [CGWindowListCreateImage -> ScreenCaptureKit Migration | Apple Developer Forums](https://developer.apple.com/forums/thread/740493)
- [ScreenCaptureKit entitlements discussion | Apple Developer Forums](https://developer.apple.com/forums/thread/683860)

### Implementation References (LOW-MEDIUM confidence)
- [ScreenCapture GitHub - Swift 6 app with region capture](https://github.com/sadopc/ScreenCapture)
- [NSWindowStyles - Window customization examples](https://github.com/lukakerr/NSWindowStyles)

# Phase 24: Window Capture - Research

**Researched:** 2026-02-09
**Domain:** ScreenCaptureKit - Window Selection & Capture
**Confidence:** HIGH

## Summary

Window capture in macOS 14+ uses ScreenCaptureKit's SCContentSharingPicker for user-driven window selection combined with SCScreenshotManager for single-frame image capture. This approach requires no Screen Recording permission since the system picker handles authorization through user interaction.

The implementation flow:
1. Present SCContentSharingPicker (system UI) to user
2. Receive SCContentFilter via observer callback after selection
3. Use SCScreenshotManager.captureImage() to capture window as CGImage
4. Save CGImage to QuickCaptures directory

iOS Simulator windows can be made prominent through SCContentSharingPickerConfiguration by excluding other apps or through natural system ordering (recently-used windows appear first).

**Primary recommendation:** Use SCContentSharingPicker + SCScreenshotManager for permission-free window capture. This is the modern, official API that replaces CGWindowListCreateImage.

## Standard Stack

The established libraries/tools for window capture on macOS:

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| ScreenCaptureKit | macOS 14.0+ | Window selection & capture | Official Apple framework; replaces deprecated CGWindow APIs |
| SCContentSharingPicker | macOS 14.0+ | System window picker UI | No permission required; user-authorized selection |
| SCScreenshotManager | macOS 12.3+ | Single-frame capture | Async API for CGImage capture; no streaming overhead |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| SCShareableContent | macOS 12.3+ | Query available windows | When building custom window lists |
| CGImage | macOS 10.0+ | Image representation | Converting screenshots to PNG |
| NSBitmapImageRep | macOS 10.0+ | Image encoding | PNG data from CGImage |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| SCContentSharingPicker | SCShareableContent + custom UI | Requires Screen Recording permission; more complex |
| SCScreenshotManager | SCStream + frame extraction | Streaming overhead for single capture; more complex |
| ScreenCaptureKit | CGWindowListCreateImage | Deprecated; requires Screen Recording permission |
| ScreenCaptureKit | screencapture -l CLI | Less control; can't filter by app easily |

**Installation:**
Built-in framework - no installation needed. Requires:
```swift
import ScreenCaptureKit
```

**Minimum requirements:**
- macOS 14.0 (Sonoma) for SCContentSharingPicker
- macOS 12.3 (Monterey) for SCScreenshotManager

## Architecture Patterns

### Recommended Project Structure
```
Services/
├── ScreenshotCaptureService.swift    # Existing: region capture
│   ├── captureRegion()               # ✓ Already implemented
│   └── captureWindow()               # → New: window capture
└── (No new services needed)
```

### Pattern 1: Picker Observer Pattern
**What:** SCContentSharingPicker uses delegate-based observer pattern for window selection
**When to use:** All window capture flows (one-time and streaming)
**Example:**
```swift
// Source: https://developer.apple.com/videos/play/wwdc2023/10136/

@MainActor
final class ScreenshotCaptureService: SCContentSharingPickerObserver {
    private let picker = SCContentSharingPicker.shared

    func captureWindow() async -> CaptureResult {
        // 1. Set up observer
        picker.add(self)
        picker.isActive = true

        // 2. Present picker (system UI)
        picker.present(using: .window)

        // 3. Wait for callback (see contentSharingPicker method below)
    }

    // Observer callback - receives selected window
    nonisolated func contentSharingPicker(
        _ picker: SCContentSharingPicker,
        didUpdateWith filter: SCContentFilter,
        for stream: SCStream?
    ) {
        Task { @MainActor in
            // Use filter to capture screenshot
            await captureWithFilter(filter)
        }
    }

    nonisolated func contentSharingPickerStartDidFailWithError(
        _ error: Error
    ) {
        // Handle picker failure
    }

    nonisolated func contentSharingPicker(
        _ picker: SCContentSharingPicker,
        didCancelFor stream: SCStream?
    ) {
        // Handle user cancellation
    }
}
```

### Pattern 2: Screenshot Capture (Not Streaming)
**What:** Use SCScreenshotManager for single-frame capture without stream overhead
**When to use:** When you need an image file, not a video stream
**Example:**
```swift
// Source: https://developer.apple.com/videos/play/wwdc2023/10136/
// Combined from multiple search results

func captureWithFilter(_ filter: SCContentFilter) async throws -> URL {
    // 1. Configure screenshot
    let config = SCStreamConfiguration()
    config.showsCursor = false
    config.width = Int(Float(filter.contentRect.width) * filter.pointPixelScale)
    config.height = Int(Float(filter.contentRect.height) * filter.pointPixelScale)

    // 2. Capture as CGImage
    let cgImage = try await SCScreenshotManager.captureImage(
        contentFilter: filter,
        configuration: config
    )

    // 3. Save to PNG
    let filename = "\(UUID().uuidString).png"
    let outputPath = capturesDirectory.appendingPathComponent(filename)
    try saveCGImageAsPNG(cgImage, to: outputPath)

    return outputPath
}
```

### Pattern 3: CGImage to PNG Conversion
**What:** Convert CGImage to PNG file on disk
**When to use:** After SCScreenshotManager.captureImage returns CGImage
**Example:**
```swift
// Source: https://www.hackingwithswift.com/example-code/media/how-to-save-a-uiimage-to-a-file-using-jpegdata-and-pngdata
// Adapted for macOS + CGImage

func saveCGImageAsPNG(_ cgImage: CGImage, to url: URL) throws {
    let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
    guard let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
        throw CaptureError.pngConversionFailed
    }
    try pngData.write(to: url)
}
```

### Pattern 4: Highlighting Simulator Windows
**What:** Configure picker to show Simulator windows prominently
**When to use:** When user frequently captures iOS Simulator
**Example:**
```swift
// Source: https://developer.apple.com/videos/play/wwdc2023/10136/

func configurePickerForSimulator() {
    let config = SCContentSharingPickerConfiguration()

    // Option 1: Exclude other apps (Simulator only)
    // Note: This is very restrictive - not recommended
    // config.allowedBundleIDs = ["com.apple.iphonesimulator"]

    // Option 2: Exclude common apps (Simulator shows up higher)
    config.excludedBundleIDs = [
        "com.Eric.Dispatch",  // Hide our own app
        "com.apple.finder",   // Hide Finder
        // Add other non-Simulator apps
    ]

    // Allow re-picking for multi-capture workflows
    config.allowsRepicking = true

    picker.setConfiguration(config, for: nil)
}
```

**Note:** System picker naturally shows recently-used windows first. If user recently interacted with Simulator, it appears at top automatically.

### Anti-Patterns to Avoid
- **Using SCStream for screenshots:** Creates streaming overhead for single-frame capture. Use SCScreenshotManager instead.
- **Building custom window picker:** Requires Screen Recording permission. Use SCContentSharingPicker instead.
- **Using CGWindowListCreateImage:** Deprecated API. Migrate to ScreenCaptureKit.
- **Calling picker.present() before setting active:** System won't recognize your picker. Always set `isActive = true` first.

## Don't Hand-Roll

Problems that look simple but have existing solutions:

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Window selection UI | Custom NSWindow with window list | SCContentSharingPicker | No permission needed; system UI handles privacy |
| Window screenshots | CGWindowListCreateImage wrapper | SCScreenshotManager | Modern async API; better performance |
| Permission handling | Custom Screen Recording prompt | SCContentSharingPicker | User selection = implicit authorization |
| Window filtering | Manual bundle ID checks | SCContentSharingPickerConfiguration | Declarative; system-optimized |

**Key insight:** ScreenCaptureKit's permission model is fundamentally different from CGWindow APIs. User-initiated selection through SCContentSharingPicker bypasses traditional Screen Recording authorization entirely. Custom implementations lose this benefit.

## Common Pitfalls

### Pitfall 1: Forgetting to Set Picker Active
**What goes wrong:** Picker presents but doesn't receive callbacks, or system doesn't integrate picker with menu bar
**Why it happens:** Picker must be registered with system before presentation
**How to avoid:** Always call `picker.isActive = true` before `picker.present()`
**Warning signs:** Observer methods never called; picker UI appears but nothing happens on selection

### Pitfall 2: Calling Picker on Background Thread
**What goes wrong:** Runtime crash or picker doesn't present
**Why it happens:** SCContentSharingPicker requires main thread (UI operation)
**How to avoid:** Mark service @MainActor or wrap picker calls in `MainActor.run`
**Warning signs:** "UI API called on background thread" errors

### Pitfall 3: Not Removing Observer
**What goes wrong:** Memory leaks or duplicate callbacks if service is recreated
**Why it happens:** Picker holds reference to observer
**How to avoid:** Call `picker.remove(self)` in deinit or when capture completes
**Warning signs:** Callbacks fire multiple times; memory usage grows

### Pitfall 4: Assuming Picker is Modal
**What goes wrong:** Code continues executing before user selects window
**Why it happens:** `picker.present()` returns immediately (non-blocking)
**How to avoid:** Use async/await with continuation or delegate pattern
**Warning signs:** Attempting to use filter before user selection completes

### Pitfall 5: Wrong CGImage to PNG Conversion
**What goes wrong:** Saved PNG is corrupt or has wrong color space
**Why it happens:** Direct CGImage data doesn't include PNG format headers
**How to avoid:** Use NSBitmapImageRep or CGImageDestination for proper encoding
**Warning signs:** Files created but won't open; wrong dimensions

### Pitfall 6: Not Handling Cancellation
**What goes wrong:** App hangs waiting for filter that never arrives
**Why it happens:** User can cancel picker without selecting anything
**How to avoid:** Implement `contentSharingPicker(_:didCancelFor:)` observer method
**Warning signs:** Async tasks never complete; UI becomes unresponsive

## Code Examples

Verified patterns from official sources:

### Complete Window Capture Flow
```swift
// Source: Synthesized from https://developer.apple.com/videos/play/wwdc2023/10136/

@MainActor
final class ScreenshotCaptureService: SCContentSharingPickerObserver {
    static let shared = ScreenshotCaptureService()

    private let picker = SCContentSharingPicker.shared
    private let capturesDirectory: URL
    private var captureContination: CheckedContinuation<CaptureResult, Never>?

    func captureWindow() async -> CaptureResult {
        return await withCheckedContinuation { continuation in
            captureContination = continuation

            // Configure picker
            picker.add(self)
            picker.isActive = true

            // Optional: Configure to highlight Simulator
            let config = SCContentSharingPickerConfiguration()
            config.excludedBundleIDs = ["com.Eric.Dispatch"]
            config.allowsRepicking = true
            picker.setConfiguration(config, for: nil)

            // Present system picker
            picker.present(using: .window)
        }
    }

    nonisolated func contentSharingPicker(
        _ picker: SCContentSharingPicker,
        didUpdateWith filter: SCContentFilter,
        for stream: SCStream?
    ) {
        Task { @MainActor in
            do {
                let url = try await captureWithFilter(filter)
                captureContination?.resume(returning: .success(url))
            } catch {
                captureContination?.resume(returning: .error(error))
            }
            captureContination = nil
            picker.remove(self)
        }
    }

    nonisolated func contentSharingPickerStartDidFailWithError(_ error: Error) {
        Task { @MainActor in
            captureContination?.resume(returning: .error(error))
            captureContination = nil
        }
    }

    nonisolated func contentSharingPicker(
        _ picker: SCContentSharingPicker,
        didCancelFor stream: SCStream?
    ) {
        Task { @MainActor in
            captureContination?.resume(returning: .cancelled)
            captureContination = nil
            picker.remove(self)
        }
    }

    private func captureWithFilter(_ filter: SCContentFilter) async throws -> URL {
        // Configure screenshot dimensions
        let config = SCStreamConfiguration()
        config.showsCursor = false
        config.width = Int(Float(filter.contentRect.width) * filter.pointPixelScale)
        config.height = Int(Float(filter.contentRect.height) * filter.pointPixelScale)

        // Capture image
        let cgImage = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: config
        )

        // Save to PNG
        let filename = "\(UUID().uuidString).png"
        let outputPath = capturesDirectory.appendingPathComponent(filename)
        try saveCGImageAsPNG(cgImage, to: outputPath)

        logInfo("Window captured: \(filename)", category: .capture)
        return outputPath
    }

    private func saveCGImageAsPNG(_ cgImage: CGImage, to url: URL) throws {
        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
        guard let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
            throw CaptureError.pngConversionFailed
        }
        try pngData.write(to: url)
    }
}
```

### Querying Available Windows (Alternative Approach)
```swift
// Source: https://developer.apple.com/documentation/screencapturekit/scshareablecontent

// If you need programmatic window access (requires Screen Recording permission):
let content = try await SCShareableContent.excludingDesktopWindows(
    false,
    onScreenWindowsOnly: true
)

// Find Simulator windows
let simulatorWindows = content.windows.filter { window in
    window.owningApplication?.bundleIdentifier == "com.apple.iphonesimulator"
}

// Create filter for specific window
let filter = SCContentFilter(desktopIndependentWindow: simulatorWindows[0])
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| CGWindowListCreateImage | SCScreenshotManager | macOS 12.3 (2022) | Async API; better performance; modern error handling |
| Custom window picker | SCContentSharingPicker | macOS 14.0 (2023) | No Screen Recording permission needed |
| SCSharableContent.getWithCompletionHandler | async/await SCShareableContent | macOS 13.0 (2022) | Cleaner async code |
| Streaming for screenshots | SCScreenshotManager | macOS 12.3 (2022) | No stream overhead; simpler API |

**Deprecated/outdated:**
- **CGWindowListCreateImage**: Replaced by SCScreenshotManager. Still works but not recommended.
- **CGWindowListCreateImageFromArray**: Use SCContentFilter instead.
- **Screen Recording permission for picker**: SCContentSharingPicker bypasses this entirely.

## Open Questions

Things that couldn't be fully resolved:

1. **Simulator window prominence in system picker**
   - What we know: System picker shows recently-used windows first; can exclude apps via config
   - What's unclear: Whether `allowedBundleIDs` actually highlights windows or just filters picker list
   - Recommendation: Use excludedBundleIDs to hide non-Simulator apps. Test both approaches. System's recent-window ordering may be sufficient.

2. **Picker configuration persistence**
   - What we know: `setConfiguration(_:for:)` accepts optional SCStream parameter
   - What's unclear: If passing `nil` makes config global vs. per-stream
   - Recommendation: Pass `nil` for single-capture use case. Document behavior after testing.

3. **Early beta Screen Recording permission bug**
   - What we know: Early Sonoma betas required Screen Recording permission despite using picker
   - What's unclear: Whether this is fully resolved in current macOS versions
   - Recommendation: Test on macOS 14.0+ to verify permission-free operation. File feedback if permission prompt appears.

## Sources

### Primary (HIGH confidence)
- [SCContentSharingPicker | Apple Developer Documentation](https://developer.apple.com/documentation/screencapturekit/sccontentsharingpicker)
- [What's new in ScreenCaptureKit - WWDC23](https://developer.apple.com/videos/play/wwdc2023/10136/)
- [SCScreenshotManager | Apple Developer Documentation](https://developer.apple.com/documentation/screencapturekit/scscreenshotmanager)
- [ScreenCaptureKit | Apple Developer Documentation](https://developer.apple.com/documentation/screencapturekit/)
- [Capturing screen content in macOS | Apple Developer Documentation](https://developer.apple.com/documentation/ScreenCaptureKit/capturing-screen-content-in-macos)

### Secondary (MEDIUM confidence)
- [A look at ScreenCaptureKit on macOS Sonoma | Nonstrict](https://nonstrict.eu/blog/2023/a-look-at-screencapturekit-on-macos-sonoma/)
- [SwiftUI: Screen Capturing on MacOS | Level Up Coding](https://levelup.gitconnected.com/swiftui-screen-capturing-streaming-sharing-recording-on-macos-1550e0abd64e)
- [Screen Sharing Got Smarter on macOS](https://blog.addpipe.com/screen-sharing-got-smarter-and-more-private-on-macos-understanding-the-system-private-window-picker/)
- [How to save a UIImage to a file using jpegData() and pngData()](https://www.hackingwithswift.com/example-code/media/how-to-save-a-uiimage-to-a-file-using-jpegdata-and-pngdata)

### Tertiary (LOW confidence)
- GitHub sample projects - various implementations
- Developer forums - community discussions

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - Official Apple APIs with WWDC sessions and documentation
- Architecture: HIGH - WWDC sample code and official documentation patterns
- Pitfalls: MEDIUM - Based on observer pattern experience and forum discussions, not exhaustive testing
- Simulator prominence: MEDIUM - Configuration options documented, but "prominence" behavior unclear

**Research date:** 2026-02-09
**Valid until:** 2026-03-09 (30 days - stable API)
**ScreenCaptureKit introduced:** macOS 12.3 (March 2022)
**SCContentSharingPicker introduced:** macOS 14.0 (September 2023)

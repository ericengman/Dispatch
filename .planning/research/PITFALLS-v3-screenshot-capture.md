# Pitfalls Research: Screenshot Capture

**Domain:** macOS screenshot capture for existing SwiftUI app
**Researched:** 2026-02-09
**Confidence:** HIGH (based on official Apple documentation, developer forums, and open-source project issues)

---

## Critical Pitfalls

High-impact issues that could block the feature entirely or require significant rework.

### Pitfall 1: CGWindowListCreateImage Deprecation

**What goes wrong:** Using CGWindowListCreateImage on macOS 15+ causes compilation warnings or failures. Apple deprecated this API in macOS Sequoia and recommends ScreenCaptureKit instead.

**Why it happens:** Code examples online (Stack Overflow, tutorials) predominantly use the deprecated CoreGraphics APIs because they were the standard for 15+ years.

**Consequences:**
- Build warnings that may become errors in future Xcode versions
- App Store review rejection for using deprecated APIs
- Missing functionality as CoreGraphics capture stops working

**Prevention:**
- Use ScreenCaptureKit (SCScreenshotManager) for macOS 12.3+ targets
- For single-frame captures, use `SCScreenshotManager.captureImage(contentFilter:configuration:)`
- Only fall back to CGWindowListCreateImage for macOS 12.2 and earlier if supporting old OS versions

**Detection:** Build warnings mentioning "deprecated" and CGWindowListCreateImage

**Phase:** Foundation phase - choose ScreenCaptureKit from the start

**Sources:**
- [JUCE Framework Issue #1414](https://github.com/juce-framework/JUCE/issues/1414)
- [Neutralinojs Issue #1359](https://github.com/neutralinojs/neutralinojs/issues/1359)
- [Apple Developer Forums - CGWindowListCreateImage to ScreenCaptureKit](https://developer.apple.com/forums/thread/740493)

---

### Pitfall 2: Screen Recording Permission Stale Cache

**What goes wrong:** `CGPreflightScreenCaptureAccess()` returns false even after the user grants permission. The permission status gets cached and doesn't update until app restart.

**Why it happens:** macOS caches permission state at launch. The check functions don't re-query the TCC database in real-time.

**Consequences:**
- Users grant permission but capture still fails
- Confusing UX where user must quit and restart app
- Support tickets from users who "enabled the permission but it doesn't work"

**Prevention:**
1. Call `CGRequestScreenCaptureAccess()` (which prompts) instead of just checking
2. After prompting, display a message: "Please restart Dispatch for the permission to take effect"
3. Use ScreenCaptureKit's `SCShareableContent.getWithCompletionHandler` which has better permission detection
4. Store a "permission was granted" flag and guide users through restart

**Detection:** Permission UI shows "granted" but captures return nil or black images

**Phase:** Permission handling phase - build robust permission flow early

**Sources:**
- [mac-screen-capture-permissions on GitHub](https://github.com/karaggeorge/mac-screen-capture-permissions)
- [Apple Developer Forums - Understanding CGRequestScreenCaptureAccess](https://developer.apple.com/forums/thread/732726)

---

### Pitfall 3: Fullscreen Window Capture Split

**What goes wrong:** When capturing a fullscreen app window, only the titlebar OR the content is captured, not both together.

**Why it happens:** macOS splits fullscreen windows into two separate windows internally - one for the titlebar/toolbar area and one for the content. Standard window capture APIs treat these as separate windows.

**Consequences:**
- Incomplete screenshots of fullscreen apps
- User confusion when screenshots don't match what they see
- Need for special-case handling

**Prevention:**
1. Detect fullscreen windows via `CGWindow.kCGWindowListOptionOnScreenOnly`
2. For fullscreen apps, capture the entire display instead of individual windows
3. Use ScreenCaptureKit's display capture mode for fullscreen scenarios
4. Consider excluding fullscreen windows from window picker and offering "Capture Display" instead

**Detection:** Screenshots of fullscreen apps show only titlebar or only content

**Phase:** Window capture phase - test fullscreen scenarios explicitly

**Sources:**
- [Deconstructing macOS screencapture CLI - Eternal Storms](https://blog.eternalstorms.at/2016/09/10/deconstructing-and-reimplementing-macos-screencapture-cli/)

---

## Permission Pitfalls

Issues specific to Screen Recording and related permissions.

### Pitfall 4: macOS Sequoia Monthly Permission Prompts

**What goes wrong:** macOS 15 Sequoia shows recurring monthly prompts asking users to re-confirm screen recording permission, even for previously approved apps.

**Why it happens:** Apple tightened security in Sequoia with mandatory periodic re-consent for screen recording.

**Consequences:**
- User annoyance with repeated prompts
- Permission may be denied on subsequent prompts, breaking feature
- Users may think the app is broken or doing something sketchy

**Prevention:**
1. Clearly communicate why screen capture is needed before requesting
2. Provide in-app education about the recurring prompt (it's system-wide, not your app)
3. Handle permission denial gracefully with helpful error messages
4. Consider offering fallback modes that don't require screen recording (e.g., drag-drop of existing images)

**Detection:** App works fine initially, then fails monthly

**Phase:** Permission phase - design UX expecting periodic re-prompts

**Sources:**
- [TidBITS - Sequoia's Repetitive Screen Recording Permissions](https://talk.tidbits.com/t/how-to-avoid-sequoia-s-repetitive-screen-recording-permissions-prompts/28957)
- [Apple Community Discussion](https://discussions.apple.com/thread/255478737)

---

### Pitfall 5: Non-Bundled Executables Permission UI Bug

**What goes wrong:** On macOS 26.1 (Tahoe), plain executables (not .app bundles) that request screen recording don't appear in System Settings Privacy panel, making it impossible for users to manage permissions.

**Why it happens:** Apple UI bug/limitation in Tahoe - only properly bundled apps appear in the settings.

**Consequences:**
- If you have CLI tools or helpers that need capture permission, they can't be managed
- Users can't revoke/re-grant permission through normal UI

**Prevention:**
1. Always use a proper .app bundle for any screen capture functionality
2. Don't split capture into separate CLI tools or XPC services that might not be bundled
3. Dispatch is already a bundled app - keep all capture code in the main bundle

**Detection:** Permission prompts appear but app not visible in System Settings

**Phase:** Architecture phase - ensure all capture code stays in main bundle

**Sources:**
- [ScreenCaptureKit Apple Developer Forums](https://developer.apple.com/forums/tags/screencapturekit)

---

### Pitfall 6: Certificate Change Breaks Permission Persistence

**What goes wrong:** When transitioning between Developer ID certificates (or from development to distribution signing), macOS may not connect the new app version to previously granted permissions.

**Why it happens:** TCC database keys permissions to code signature identity. Different certificates = different identity.

**Consequences:**
- Users who previously granted permission must grant it again
- App may appear as entirely new in System Settings
- Confusion during development with multiple signing identities

**Prevention:**
1. Use consistent signing identity throughout development
2. Warn beta testers that permission may need re-granting on certificate changes
3. For production, ensure your Developer ID certificate is stable
4. Handle permission-not-granted gracefully even if it was previously granted

**Detection:** Permission worked before, now doesn't after update

**Phase:** Not phase-specific - be aware throughout

---

## Implementation Pitfalls

Issues with cross-hair UI, window capture, and selection mechanics.

### Pitfall 7: Transparent Overlay Mouse Event Pass-Through

**What goes wrong:** Creating a fullscreen transparent overlay for region selection, but mouse events either don't register (pass through) or block all interaction with underlying apps.

**Why it happens:** `NSWindow.ignoresMouseEvents` is binary - the overlay either captures all clicks or none. Getting selective pass-through (receive drags, ignore clicks) requires careful coordination.

**Consequences:**
- Crosshair selection doesn't receive drag events
- OR users can't click to cancel or interact with other windows
- Frustrating UX where nothing responds as expected

**Prevention:**
1. Set `ignoresMouseEvents = false` during selection mode
2. Use `NSPanel` with `.nonActivatingPanel` style mask for the overlay
3. For SwiftUI, wrap in `NSViewRepresentable` with custom `NSHostingView` that handles mouse events
4. Set `.canBecomeKey = true` on the panel to receive keyboard events (Escape to cancel)
5. Use `NSTrackingArea` for precise mouse location tracking during drag

**Detection:** Mouse drags don't register or clicking outside selection area fails

**Phase:** Cross-hair UI phase - prototype mouse handling early

**Sources:**
- [Hacking with Swift Forums - Mouse Tracking](https://developer.apple.com/forums/thread/678661)
- [SwiftUI Lab - Hosting+Representable Combo](https://swiftui-lab.com/a-powerful-combo/)
- [Building an Invisible Mac App - Pierce Freeman](https://pierce.dev/notes/building-a-kind-of-invisible-mac-app)

---

### Pitfall 8: SwiftUI Overlay Sheet Interaction Bug

**What goes wrong:** SwiftUI overlays stop responding correctly when a sheet is presented somewhere in the view hierarchy.

**Why it happens:** SwiftUI's overlay modifier has known bugs with sheet presentation - the overlay may not receive events or may be hidden.

**Consequences:**
- Selection overlay stops working when any sheet is open
- Inconsistent behavior depending on view hierarchy

**Prevention:**
1. Use AppKit `NSWindow` / `NSPanel` for the selection overlay instead of SwiftUI `.overlay()`
2. Present the overlay as a separate window, not as part of the SwiftUI view hierarchy
3. Avoid sheets while capture mode is active

**Detection:** Selection overlay works sometimes but not others

**Phase:** Cross-hair UI phase - use NSPanel approach, not SwiftUI overlay

**Sources:**
- [SimplyKyra - SwiftUI Overlays and Sheets Issue](https://www.simplykyra.com/blog/swiftui-overlays-and-their-issue-with-sheets/)

---

### Pitfall 9: Multi-Display Coordinate System Confusion

**What goes wrong:** Region selection coordinates are wrong when using multiple displays, especially with mixed Retina/non-Retina or different arrangements.

**Why it happens:** macOS uses a global coordinate system where (0,0) is the bottom-left of the primary display. Secondary displays can have negative coordinates. Different displays have different `backingScaleFactor` values.

**Consequences:**
- Captured region doesn't match selected region
- Off-by-hundreds-of-pixels errors on multi-monitor setups
- Correct on single display, broken on multi-display

**Prevention:**
1. Use `NSScreen.screens` to get all displays and their frames
2. Convert points using `NSScreen.convertRect(toScreen:)`
3. For each display, account for its `backingScaleFactor` when calculating pixel coordinates
4. Test explicitly with multi-display setups during development
5. The primary display has `frame.origin = (0, 0)` - others can be negative

**Detection:** Works on single display, wrong on multi-display

**Phase:** Region selection phase - test multi-monitor explicitly

**Sources:**
- [Flameshot Issue #1258 - Multi Monitor](https://github.com/flameshot-org/flameshot/issues/1258)
- [Apple Developer Forums - Multi Monitor Screenshot](https://developer.apple.com/forums/thread/108093)

---

### Pitfall 10: Retina/HiDPI Scale Factor Mismatch

**What goes wrong:** Captured images are 2x the expected size, or coordinates are halved, causing misalignment between what user selects and what's captured.

**Why it happens:** Retina displays have `backingScaleFactor = 2.0`. Screen coordinates are in points, but capture APIs return pixels. Mixing up points and pixels causes 2x errors.

**Consequences:**
- Selection rectangle captures wrong region (shifted by 2x)
- Images are huge (capturing at 2x scale when 1x expected)
- Annotations don't align with image features

**Prevention:**
1. Always query `NSScreen.main?.backingScaleFactor` or window's `backingScaleFactor`
2. When using ScreenCaptureKit, configure `SCStreamConfiguration.scalesToFit` appropriately
3. Multiply point coordinates by scale factor when converting to pixel coordinates
4. When displaying captured image, set layer's `contentsScale` to match backing scale factor
5. Dispatch already handles this in `AnnotationCanvasView` - follow that pattern

**Detection:** Everything is 2x off, or images are double-sized

**Phase:** Capture implementation phase - test on Retina displays

**Sources:**
- [Apple - APIs for Supporting High Resolution](https://developer.apple.com/library/archive/documentation/GraphicsAnimation/Conceptual/HighResolutionOSX/APIs/APIs.html)
- [Apple Documentation - backingScaleFactor](https://developer.apple.com/documentation/appkit/nswindow/1419459-backingscalefactor)

---

### Pitfall 11: Excluding Self Window from Capture

**What goes wrong:** The selection overlay window or the app's own windows appear in the captured screenshot.

**Why it happens:** Window capture APIs include all on-screen windows by default. The selection overlay is on-screen during capture.

**Consequences:**
- Captured images include the crosshair/selection UI
- App windows appear in "full display" captures
- Unprofessional-looking screenshots

**Prevention:**
1. With ScreenCaptureKit, use `SCContentFilter` to explicitly exclude your app by bundle identifier
2. Set `NSWindow.sharingType = .none` on selection overlay (note: broken on macOS 15+ with ScreenCaptureKit, but still helps with legacy APIs)
3. Hide the selection overlay window immediately before capture, capture, then re-show
4. For window-specific capture, filter to only the target window(s)

**Detection:** Own UI appears in captured screenshots

**Phase:** Capture implementation phase - test that self is excluded

**Sources:**
- [WWDC22 - Meet ScreenCaptureKit](https://developer.apple.com/videos/play/wwdc2022/10156/)
- [Apple Sample Code - Capturing Screen Content](https://github.com/Fidetro/CapturingScreenContentInMacOS)

---

## Performance Pitfalls

Issues affecting live preview performance and memory usage.

### Pitfall 12: Live Window Preview Performance Drain

**What goes wrong:** Showing live previews of available windows causes high CPU/GPU usage, laggy UI, or excessive memory consumption.

**Why it happens:** Capturing window thumbnails frequently (for live preview) requires repeated calls to capture APIs. Each call involves IPC with the WindowServer and memory allocation for the image buffer.

**Consequences:**
- UI becomes laggy during window selection
- Battery drain on laptops
- Memory pressure warnings

**Prevention:**
1. Use ScreenCaptureKit's `SCStream` with low frame rate (1-2 fps) for previews
2. Capture thumbnails at reduced resolution (configure `SCStreamConfiguration.width/height`)
3. Cache thumbnails and only refresh on demand or with 1-2 second debounce
4. Use `CGWindowListCopyWindowInfo` for window list (fast), but capture images sparingly
5. Implement lazy loading - only capture preview for visible/hovered windows

**Detection:** High CPU in Activity Monitor during window picker, laggy scrolling

**Phase:** Window picker phase - design for low refresh rate from the start

**Sources:**
- [Alt-Tab macOS Issue #45 - Recomputing Thumbnails](https://github.com/lwouis/alt-tab-macos/issues/45)
- [Nonstrict - ScreenCaptureKit on Sonoma](https://nonstrict.eu/blog/2023/a-look-at-screencapturekit-on-macos-sonoma/)

---

### Pitfall 13: ScreenCaptureKit Memory Pressure from Queue Depth

**What goes wrong:** ScreenCaptureKit streams consume excessive memory when configured with high queue depth.

**Why it happens:** `SCStreamConfiguration.queueDepth` controls the surface pool size. Higher values mean more frames buffered in memory. Default or misconfigured values can allocate hundreds of MB.

**Consequences:**
- Memory warnings or crashes
- System slowdown
- Unexpected memory growth over time

**Prevention:**
1. For single-frame capture (screenshots), use `SCScreenshotManager` instead of streams
2. If using streams for preview, set `queueDepth` to 2-3 (minimum practical)
3. Set `minimumFrameInterval` to limit frame rate (e.g., `CMTime(1, 2)` for 2fps)
4. Stop the stream immediately when not actively needed
5. Monitor memory usage during development

**Detection:** Memory grows during capture sessions, doesn't decrease

**Phase:** Live preview phase - configure streams conservatively

**Sources:**
- [WWDC22 - Take ScreenCaptureKit to the Next Level](https://developer.apple.com/videos/play/wwdc2022/10155/)

---

### Pitfall 14: CGImage Memory Leaks

**What goes wrong:** Repeated screen captures cause memory to grow without bound, eventually causing crashes.

**Why it happens:** CoreGraphics `CGImageRef` objects require explicit `CGImageRelease()` in C/ObjC, or proper handling in Swift where they're bridged. If the CGImage isn't properly released or autoreleased, it leaks.

**Consequences:**
- Memory grows with each capture
- Eventually app crashes or system slows
- Hard to track down without instruments

**Prevention:**
1. In Swift, ensure CGImage goes out of scope and is deallocated (no strong reference cycles)
2. Don't store CGImages long-term - convert to NSImage or Data promptly
3. Use Instruments Allocations to verify images are being deallocated
4. For repeated captures, reuse image buffers if possible
5. Explicitly nil out references when done with images

**Detection:** Memory growth in Instruments, allocation count keeps increasing

**Phase:** All capture phases - validate with Instruments

**Sources:**
- [NutJS Blog - Screen Capture Memory on Ventura](https://nutjs.dev/blog/apple-silicon-screencapture-memory)
- [Apple Developer Forums - CGImage Memory Leak](https://developer.apple.com/forums/thread/17142)

---

### Pitfall 15: ScreenCaptureKit Silent Frame Dropping

**What goes wrong:** ScreenCaptureKit stream appears to be running but frames are being dropped, resulting in choppy preview or missed captures.

**Why it happens:** Under high system load, ScreenCaptureKit drops frames to maintain responsiveness. The stream doesn't disconnect, it just delivers fewer frames.

**Consequences:**
- Preview appears frozen or choppy
- May miss the "right moment" for capture
- No error or warning - silent failure

**Prevention:**
1. Monitor `SCStreamOutput` callback frequency
2. For single captures, use `SCScreenshotManager` which waits for a complete frame
3. Don't rely on streams for time-critical single captures
4. Show UI indicator when frame rate drops below threshold

**Detection:** Preview skips, captured images don't match current screen state

**Phase:** Live preview phase - use screenshots API for actual captures

**Sources:**
- [Fat Bob Man - From Pixel Capture to Metadata](https://fatbobman.com/en/posts/screensage-from-pixel-to-meta)

---

## Integration Pitfalls

Issues when integrating screenshot capture with existing Dispatch code.

### Pitfall 16: Conflict with Existing AnnotationWindow Architecture

**What goes wrong:** The new capture overlay conflicts with the existing `AnnotationWindowController` singleton pattern, causing state confusion or multiple windows fighting for control.

**Why it happens:** Dispatch already has an annotation window system. Adding a capture overlay introduces another window that must coordinate with it.

**Consequences:**
- Two windows open at once, confusing state
- Capture overlay doesn't know about annotation window, or vice versa
- Key events go to wrong window

**Prevention:**
1. Design capture as a distinct phase that completes before annotation begins
2. Ensure capture overlay dismisses completely before annotation window opens
3. Use a coordinator/state machine to manage the capture -> annotate flow
4. Don't try to do capture and annotation simultaneously
5. Consider extending `AnnotationWindowController` to handle capture mode

**Detection:** Multiple windows open, state desync between capture and annotation

**Phase:** Architecture phase - design state flow first

---

### Pitfall 17: Blocking Main Thread During Capture

**What goes wrong:** UI freezes momentarily when capturing, especially for large displays or multiple windows.

**Why it happens:** While ScreenCaptureKit is async, some operations or image processing may inadvertently run on main thread.

**Consequences:**
- App appears frozen during capture
- Poor UX, users may force-quit
- Violates Apple's responsiveness guidelines

**Prevention:**
1. All ScreenCaptureKit calls should use async/await or completion handlers
2. Image processing (resizing, format conversion) should happen on background queue
3. Use `Task { }` for async work, ensure `@MainActor` only for UI updates
4. Show a brief loading indicator if capture takes >100ms
5. Dispatch's existing pattern with `@MainActor` and background tasks should be followed

**Detection:** UI freezes momentarily during capture operation

**Phase:** All capture phases - profile main thread

---

### Pitfall 18: NSImage/CGImage Coordinate System Mismatch with Existing Code

**What goes wrong:** Captured images appear flipped or coordinates don't match between capture and annotation.

**Why it happens:** CoreGraphics uses bottom-left origin, AppKit/NSImage uses top-left. Mixing coordinate systems without conversion causes flipping.

**Consequences:**
- Annotations appear in wrong position
- Images are upside-down
- Crop coordinates don't match visual selection

**Prevention:**
1. Pick one coordinate system and stick to it throughout
2. Dispatch's existing `AnnotationCanvasView` uses SwiftUI coordinates (top-left origin)
3. When receiving CGImage from capture, create NSImage with proper orientation
4. Test annotation placement immediately after adding capture code
5. Document the coordinate system used at each layer

**Detection:** Annotations appear at wrong Y position, images flipped

**Phase:** Integration phase - test with existing annotation code immediately

---

## Prevention Matrix

| Pitfall | Warning Signs | Prevention | Phase |
|---------|--------------|------------|-------|
| CGWindowListCreateImage Deprecation | Build warnings | Use ScreenCaptureKit | Foundation |
| Permission Stale Cache | Works after restart only | Guide user to restart, use SCShareableContent | Permission |
| Fullscreen Window Split | Partial fullscreen captures | Capture display instead, detect fullscreen | Window capture |
| Sequoia Monthly Prompts | Works then breaks monthly | UX education, graceful handling | Permission |
| Non-Bundled Permission UI Bug | Can't manage permissions | Keep code in main bundle | Architecture |
| Certificate Permission Reset | Works before update, not after | Consistent signing, handle re-auth | Throughout |
| Overlay Mouse Pass-Through | Drags don't register | NSPanel with proper config | Cross-hair UI |
| SwiftUI Overlay Sheet Bug | Overlay fails with sheets | Use NSPanel, not SwiftUI overlay | Cross-hair UI |
| Multi-Display Coordinates | Wrong on second monitor | NSScreen frame conversion, test multi-monitor | Region selection |
| Retina Scale Factor | Everything 2x off | Multiply by backingScaleFactor | Capture implementation |
| Self Window in Capture | Own UI in screenshot | SCContentFilter exclude, hide before capture | Capture implementation |
| Live Preview Performance | Laggy UI, high CPU | Low FPS, cached thumbnails | Window picker |
| SCK Queue Memory | Memory growth | Low queueDepth, stop streams | Live preview |
| CGImage Leaks | Memory never decreases | Nil references, Instruments validation | All capture |
| Silent Frame Dropping | Choppy preview | Use SCScreenshotManager for single capture | Live preview |
| AnnotationWindow Conflict | State confusion | Sequential phases, state machine | Architecture |
| Main Thread Blocking | UI freeze | Async capture, background processing | All capture |
| Coordinate System Mismatch | Flipped images, wrong annotation position | Consistent coordinate system | Integration |

---

## Phase-Specific Checklist

### Permission Phase
- [ ] Use `CGRequestScreenCaptureAccess()` to prompt (not just check)
- [ ] Show "restart required" message after permission granted
- [ ] Handle Sequoia monthly re-prompts gracefully
- [ ] Test permission revocation and re-grant flow

### Cross-Hair UI Phase
- [ ] Use NSPanel for overlay, not SwiftUI overlay
- [ ] Configure `ignoresMouseEvents` correctly
- [ ] Test mouse drag across entire selection area
- [ ] Implement Escape key to cancel
- [ ] Test on multi-display setups

### Window Picker Phase
- [ ] Cache window thumbnails, refresh sparingly
- [ ] Use low frame rate (1-2 fps) for previews
- [ ] Handle fullscreen windows specially
- [ ] Exclude own app windows from list

### Capture Implementation Phase
- [ ] Use ScreenCaptureKit (SCScreenshotManager for single frames)
- [ ] Account for backingScaleFactor on Retina displays
- [ ] Exclude self window using SCContentFilter
- [ ] Convert coordinates correctly for multi-display
- [ ] Validate no memory leaks with Instruments

### Integration Phase
- [ ] Coordinate with existing AnnotationWindowController
- [ ] Verify coordinates match between capture and annotation
- [ ] Ensure async capture doesn't block main thread
- [ ] Test complete flow: capture -> annotate -> dispatch

---

## Sources Summary

### Official Apple Documentation
- [ScreenCaptureKit Documentation](https://developer.apple.com/documentation/screencapturekit/)
- [SCContentFilter Documentation](https://developer.apple.com/documentation/screencapturekit/sccontentfilter)
- [Capturing Screen Content in macOS](https://developer.apple.com/documentation/ScreenCaptureKit/capturing-screen-content-in-macos)
- [WWDC22 - Meet ScreenCaptureKit](https://developer.apple.com/videos/play/wwdc2022/10156/)
- [WWDC22 - Take ScreenCaptureKit to the Next Level](https://developer.apple.com/videos/play/wwdc2022/10155/)

### Developer Community & Issues
- [mac-screen-capture-permissions](https://github.com/karaggeorge/mac-screen-capture-permissions)
- [Alt-Tab macOS - Thumbnail Performance](https://github.com/lwouis/alt-tab-macos/issues/45)
- [Flameshot - Multi Monitor Issue](https://github.com/flameshot-org/flameshot/issues/1258)
- [Eternal Storms - Deconstructing macOS screencapture](https://blog.eternalstorms.at/2016/09/10/deconstructing-and-reimplementing-macos-screencapture-cli/)

### Technical Blogs
- [Nonstrict - ScreenCaptureKit on Sonoma](https://nonstrict.eu/blog/2023/a-look-at-screencapturekit-on-macos-sonoma/)
- [Fat Bob Man - Screen Recording Architecture](https://fatbobman.com/en/posts/screensage-from-pixel-to-meta)
- [SwiftUI Lab - Hosting+Representable Combo](https://swiftui-lab.com/a-powerful-combo/)

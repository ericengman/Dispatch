# Project Research Summary

**Project:** Dispatch v3.0 — Screenshot Capture
**Domain:** macOS screenshot capture and annotation for Claude Code workflow
**Researched:** 2026-02-09
**Confidence:** HIGH

## Executive Summary

Dispatch v3.0 aims to add quick screenshot capture to complement the existing iOS Simulator screenshot workflow. Research reveals a clear path: leverage native macOS APIs (`screencapture -i` for region selection, `SCContentSharingPicker` for window capture) rather than building custom UI, and reuse Dispatch's existing annotation infrastructure extensively. The key insight is that both capture methods require zero Screen Recording permission because they are user-initiated through system UI.

The recommended approach is a hybrid strategy: invoke the native `screencapture -i` command for cross-hair region selection (zero implementation overhead, native UX users already know), and use ScreenCaptureKit's `SCContentSharingPicker` for window capture (system-provided picker, no permission needed). After capture, feed the image into Dispatch's existing `AnnotationWindow` and annotation pipeline. This maximizes code reuse—the annotation subsystem (AnnotationViewModel, AnnotationCanvasView, AnnotationToolbar, AnnotationRenderer, SendQueueView) is already well-architected and source-agnostic.

Critical risks to mitigate: (1) Do NOT use CGWindowListCreateImage—it is deprecated in macOS 14 and removed in macOS 15, use ScreenCaptureKit instead; (2) For any overlay UI, use NSPanel not SwiftUI `.overlay()` modifier due to known sheet interaction bugs; (3) Screen Recording permission (if eventually needed) has a stale cache issue requiring app restart after grant.

## Key Findings

### Recommended Stack

The stack centers on native macOS APIs with minimal external dependencies.

**Core technologies:**
- `screencapture -i` (CLI): Region selection — native UX, zero implementation, no permission needed
- `SCContentSharingPicker` (ScreenCaptureKit): Window picker UI — system-provided, no Screen Recording permission
- `SCScreenshotManager` (ScreenCaptureKit): Capture API — modern replacement for deprecated CGWindowListCreateImage
- Existing annotation infrastructure: Views, services, models — direct reuse, already tested

**Not recommended:**
- CGWindowListCreateImage — deprecated macOS 14, removed macOS 15
- Custom cross-hair overlay — high complexity, `screencapture -i` provides this for free
- AVCaptureScreenInput — designed for video, overkill for screenshots

### Expected Features

**Must have (table stakes):**
- Region selection (crosshair) — native macOS behavior via `screencapture -i`
- Window capture — via SCContentSharingPicker
- Instant feedback — thumbnail after capture
- Escape to cancel — universal cancel mechanism
- Keyboard shortcuts — global hotkey to trigger capture

**Should have (differentiators):**
- Direct annotation pipeline — capture -> annotate -> send to Claude in one flow
- Simulator-aware capture — auto-detect iOS Simulator windows
- Session targeting — capture -> annotate -> send to specific Terminal session

**Defer (v2+):**
- Window thumbnails in picker (high complexity)
- Quick capture mode (skip annotation)
- Recent windows MRU list
- Video/GIF recording (scope creep, different product)
- Cloud upload/sharing (Dispatch sends to Claude, not the internet)
- Scrolling capture (complexity not worth it, Claude handles multiple screenshots)

### Architecture Approach

Dispatch already has a mature annotation system built for iOS Simulator screenshots. The new quick capture feature can leverage this existing infrastructure extensively—the annotation subsystem (AnnotationViewModel, AnnotationCanvasView, AnnotationToolbar, AnnotationRenderer) is source-agnostic and requires minimal modification. The key architectural decision is to extend the existing Screenshot model with a `CaptureSource` enum rather than creating parallel models.

**Major components:**
1. **ScreenshotCaptureService** — orchestrates capture modes (region via screencapture CLI, window via SCContentSharingPicker)
2. **WindowCaptureController** — wraps SCContentSharingPicker, handles delegate callbacks
3. **QuickCaptureStore** — transient in-memory storage for non-persisted captures
4. **Existing annotation infrastructure** — AnnotationWindow, AnnotationCanvasView, SendQueueView (reuse directly)

**Data flow:**
```
Capture (region/window) -> Screenshot model -> AnnotationWindow -> SendQueue -> EmbeddedTerminalService
```

### Critical Pitfalls

1. **CGWindowListCreateImage Deprecation** — Use ScreenCaptureKit (SCScreenshotManager) from the start. The legacy API is deprecated in macOS 14 and removed in macOS 15. All online code examples use the deprecated API.

2. **SwiftUI Overlay Sheet Bug** — For any capture overlay UI, use NSPanel not SwiftUI `.overlay()` modifier. SwiftUI overlays stop responding correctly when sheets are presented anywhere in the view hierarchy.

3. **Permission Stale Cache** — Screen Recording permission is cached at app launch. After user grants permission, show "restart required" message. Use `SCShareableContent` for better permission detection.

4. **Multi-Display Coordinate Confusion** — macOS uses global coordinates where (0,0) is bottom-left of primary display. Secondary displays can have negative coordinates. Use `NSScreen.convertRect(toScreen:)` for proper conversion.

5. **Retina Scale Factor Mismatch** — Screen coordinates are in points, capture APIs return pixels. Always multiply by `backingScaleFactor` when converting. Dispatch's existing AnnotationCanvasView already handles this—follow that pattern.

6. **Excluding Self Window** — The selection overlay or app windows appear in captured screenshots. With ScreenCaptureKit, use `SCContentFilter` to exclude by bundle identifier. Hide overlay before capture.

## Implications for Roadmap

Based on research, suggested phase structure:

### Phase 1: Region Capture via screencapture CLI
**Rationale:** Lowest implementation effort, highest user value. Uses native macOS `screencapture -i` command—zero UI code needed.
**Delivers:** Region selection capture -> annotation flow
**Addresses:** Region selection (table stakes), keyboard shortcut trigger
**Avoids:** Custom overlay complexity, permission issues (user-initiated = no permission needed)
**Estimate:** 1-2 days

### Phase 2: Window Capture via SCContentSharingPicker
**Rationale:** Builds on Phase 1 capture infrastructure. SCContentSharingPicker provides system UI—no custom picker needed.
**Delivers:** Window picker -> capture -> annotation flow
**Uses:** ScreenCaptureKit SCContentSharingPicker (macOS 14+)
**Implements:** WindowCaptureController wrapper
**Avoids:** Screen Recording permission (system picker is user-initiated)
**Estimate:** 2-3 days

### Phase 3: Annotation Pipeline Integration
**Rationale:** Wire capture outputs to existing annotation infrastructure. Low risk—existing code is well-tested.
**Delivers:** Captured screenshots flow into AnnotationWindow for markup and dispatch
**Reuses:** AnnotationWindow, AnnotationCanvasView, AnnotationToolbar, SendQueueView, AnnotationRenderer
**Addresses:** Direct annotation pipeline (differentiator)
**Estimate:** 1-2 days

### Phase 4: Sidebar Integration and UI Polish
**Rationale:** Add QuickCaptureSection to SkillsSidePanel. Recent captures strip. Keyboard shortcuts.
**Delivers:** Discoverable capture actions in sidebar, capture history
**Implements:** QuickCaptureSection, QuickCaptureStore
**Addresses:** Instant feedback, session targeting
**Estimate:** 2-3 days

### Phase Ordering Rationale

- **Region capture first:** Highest value-to-effort ratio. `screencapture -i` does all the hard work (multi-monitor, coordinate systems, Retina scaling).
- **Window capture second:** SCContentSharingPicker is similarly low-effort, but slightly more integration work than CLI command.
- **Annotation integration third:** Depends on capture infrastructure existing. Low risk because existing code is battle-tested.
- **UI polish last:** Sidebar integration and shortcuts are polish after core functionality works.

### Research Flags

Phases with standard patterns (skip research-phase):
- **Phase 1 (Region Capture):** Well-documented CLI, straightforward Process invocation
- **Phase 3 (Annotation Integration):** Existing codebase, just wiring
- **Phase 4 (UI Polish):** Standard SwiftUI patterns

Phases that may need attention during implementation:
- **Phase 2 (Window Capture):** SCContentSharingPicker delegate pattern needs careful implementation. Test picker presentation thoroughly.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | Official Apple documentation, WWDC sessions, verified deprecation status |
| Features | HIGH | Verified against CleanShot X, Shottr, native macOS behavior |
| Architecture | HIGH | Direct analysis of existing Dispatch codebase, clear reuse paths |
| Pitfalls | HIGH | Apple Developer Forums, GitHub issues, multiple sources corroborate |

**Overall confidence:** HIGH

### Gaps to Address

- **Multi-display testing:** Research covers the theory, but actual testing on multi-monitor setups needed during implementation
- **macOS 15 (Sequoia) monthly prompts:** If Screen Recording permission is eventually needed, UX for recurring prompts needs design consideration
- **SCContentSharingPicker edge cases:** Limited real-world documentation; may discover nuances during implementation

## Sources

### Primary (HIGH confidence)
- [ScreenCaptureKit | Apple Developer Documentation](https://developer.apple.com/documentation/screencapturekit/)
- [SCContentSharingPicker | Apple Developer Documentation](https://developer.apple.com/documentation/screencapturekit/sccontentsharingpicker)
- [What's new in ScreenCaptureKit - WWDC23](https://developer.apple.com/videos/play/wwdc2023/10136/)
- [screencapture Man Page - SS64](https://ss64.com/mac/screencapture.html)
- Existing Dispatch codebase analysis

### Secondary (MEDIUM confidence)
- [A look at ScreenCaptureKit on macOS Sonoma | Nonstrict](https://nonstrict.eu/blog/2023/a-look-at-screencapturekit-on-macos-sonoma/)
- [CGWindowListCreateImage -> ScreenCaptureKit Migration | Apple Developer Forums](https://developer.apple.com/forums/thread/740493)
- [CleanShot X Features](https://cleanshot.com/features) — competitive feature reference
- [Shottr](https://shottr.cc) — developer-focused screenshot tool reference

### Tertiary (LOW confidence)
- [Deconstructing and Reimplementing macOS' screencapture CLI | Eternal Storms](https://blog.eternalstorms.at/2016/09/10/deconstructing-and-reimplementing-macos-screencapture-cli/)
- [mac-screen-capture-permissions | GitHub](https://github.com/karaggeorge/mac-screen-capture-permissions)

---
*Research completed: 2026-02-09*
*Ready for roadmap: yes*

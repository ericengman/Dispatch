# Features Research: Screenshot Capture

**Domain:** macOS screenshot capture for Claude Code workflow
**Researched:** 2026-02-09
**Confidence:** HIGH (verified against CleanShot X, Shottr, native macOS)

## Table Stakes

Features users expect from any screenshot capture tool. Missing = product feels incomplete.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| **Region selection (crosshair)** | Native macOS behavior (Cmd+Shift+4). Users expect click-drag to select area. | Medium | Must match native feel: crosshair cursor, live dimension display |
| **Window capture** | Native macOS behavior (Cmd+Shift+4, Space). One-click to capture entire window. | Medium | Need window detection, highlight on hover |
| **Fullscreen capture** | Basic expectation (Cmd+Shift+3). Capture entire display. | Low | Simplest mode, good fallback |
| **Instant feedback** | All screenshot tools show thumbnail/preview immediately after capture | Low | Quick Access Overlay pattern (CleanShot X) or thumbnail in corner (native macOS) |
| **Escape to cancel** | Universal cancel mechanism during capture | Low | Critical for UX consistency |
| **Keyboard shortcuts** | Users expect hotkey to trigger capture without mouse | Low | Global hotkey registration (Dispatch already has this infrastructure) |
| **Copy to clipboard** | Option to copy instead of save to file | Low | Native macOS: hold Control to copy instead of save |
| **Retina/HiDPI support** | Modern Macs are all Retina. Screenshots must be pixel-accurate. | Low | Use proper scale factor handling |

## Differentiators

Features that make Dispatch unique for Claude Code workflows. Not universally expected, but add significant value.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| **Direct annotation pipeline** | Capture -> Annotate -> Send to Claude in one flow. No file management. | Medium | Dispatch already has annotation UI. Wire capture output directly to `AnnotationWindow`. |
| **Live window picker with app filtering** | Show list of capturable windows grouped by app. Click to capture. | Medium | Better than native Space-to-cycle-windows. Show simulator windows prominently. |
| **Simulator-aware capture** | Auto-detect iOS Simulator windows. Show device frame info. | Low | Builds on existing `ScreenshotWatcherService` simulator detection. Capture any simulator, not just latest screenshot. |
| **Recent windows list** | Quick re-capture of recently captured windows | Low | Track window IDs, show MRU list. Developer workflow: capture same window repeatedly during iteration. |
| **Session targeting** | Capture -> Annotate -> Send to specific Terminal session | Low | Leverage existing session management. Differentiator over standalone screenshot tools. |
| **Quick capture mode** | Hotkey -> Capture -> Instant send (skip annotation for simple screenshots) | Low | Power user feature. Option to bypass annotation for "just show Claude this" cases. |
| **Window thumbnails in picker** | Show live preview of windows before capture | High | CGWindowListCreateImage for thumbnails. Adds visual context to window selection. |

## Anti-Features

Features to explicitly NOT build. Common in other tools but wrong for Dispatch's use case.

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| **Cloud upload/sharing** | Dispatch sends to Claude, not to the internet. Adding cloud adds complexity and privacy concerns. | Keep screenshots local. The "share" action is sending to Claude. |
| **Video/GIF recording** | Scope creep. CleanShot X, Shottr do this, but Dispatch is for static screenshots to Claude. | Stick to static capture. Video is a different product. |
| **Scrolling capture** | High complexity (requires injecting scroll events, stitching images). Claude can handle multiple screenshots. | If content is long, capture multiple screenshots and annotate each. |
| **OCR/text extraction** | Claude IS the OCR. Sending screenshot to Claude extracts text better than any local OCR. | Just capture and send. Claude handles text extraction. |
| **Background beautification** | CleanShot X adds backgrounds, shadows, etc. Dispatch screenshots are for debugging/development, not social media. | Raw captures only. Annotation adds context; beautification adds noise. |
| **File management/organization** | Dispatch already has history via `PromptHistory`. Screenshots are ephemeral inputs to Claude conversations. | Let macOS handle file storage. Dispatch just needs capture -> annotate -> send. |
| **Timer/delayed capture** | Rarely needed for development workflows. Adds UI complexity. | If needed later, simple 3-5 second timer. Not V1. |
| **Color picker/measurement tools** | Shottr excels here for designers. Dispatch users are developers talking to Claude, not measuring pixels. | Leave to dedicated tools like Shottr. Focus on capture-annotate-send. |
| **Floating screenshot pin** | CleanShot X "Always on top" feature. Useful for reference, but Dispatch's annotation window already provides this context. | Use annotation window as the reference view. |

## Reference Apps

### CleanShot X (Premium, $29+)
**What they do well:**
- Quick Access Overlay: Thumbnail appears in corner after capture with one-click actions (Copy, Save, Annotate, Cloud)
- Capture modes are exhaustive: Area, Window, Fullscreen, Scrolling, Self-timer, Freeze screen
- Crosshair with dimension display and magnifier for precision
- Background tool for social media beautification
- Annotation is robust: arrows (4 styles), shapes, text, blur, highlight, spotlight, step counters

**What Dispatch can learn:**
- Quick Access Overlay pattern is excellent UX. After capture, show thumbnail with "Annotate" and "Send" actions.
- Crosshair with dimension display is expected behavior
- Capture modes accessible via consistent keyboard shortcuts

**What to skip:**
- Cloud upload, scrolling capture, video recording, background beautification
- 4 arrow styles (one is enough)
- Step counters, spotlight (over-engineering for our use case)

### Shottr (Free / $12 one-time)
**What they do well:**
- Blazing fast (17ms capture on Apple Silicon)
- Developer/designer focus: ruler, color picker, measurements, color contrast checker
- Scrolling capture that actually works
- Lightweight (2.3MB)
- Repeat area screenshot (retake same region)

**What Dispatch can learn:**
- Speed matters. Capture should feel instant.
- Simple annotation tools are sufficient (arrows, rectangles, text)
- "Repeat area" feature valuable for iterative development

**What to skip:**
- Color picker, measurements, rulers, contrast checker (designer tools, not debugging tools)
- Scrolling capture (complexity not worth it)
- S3 upload, URL schemes

### Native macOS Screenshot (Free, built-in)
**What they do well:**
- Consistent, reliable, zero learning curve
- Cmd+Shift+3/4/5 muscle memory (since classic Mac OS)
- Thumbnail in corner with markup access
- Window capture with Space bar toggle
- Hold Control to copy to clipboard instead of file

**What Dispatch can learn:**
- Match native keyboard conventions where possible
- Crosshair behavior, window highlighting, Escape to cancel are table stakes
- Thumbnail feedback pattern users expect

**What to skip:**
- Don't try to replace macOS screenshots entirely. Extend for Claude workflow.

## Integration with Existing Dispatch Features

### Existing Annotation Infrastructure
Dispatch already has annotation tools:
- **AnnotationTypes:** freehand, arrow, rectangle, text
- **AnnotationColors:** red, orange, yellow, green, blue, white, black
- **AnnotationToolbar:** tool selection, color picker, undo/redo, zoom
- **AnnotationCanvasView:** drawing surface
- **AnnotationWindow:** standalone window for markup
- **AnnotationRenderer:** NSImage rendering with annotations

**Integration Point:** Wire capture output directly to `AnnotationWindow` with `AnnotatedImage` struct.

### Existing Screenshot Model
```swift
struct Screenshot {
    // Already supports representing captured images
    var displayLabel: String
    // Can be extended for capture metadata
}
```

### Existing Hotkey Infrastructure
`HotkeyManager` already handles global hotkey registration. Add capture mode hotkeys alongside existing prompt dispatch hotkey.

### Existing Session Targeting
Session management can be leveraged for "capture -> annotate -> send to session X" workflow.

## Feature Dependencies

```
                    +-----------------+
                    | Global Hotkey   |  (Existing in Dispatch)
                    +--------+--------+
                             |
                             v
              +--------------+---------------+
              |                              |
    +---------v---------+        +-----------v----------+
    | Region Selection  |        | Window Picker        |
    | (Crosshair mode)  |        | (List + thumbnails)  |
    +--------+----------+        +-----------+----------+
              |                              |
              +-------------+----------------+
                            |
                            v
                  +---------+----------+
                  | Capture Engine     |
                  | (CGWindowList*)    |
                  +---------+----------+
                            |
              +-------------+-------------+
              |                           |
    +---------v---------+       +---------v---------+
    | Quick Send        |       | Annotation UI     | (Existing)
    | (Skip annotation) |       | Markup -> Send    |
    +-------------------+       +-------------------+
```

**Key APIs:**
- `CGWindowListCopyWindowInfo` - enumerate windows
- `CGWindowListCreateImage` - capture window/region
- `NSScreen.screens` - display info for fullscreen
- `NSEvent.addGlobalMonitorForEvents` - mouse tracking during selection

## MVP Recommendation

For v3.0 MVP, prioritize:

1. **Region selection (crosshair)** - Table stakes, matches native UX
2. **Window capture with picker** - Better than native for selecting specific windows
3. **Direct annotation pipeline** - Key differentiator: capture -> annotate -> send
4. **Simulator window awareness** - Builds on existing feature, high value for iOS dev workflow

Defer to post-MVP:
- Window thumbnails in picker: High complexity, picker without thumbnails is functional
- Quick capture mode: Power user feature, annotation flow works for all cases
- Recent windows list: Nice-to-have, not critical for launch
- Fullscreen capture: Lower priority than region/window, easy to add later

## Complexity Estimates

| Feature | Effort | Risk | Notes |
|---------|--------|------|-------|
| Crosshair region selection | 2-3 days | Low | Well-documented APIs, clear UX pattern |
| Window capture with picker | 2-3 days | Low | CGWindowListCopyWindowInfo is straightforward |
| Annotation integration | 1 day | Low | Existing infrastructure, wire-up only |
| Simulator awareness | 1 day | Low | Extend existing detection code |
| Window thumbnails | 3-5 days | Medium | Performance with many windows, memory |
| Quick capture mode | 1 day | Low | Bypass existing flow |
| Recent windows MRU | 1 day | Low | Simple list tracking |

**Total MVP Estimate:** 6-8 days for core features

## Keyboard Shortcuts (Proposed)

| Shortcut | Action | Rationale |
|----------|--------|-----------|
| Cmd+Shift+S | Open capture mode (region) | "S" for screenshot, avoids conflict with Cmd+Shift+3/4/5 |
| Cmd+Shift+W | Open window picker | "W" for window |
| Escape | Cancel capture | Universal cancel |
| Space | Toggle region/window mode (during capture) | Matches native macOS |

## Sources

- [CleanShot X Features](https://cleanshot.com/features) - Full feature list for premium screenshot tool
- [Shottr](https://shottr.cc) - Developer-focused screenshot tool features
- [Apple Support - Take a screenshot on Mac](https://support.apple.com/en-us/102646) - Native macOS screenshot behavior
- [Best CleanShot X Alternative in 2026](https://www.screensnap.pro/blog/best-cleanshot-x-alternative-in-2026-plus-4-more-options-for-mac-users) - Comparison of screenshot tools
- [Shottr vs CleanShot X](https://setapp.com/app-reviews/cleanshot-x-vs-shottr) - Feature comparison
- [Best Screenshot Tool for Mac 2026](https://www.techradar.com/pro/best-screenshot-tool-for-mac) - Market overview
- [10 Best Mac Screenshot Apps 2026](https://storychief.io/blog/best-screenshot-tool-for-mac) - Feature expectations

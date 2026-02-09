# Architecture Research: Screenshot Capture Integration (v3.0)

**Domain:** Quick screenshot capture integration for Dispatch macOS app
**Researched:** 2026-02-09
**Confidence:** HIGH (analysis based on existing codebase examination)

## Executive Summary

Dispatch already has a mature annotation system built for iOS Simulator screenshots (SimulatorRun/Screenshot model). The new quick capture feature can leverage this existing infrastructure extensively, with new components focused on capture mechanics (region selection, window capture) and integration points (sidebar actions, session targeting).

The annotation subsystem (AnnotationViewModel, AnnotationCanvasView, AnnotationToolbar, AnnotationRenderer, SendQueueView) is well-architected and can be reused with minimal modification by generalizing the Screenshot model to support multiple capture sources.

**Key Architectural Decision:** Extend existing Screenshot model with CaptureSource enum rather than creating parallel models. This maximizes code reuse and allows annotation views to work with any screenshot source.

---

## Existing Components to Reuse

### Models (Direct Reuse)

| Component | Location | Reuse Strategy |
|-----------|----------|----------------|
| `AnnotationTypes.swift` | Models/ | Direct reuse - AnnotationType, AnnotationColor, Annotation, AnnotatedImage, AnnotationAction are source-agnostic |
| `Screenshot.swift` | Models/ | Extend with `CaptureSource` enum (simulator, region, window, fullscreen) |

### Services (Direct Reuse)

| Component | Location | Reuse Strategy |
|-----------|----------|----------------|
| `AnnotationRenderer.swift` | Services/ | Direct reuse - renders any AnnotatedImage to NSImage |
| `EmbeddedTerminalService.swift` | Services/ | Direct reuse - dispatches prompts to terminal sessions |

### Views (Direct Reuse)

| Component | Location | Reuse Strategy |
|-----------|----------|----------------|
| `AnnotationCanvasView.swift` | Views/Simulator/ | Direct reuse - works with any AnnotatedImage |
| `AnnotationToolbar.swift` | Views/Simulator/ | Direct reuse - tool/color selection |
| `SendQueueView.swift` | Views/Simulator/ | Direct reuse - displays queued AnnotatedImage items |
| `BottomStripView.swift` | Views/Simulator/ | Direct reuse - thumbnail strip for multi-screenshot selection |

### ViewModels (Partial Reuse)

| Component | Location | Reuse Strategy |
|-----------|----------|----------------|
| `AnnotationViewModel` (in SimulatorViewModel.swift) | ViewModels/ | Direct reuse - manages annotation state, queue, dispatch |

### Patterns to Follow

The existing architecture demonstrates clear patterns:

1. **Service Singletons** - `AnnotationRenderer.shared`, `EmbeddedTerminalService.shared`
2. **Environment Object Injection** - Views receive AnnotationViewModel via @EnvironmentObject
3. **Async Rendering** - Background queue for image processing
4. **Clipboard-Based Image Transfer** - Images copied to clipboard, prompt dispatched separately

---

## New Components Needed

### 1. ScreenshotCaptureService (Service Layer)

**Purpose:** Unified API for all capture methods (region, window, fullscreen)

**Location:** `Dispatch/Services/ScreenshotCaptureService.swift`

```swift
@MainActor
final class ScreenshotCaptureService {
    static let shared = ScreenshotCaptureService()

    enum CaptureMode {
        case region(CGRect)
        case window(CGWindowID)
        case fullScreen
    }

    func capture(mode: CaptureMode) async throws -> Screenshot
    func startRegionSelection() -> AsyncStream<RegionSelectionState>
    func getWindowList() -> [WindowInfo]
    func captureWindowPreview(windowId: CGWindowID) -> NSImage?
}
```

**Key APIs:**
- `CGWindowListCopyWindowInfo` - Enumerate windows
- `CGWindowListCreateImage` - Capture specific window or screen region

### 2. RegionSelectionOverlay (View Layer)

**Purpose:** Full-screen crosshair overlay for region selection

**Location:** `Dispatch/Views/Screenshot/RegionSelectionOverlay.swift`

```swift
struct RegionSelectionOverlay: View {
    @Binding var selectedRegion: CGRect?
    let onComplete: (CGRect) -> Void
    let onCancel: () -> Void

    // Full-screen transparent window with:
    // - Crosshair cursor
    // - Drag-to-select rectangle
    // - Dimmed area outside selection
    // - ESC to cancel
}
```

**Implementation Notes:**
- Requires separate NSWindow with `.borderless` style
- Level: `.screenSaver` or `.floating` to appear above all windows
- Uses `NSEvent.addGlobalMonitorForEvents` for mouse tracking

### 3. WindowPickerView (View Layer)

**Purpose:** Grid of window thumbnails for selection

**Location:** `Dispatch/Views/Screenshot/WindowPickerView.swift`

```swift
struct WindowPickerView: View {
    @StateObject var captureService = ScreenshotCaptureService.shared
    let onSelect: (CGWindowID) -> Void

    // Grid of live window previews
    // Grouped by application
    // Hover to highlight, click to capture
}
```

**Implementation Notes:**
- Use `CGWindowListCreateImage` with small rect for thumbnails
- Refresh on timer (2-3 second interval) for "live" preview
- Exclude Dispatch's own windows from list

### 4. QuickCaptureSection (Sidebar Integration)

**Purpose:** New section in SkillsSidePanel for capture actions

**Location:** `Dispatch/Views/Screenshot/QuickCaptureSection.swift`

```swift
struct QuickCaptureSection: View {
    @Binding var selectedScreenshot: Screenshot?

    // Buttons:
    // - "Capture Region" -> triggers RegionSelectionOverlay
    // - "Capture Window" -> shows WindowPickerView sheet
    // - "Capture Screen" -> immediate full-screen capture

    // Recent captures strip (horizontal scroll)
}
```

### 5. QuickCaptureStore (Transient State)

**Purpose:** Manage captures not associated with SimulatorRun

**Location:** `Dispatch/ViewModels/QuickCaptureStore.swift`

```swift
@Observable
@MainActor
final class QuickCaptureStore {
    var captures: [Screenshot] = []  // In-memory, not persisted
    var selectedCapture: Screenshot?

    func add(_ screenshot: Screenshot)
    func remove(_ screenshot: Screenshot)
    func clearAll()
}
```

**Design Decision:** Quick captures are transient by default (not persisted to SwiftData). User can explicitly save to a project if desired.

---

## Integration Points

### 1. Sidebar Integration

**Location:** `SkillsSidePanel.swift`

**Changes:**
- Add new section "Quick Capture" above "Screenshot Runs"
- Contains capture action buttons + recent captures strip
- Section follows existing `SectionHeaderBar` pattern

```
SkillsSidePanel
+-- Quick Capture (NEW)
|   +-- Action buttons (Region, Window, Screen)
|   +-- Recent captures strip
+-- Screenshot Runs (existing)
+-- Memory (existing)
+-- Skills (existing)
```

### 2. MainView State

**Location:** `MainView.swift`

**Changes:**
- Add `@State private var selectedCapture: Screenshot?`
- Route to annotation view when capture selected (similar to selectedRun)
- Add keyboard shortcuts for capture actions

### 3. NavigationSelection Extension

**Location:** `MainView.swift`

**Changes:**
- Add new case: `.quickCapture(UUID)` to NavigationSelection enum
- Enables deep-linking to specific captures

### 4. AnnotationViewModel Generalization

**Location:** `SimulatorViewModel.swift` (AnnotationViewModel class)

**Current:** Works with Screenshot from SimulatorRun
**Change:** Works with any Screenshot (already supports this, just needs QuickCaptureStore integration)

### 5. Session Targeting

**Current Flow:**
```
AnnotationWindow -> EmbeddedTerminalService.shared.dispatchPrompt(prompt)
```
Dispatches to the active session.

**Enhanced Flow:**
```
AnnotationWindow -> Session picker (optional) -> dispatchPrompt(prompt, to: sessionId)
```
Allow targeting a specific terminal session from the queue.

**Implementation:**
- Add session picker dropdown in dispatch section
- Use `TerminalSessionManager.shared.sessions` for options
- Pass sessionId to `EmbeddedTerminalService.dispatchPrompt(_:to:)`

---

## Data Flow

### Capture -> Annotate -> Queue -> Dispatch

```
+------------------+
|  Capture Source  |
+------------------+
| - Region select  |
| - Window pick    |
| - Full screen    |
| - Simulator run  |
+--------+---------+
         |
         v
+------------------+
|   Screenshot     |
|   (Model)        |
+------------------+
| id: UUID         |
| filePath: String |
| captureIndex     |
| source: enum     | <-- NEW: CaptureSource
+--------+---------+
         |
         v
+------------------+
| AnnotatedImage   |
|   (In-Memory)    |
+------------------+
| screenshot       |
| annotations: []  |
| cropRect?        |
+--------+---------+
         |
         v
+------------------+
| AnnotationVM     |
| .sendQueue       |
+------------------+
| [AnnotatedImage] |
| promptText       |
+--------+---------+
         |
         +--- copyToClipboard() --> NSPasteboard
         |
         +--- dispatchPrompt(to:) --> EmbeddedTerminalService
                                              |
                                              v
                                     Terminal Session
```

### Temporary File Storage

Quick captures need temporary storage for image files:

```
Location: ~/Library/Application Support/Dispatch/QuickCaptures/
File naming: {UUID}.png
Cleanup: On app launch, delete files older than 24 hours
```

---

## Refactoring Plan

### Phase 1: Prepare Foundation (Low Risk)

1. **Extract CaptureSource enum** - Add to Screenshot model without breaking existing code
   ```swift
   enum CaptureSource: String, Codable {
       case simulator
       case region
       case window
       case fullScreen
   }
   ```

2. **Add optional source field to Screenshot** - Default to `.simulator` for backwards compatibility

3. **Move AnnotationViewModel to own file** - Currently embedded in SimulatorViewModel.swift

### Phase 2: Capture Infrastructure (Medium Risk)

4. **Create ScreenshotCaptureService** - Core capture logic using CGWindowList APIs

5. **Create QuickCaptureStore** - Transient storage for non-persisted captures

6. **Create temp file management** - Storage location, cleanup logic

### Phase 3: UI Components (Low Risk)

7. **Create RegionSelectionOverlay** - Full-screen selection window

8. **Create WindowPickerView** - Window grid with live previews

9. **Create QuickCaptureSection** - Sidebar integration

### Phase 4: Integration (Medium Risk)

10. **Update MainView** - State management for quick captures

11. **Update SkillsSidePanel** - Add new section

12. **Add keyboard shortcuts** - Global capture hotkeys

### Phase 5: Session Targeting (Low Risk)

13. **Add session picker to annotation views** - Target specific terminal

14. **Update dispatch flow** - Route to selected session

---

## Suggested Build Order

Based on dependencies and risk, recommend this phase sequence:

### Phase 1: Core Capture Service
**Rationale:** Foundation for all capture features. No UI changes, testable in isolation.
- ScreenshotCaptureService
- Temp file storage
- CaptureSource enum extension to Screenshot

**Files to Create:**
- `Services/ScreenshotCaptureService.swift`

**Files to Modify:**
- `Models/Screenshot.swift` (add CaptureSource enum)

### Phase 2: Region Selection
**Rationale:** Most common use case, exercises capture service.
- RegionSelectionOverlay (full-screen window)
- RegionSelectionWindow (NSWindow controller)
- Keyboard shortcut trigger

**Files to Create:**
- `Views/Screenshot/RegionSelectionOverlay.swift`
- `Views/Screenshot/RegionSelectionWindow.swift`

### Phase 3: Sidebar Integration
**Rationale:** Makes captures accessible without breaking existing flows.
- QuickCaptureSection
- QuickCaptureStore
- Update SkillsSidePanel

**Files to Create:**
- `Views/Screenshot/QuickCaptureSection.swift`
- `ViewModels/QuickCaptureStore.swift`

**Files to Modify:**
- `Views/Skills/SkillsSidePanel.swift`
- `Views/MainView.swift`

### Phase 4: Window Capture
**Rationale:** Builds on capture service, adds complexity of window enumeration.
- WindowPickerView
- WindowInfo model
- Live preview refresh

**Files to Create:**
- `Views/Screenshot/WindowPickerView.swift`
- `Models/WindowInfo.swift`

### Phase 5: Session Targeting
**Rationale:** Enhancement to existing dispatch, independent of capture work.
- Session picker in annotation views
- Dispatch routing

**Files to Modify:**
- `Views/Simulator/RunDetailView.swift`
- `Views/Simulator/AnnotationWindow.swift`

### Phase 6: Polish
- Keyboard shortcuts for all capture modes
- Hotkey configuration in settings
- Cleanup old temp files on launch

**Files to Modify:**
- `Services/HotkeyManager.swift`
- `Views/Settings/SettingsView.swift`

---

## Technical Considerations

### Permissions Required

| Permission | API | When Requested |
|------------|-----|----------------|
| Screen Recording | CGWindowListCreateImage | First window capture |

**Notes:**
- Screen Recording permission is already commonly granted for macOS productivity apps
- If denied, show clear error message with link to System Settings
- Region capture on own display may work without permission (verify during implementation)

### Performance

| Concern | Mitigation |
|---------|------------|
| Window preview refresh | Throttle to 2-3 second intervals |
| Large captures | Resize before storing (max 4K) |
| Memory for annotations | Annotations are lightweight structs |
| Clipboard size | Render at capture resolution, not retina 2x |

### Window Enumeration Filtering

When building window list, filter out:
- Dispatch's own windows (`kCGWindowOwnerPID` == current process)
- Windows with zero size
- Desktop/Dock/SystemUIServer windows
- Windows below minimum size threshold (e.g., 50x50)

### CGWindowList API Notes

```swift
// Get all on-screen windows
let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID)

// Capture specific window
let windowImage = CGWindowListCreateImage(
    .null,  // Capture bounds from window
    .optionIncludingWindow,
    windowID,
    [.boundsIgnoreFraming]
)

// Capture screen region
let regionImage = CGWindowListCreateImage(
    rect,
    .optionOnScreenBelowWindow,
    kCGNullWindowID,
    []
)
```

---

## Component Relationships

```
+----------------------------------+
|           MainView               |
+----------------------------------+
|  @State selectedCapture          |
|  @State selectedRun              |
+--+-------------------------------+
   |
   |  NavigationSplitView
   |
   +---> SkillsSidePanel
   |     +-- QuickCaptureSection (NEW)
   |     |   +-- CaptureActionButtons
   |     |   +-- RecentCapturesStrip
   |     +-- ScreenshotRunsSection
   |     +-- MemorySection
   |     +-- SkillsSection
   |
   +---> ContentArea
         +-- if selectedCapture/selectedRun
         |   +-- RunDetailView / CaptureDetailView
         |       +-- AnnotationCanvasView
         |       +-- AnnotationToolbar
         |       +-- SendQueueView
         |       +-- SessionPicker (NEW)
         +-- else
             +-- MultiSessionTerminalView
```

---

## Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Screen Recording permission denied | Medium | Blocks feature | Clear error message, link to System Settings |
| Full-screen app capture complexity | Low | Poor UX | Document as known limitation, suggest Region capture |
| Window list stale | Medium | Wrong window captured | Refresh list on open, show timestamps |
| Memory pressure with many captures | Low | Crash | Limit QuickCaptureStore to 20 items |
| Region selection overlay interferes with other apps | Medium | UX issue | ESC to cancel, clear visual feedback |

---

## Open Questions for Phase Research

1. **Region selection window management:** Should use separate NSWindowController or SwiftUI Window scene?
2. **Keyboard shortcut conflicts:** Check if proposed shortcuts (Cmd+Shift+4, etc.) conflict with system
3. **Multi-display capture:** How to handle region selection across multiple displays?
4. **Retina scaling:** Should captures be at display scale or 1x?

---

## Sources

- Existing Dispatch codebase analysis (HIGH confidence)
- Apple CGWindowList documentation
- Apple NSWindow documentation for overlay windows

**Files Analyzed:**
- `/Users/eric/Dispatch/Dispatch/Models/Screenshot.swift`
- `/Users/eric/Dispatch/Dispatch/Models/AnnotationTypes.swift`
- `/Users/eric/Dispatch/Dispatch/Views/Simulator/AnnotationCanvasView.swift`
- `/Users/eric/Dispatch/Dispatch/Views/Simulator/AnnotationToolbar.swift`
- `/Users/eric/Dispatch/Dispatch/Views/Simulator/SendQueueView.swift`
- `/Users/eric/Dispatch/Dispatch/Views/Simulator/BottomStripView.swift`
- `/Users/eric/Dispatch/Dispatch/Views/Simulator/RunDetailView.swift`
- `/Users/eric/Dispatch/Dispatch/Views/Simulator/AnnotationWindow.swift`
- `/Users/eric/Dispatch/Dispatch/Services/AnnotationRenderer.swift`
- `/Users/eric/Dispatch/Dispatch/Services/EmbeddedTerminalService.swift`
- `/Users/eric/Dispatch/Dispatch/Services/TerminalSessionManager.swift`
- `/Users/eric/Dispatch/Dispatch/ViewModels/SimulatorViewModel.swift`
- `/Users/eric/Dispatch/Dispatch/ViewModels/QueueViewModel.swift`
- `/Users/eric/Dispatch/Dispatch/Views/MainView.swift`
- `/Users/eric/Dispatch/Dispatch/Views/Sidebar/SidebarView.swift`
- `/Users/eric/Dispatch/Dispatch/Views/Skills/SkillsSidePanel.swift`

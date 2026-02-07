# TODO: Simulator Screenshot Review Feature

## Phase 1: Foundation ✅ COMPLETE

### Data Models
- [x] Create `SimulatorRun` SwiftData model with project relationship → `Dispatch/Models/SimulatorRun.swift`
- [x] Create `Screenshot` SwiftData model with run relationship → `Dispatch/Models/Screenshot.swift`
- [x] Add `SimulatorRun` and `Screenshot` to model container in `DispatchApp.swift`
- [x] Create `AnnotatedImage` struct (non-persisted) → `Dispatch/Models/AnnotationTypes.swift`
- [x] Create `Annotation` struct with type, points, color → `Dispatch/Models/AnnotationTypes.swift`
- [x] Create `AnnotationType` enum (freehand, arrow, rectangle, text) → `Dispatch/Models/AnnotationTypes.swift`

### Services
- [x] Create `ScreenshotWatcherService` using `FileManager` and `DispatchSource` → `Dispatch/Services/ScreenshotWatcherService.swift`
- [x] Implement directory watching for screenshot folder
- [x] Implement run detection and grouping logic
- [x] Create `AnnotationRenderer` for drawing annotations on images → `Dispatch/Services/AnnotationRenderer.swift`
- [x] Implement undo/redo stack in renderer → `AnnotationUndoManager` class
- [x] Implement auto-cleanup: keep only latest 10 runs per project

### HookServer Endpoints
- [x] Add `GET /screenshots/location` endpoint to return save path
- [x] Add `POST /screenshots/run` endpoint to create new run
- [x] Add `POST /screenshots/complete` endpoint to mark run done
- [x] Update `HookServer.swift` with new routes

---

## Phase 2: Core Views ✅ COMPLETE

### Project Tab Integration
- [x] Add `SimulatorRunsStripView` to project detail area → `Dispatch/Views/Simulator/SimulatorRunsStripView.swift`
- [x] Create horizontal scrollable card strip for runs
- [x] Show run cards with name, timestamp, thumbnail preview
- [x] Implement tap on card to open run detail/annotation window

### SimulatorRunCard
- [x] Create card component with run metadata → in `SimulatorRunsStripView.swift`
- [x] Show first screenshot as thumbnail
- [x] Display run name and screenshot count
- [x] Add subtle delete option (context menu or swipe)

### ScreenshotStripView (within run detail)
- [x] Create horizontal `ScrollView` with `LazyHStack` → `Dispatch/Views/Simulator/ScreenshotStripView.swift`
- [x] Implement `ScreenshotThumbnailView` component → in `ScreenshotStripView.swift`
- [x] Add visible/hidden state toggle
- [x] Implement collapsed state for hidden screenshots (~8px width)
- [x] Add selection ring styling
- [x] Implement double-tap gesture to open annotation window

### Keyboard Navigation
- [x] Add `←` / `→` arrow key handlers for navigation
- [x] Add `Space` key handler for hide toggle
- [x] Add `Enter` key handler to open annotation window
- [x] Track focus state for keyboard navigation

### ViewModels Created
- [x] `SimulatorViewModel` → `Dispatch/ViewModels/SimulatorViewModel.swift`
- [x] `AnnotationViewModel` → in `SimulatorViewModel.swift`

---

## Phase 3: Annotation Window ✅ COMPLETE

### Window Setup
- [x] Create `AnnotationWindow` as separate `Window` scene → `Dispatch/Views/Simulator/AnnotationWindow.swift`
- [x] Implement window state management (open/close) via `AnnotationWindowController`
- [x] Pass selected screenshot to window
- [x] Set minimum window size (1000x700)

### Layout Structure (Implemented)
```
┌────────────────────────────────┬──────────────────────────┐
│  Main Canvas                   │  [Send Queue - HScroll]  │
│  ┌──────────────────────────┐  │  [img1] [img2] [img3]    │
│  │                          │  ├──────────────────────────┤
│  │   Active Image           │  │  Prompt Input            │
│  │   with Annotations       │  │  ┌────────────────────┐  │
│  │                          │  │  │                    │  │
│  └──────────────────────────┘  │  │                    │  │
│  [Tools: Crop|Draw|Arrow|...]  │  │                    │  │
│                                │  └────────────────────┘  │
│                                │  [Dispatch Button]       │
├────────────────────────────────┴──────────────────────────┤
│  All Screenshots (read-only strip)                        │
│  [thumb1] [thumb2] [thumb3] [thumb4] [thumb5] ...  →     │
└───────────────────────────────────────────────────────────┘
```

### AnnotationCanvasView (Left Panel)
- [x] Create canvas with `Canvas` view for drawing → `Dispatch/Views/Simulator/AnnotationCanvasView.swift`
- [x] Implement image display with aspect-fit
- [x] Add zoom (magnify gesture) and pan support (option+drag)
- [x] Track current mouse/touch position for drawing

### Right Panel Layout
- [x] Create vertical stack: send queue (top) → prompt input (bottom)
- [x] Send queue as horizontal scroll above prompt → `Dispatch/Views/Simulator/SendQueueView.swift`
- [x] Prompt input with dispatch button below

### Annotation Tools
- [x] Create `AnnotationToolbar` with tool buttons → `Dispatch/Views/Simulator/AnnotationToolbar.swift`
- [x] Implement crop tool (drag rectangle selection) with overlay
- [x] Implement freehand draw tool
- [x] Implement arrow tool (start point → end point) with arrowhead
- [x] Implement rectangle tool
- [x] Implement text tool placeholder (tap to position)
- [x] Add color picker (7 preset colors: red, orange, yellow, green, blue, white, black)

### Crop Behavior
- [x] Show crop overlay with handles and grid lines
- [x] Apply/Cancel buttons on crop overlay
- [x] Auto-add cropped/annotated image to send queue

### Undo/Redo
- [x] Implement action history in AnnotationViewModel
- [x] Add ⌘Z undo shortcut
- [x] Add ⌘⇧Z redo shortcut
- [x] Undo/redo buttons in toolbar

### Keyboard Shortcuts (Annotation Window)
- [x] `C` - Crop tool
- [x] `D` - Draw tool
- [x] `A` - Arrow tool
- [x] `R` - Rectangle tool
- [x] `T` - Text tool
- [x] `1-7` - Color selection
- [x] `Esc` - Close window
- [x] `⌘⏎` - Dispatch (via button)

### Integration
- [x] Integrated with SimulatorRunsStripView (tap run card to open)
- [x] Integrated with MainView (runs strip shows above prompts for projects)
- [x] Bottom strip for all screenshots in run → `Dispatch/Views/Simulator/BottomStripView.swift`

---

## Phase 4: Send Queue & Dispatch ✅ COMPLETE

### SendQueueView (Horizontal Scroll - Right Panel Top)
- [x] Create horizontal scrollable list of queued images
- [x] Show thumbnail with annotations rendered
- [x] Add delete (×) button per item
- [x] Implement tap to load in main canvas
- [ ] Add drag to reorder (deferred)
- [x] Show empty state when queue is empty
- [x] Limit to 5 images max (Claude vision limit)

### BottomStripView (All Screenshots)
- [x] Create horizontal strip of all run screenshots
- [x] Tap selects and loads in main canvas (does NOT add to queue)
- [x] Only annotation/crop adds to send queue
- [x] Show which images are already queued (checkmark overlay)
- [x] Implement hidden state with eye toggle

### Prompt Input
- [x] Add multi-line `TextEditor` in right panel
- [x] Implement placeholder text
- [ ] Auto-focus on window open (deferred)

### Dispatch Integration
- [x] Use existing `DispatchButton` component
- [x] Prepare images for dispatch (rendered via AnnotationRenderer)
- [x] Format prompt with image attachments (max 5 images)
- [x] Clear send queue after successful dispatch
- [ ] Create `PromptHistory` entry with image references (deferred)

---

## Phase 5: Image Dispatch Protocol ✅ COMPLETE

### Clipboard + Paste Approach
- [x] Render annotated images to NSImage → `AnnotationRenderer.render()`
- [x] Copy images to clipboard (NSPasteboard) → `AnnotationRenderer.copyToClipboard()`
- [x] Research Terminal.app image paste behavior via AppleScript
- [x] Implement paste sequence: images first, then prompt text
- [ ] Handle image size limits (resize if needed) (deferred)
- [x] Enforce 5 image maximum per dispatch

### TerminalService Updates
- [x] Add `pasteFromClipboard` method using AppleScript paste command
- [x] Combine image paste with text dispatch
- [ ] Test with actual Claude Code session (requires live testing)

---

## Phase 6: Polish & Settings ✅ MOSTLY COMPLETE

### Settings Additions
- [x] Add screenshot directory setting to `AppSettings` → `screenshotDirectory`
- [x] Add default annotation color setting → `defaultAnnotationColor`
- [x] Add max runs per project setting → `maxRunsPerProject`
- [ ] Add settings UI in `SettingsView` (deferred)

### Auto-Cleanup
- [x] Implement cleanup on new run: delete oldest if >10 runs per project
- [x] Delete associated files when deleting run records
- [x] Run cleanup on app launch → `DispatchApp.runScreenshotCleanup()`

### Keyboard Shortcuts (Annotation Window)
- [x] `C` - Crop tool
- [x] `D` - Draw tool
- [x] `A` - Arrow tool
- [x] `R` - Rectangle tool
- [x] `T` - Text tool
- [x] `1-7` - Color selection
- [x] `Delete` - Remove from queue
- [x] `Esc` - Close window
- [x] `⌘⏎` - Dispatch

### Visual Polish
- [x] Add loading states for image processing (thumbnail loading)
- [x] Add animation for queue add/remove
- [x] Add animation for queued indicator
- [ ] Add tooltip hints for tools (deferred)
- [x] Style consistent with rest of Dispatch

### Error Handling
- [x] Handle missing files gracefully (screenshot.image returns nil)
- [x] Add logging throughout with `LoggingService`
- [ ] Show error when dispatch fails (deferred - errors logged)

---

## Phase 7: Claude Code Skill Update ✅ COMPLETE

### Skill Modifications
- [x] Update `test-feature` skill to check for Dispatch screenshot endpoint → `~/.claude/skills/test-feature/SKILL.md`
- [x] Update `explore-app` skill with same Dispatch integration → `~/.claude/skills/explore-app/SKILL.md`
- [x] Implement screenshot save to Dispatch-provided path (via `$DISPATCH_SCREENSHOT_PATH`)
- [x] Add run metadata (device, run name) to API call
- [x] Graceful fallback if Dispatch not running

### Skills Updated
Both skills now include:
1. **Dispatch Screenshot Integration** section with API documentation
2. **Phase 2 initialization** to create screenshot run via `POST /screenshots/run`
3. **Phase 8 cleanup** to complete run via `POST /screenshots/complete`
4. **Path guidance** for saving screenshots to Dispatch-provided location

### Testing
- [ ] Test end-to-end flow with live simulator
- [ ] Test with various image sizes
- [ ] Test batch dispatch with 5 images (max)
- [ ] Test keyboard-only workflow
- [ ] Test auto-cleanup with 11+ runs

---

## Summary of Constraints

| Constraint | Value |
|------------|-------|
| Max images per dispatch | 5 |
| Max runs per project | 10 (auto-delete oldest) |
| Image dispatch method | Copy-paste to Terminal |
| Annotation persistence | Per-session only |

---

## Future Enhancements (Post-v1)

- [ ] Comparison mode (side-by-side diff)
- [ ] Run notes/comments
- [ ] Filter by date range
- [ ] Search by run name
- [ ] Export run to folder/PDF
- [ ] Template prompts for common issues

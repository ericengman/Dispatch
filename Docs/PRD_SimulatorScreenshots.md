# PRD: Simulator Screenshot Review & Dispatch

## Overview

A feature in Dispatch for reviewing iOS Simulator screenshots captured during Claude Code testing sessions. Users can view, annotate, crop, and dispatch images with prompts back to Claude for feedback-driven iteration.

## Problem Statement

When Claude Code runs iOS apps in the simulator and captures screenshots for testing, users cannot see those screenshots to verify what Claude observed. This creates a blind spot in the development workflow where users must trust Claude's interpretation without visual confirmation.

## Solution

Add screenshot review capabilities to Dispatch that:
1. Displays screenshots organized by project and test run
2. Provides annotation and cropping tools for highlighting issues
3. Enables dispatching annotated images with prompts to Claude
4. Supports rapid keyboard-driven review workflows

---

## Core Features

### 1. Screenshot Browser (Per Project)

**Location:** Within each project tab, a horizontal scrollable strip of run cards appears above the skills section (icon: `camera.viewfinder`)

**Organization:**
- **By Project:** Screenshots grouped under their associated Dispatch project
- **By Run:** Within each project, grouped by test run (Claude labels each run)
- **Chronological:** Screenshots within a run shown in capture order

**Run Card Display:**
- Run name/label (provided by Claude)
- Timestamp
- Screenshot count
- First screenshot as thumbnail preview
- Tap to open run in Annotation Window

### 2. Screenshot Strip View

**Layout:** Horizontal scrollable HStack of screenshot thumbnails (within Annotation Window)

**Thumbnail States:**
- **Visible:** Full thumbnail with subtle border
- **Hidden:** Collapsed to thin vertical bar (same height, ~8px width) with `eye.slash` indicator
- **Selected:** Highlighted border, slight scale-up

**Interactions:**
- **Single tap:** Select/focus the screenshot, load in main canvas
- **Double tap:** Open in Annotation Window with full image
- **Tap eye icon:** Toggle hidden state
- **Keyboard navigation:**
  - `←` / `→`: Navigate between screenshots
  - `Space`: Toggle hidden state on current selection
  - `Enter`: Open in Annotation Window

### 3. Annotation Window

A separate window for detailed image review and prompt composition.

**Layout (2-column design):**

```
┌────────────────────────────────┬──────────────────────────┐
│  Main Canvas                   │  Send Queue (HScroll)    │
│  ┌──────────────────────────┐  │  [img1] [img2] [img3] →  │
│  │                          │  ├──────────────────────────┤
│  │   Active Image           │  │  Prompt Input            │
│  │   with Annotations       │  │  ┌────────────────────┐  │
│  │                          │  │  │ Describe the       │  │
│  │                          │  │  │ issue...           │  │
│  └──────────────────────────┘  │  │                    │  │
│  [Tools: Crop|Draw|Arrow|...]  │  └────────────────────┘  │
│                                │       [Dispatch Button]  │
├────────────────────────────────┴──────────────────────────┤
│  All Screenshots (read-only strip)                        │
│  [thumb1] [thumb2] [thumb3] [thumb4] [thumb5] ...  →     │
└───────────────────────────────────────────────────────────┘
```

**Right Panel Layout (top to bottom):**
1. Send Queue - horizontal scroll of images to dispatch
2. Prompt Input - multi-line text area
3. Dispatch Button

### 4. Annotation Tools

**Default Tool:** Square crop (drag to select region)

**Tool Palette:**
| Tool | Icon | Behavior |
|------|------|----------|
| Crop | `crop` | Drag rectangle to crop region |
| Draw | `pencil.tip` | Freehand drawing in selected color |
| Arrow | `arrow.up.right` | Draw directional arrows |
| Rectangle | `rectangle` | Draw hollow rectangles |
| Text | `character.textbox` | Add text labels |

**Color Options:** Red (default), Orange, Yellow, Green, Blue, White, Black

**Actions:**
- **Undo/Redo:** Standard ⌘Z / ⌘⇧Z
- **Clear annotations:** Reset to original image
- **Zoom:** Scroll/pinch to zoom, drag to pan when zoomed

### 5. Send Queue (Right Panel)

**Purpose:** Stage multiple annotated images for batch dispatch (max 5)

**Adding to Queue:**
- Tap screenshot in bottom strip → loads in canvas, does NOT add to queue
- Make crop/annotation → automatically adds to queue
- Drag from bottom strip to queue panel

**Queue Item Features:**
- Thumbnail preview showing annotations
- Click to load in main canvas for editing
- Delete button (×) to remove from queue
- Drag to reorder

**Visual Distinction:**
- Bottom strip: All screenshots from run (reference only, selection loads in canvas)
- Right panel queue: Only images that will be sent to Claude

### 6. Prompt Composition

**Input Field:** Multi-line text area with placeholder "Describe the issue or ask Claude to fix..."

**Auto-placeholders (optional):**
- `{{images}}` - Replaced with image references
- `{{run_name}}` - Current run label
- `{{project}}` - Project name

**Dispatch:** Uses existing DispatchButton and dispatch logic

### 7. Image Dispatch Method

**Copy-Paste to Terminal:** Images are copied to clipboard and pasted into Terminal alongside the prompt text. This leverages Terminal.app's native image paste support.

**Flow:**
1. Render annotated images to clipboard
2. Compose prompt text with image placeholders
3. Paste images + text into Terminal via AppleScript
4. Claude Code receives images inline in the conversation

### 8. Keyboard Shortcuts (Annotation Window)

| Shortcut | Action |
|----------|--------|
| `⌘⏎` | Dispatch prompt with queued images |
| `C` | Select crop tool |
| `D` | Select draw tool |
| `A` | Select arrow tool |
| `R` | Select rectangle tool |
| `T` | Select text tool |
| `1-7` | Select color (1=red, 2=orange, etc.) |
| `⌘Z` | Undo |
| `⌘⇧Z` | Redo |
| `Delete` | Remove selected item from send queue |
| `Esc` | Close window / cancel current operation |

---

## Technical Design

### Data Models

```swift
// New models for SwiftData

@Model
final class SimulatorRun {
    var id: UUID
    var project: Project?          // Relationship to existing Project
    var name: String               // Run label from Claude
    var deviceInfo: String?        // e.g., "iPhone 15 Pro"
    var createdAt: Date
    var screenshots: [Screenshot]  // Ordered by captureIndex
}

@Model
final class Screenshot {
    var id: UUID
    var run: SimulatorRun?
    var filePath: String           // Path to original image
    var captureIndex: Int          // Order within run
    var isHidden: Bool             // User can hide from view
    var createdAt: Date
}

// Non-persisted (in-memory only)
struct AnnotatedImage {
    var screenshot: Screenshot
    var annotations: [Annotation]
    var cropRect: CGRect?          // nil = full image
    var renderedImage: NSImage?    // Cached render
}

struct Annotation {
    var id: UUID
    var type: AnnotationType
    var points: [CGPoint]          // Path points
    var color: Color
    var text: String?              // For text annotations
}

enum AnnotationType {
    case freehand
    case arrow
    case rectangle
    case text
}
```

### Services

```swift
// ScreenshotWatcherService
// - Watches configured directory for new screenshots
// - Creates SimulatorRun/Screenshot records
// - Groups by project based on directory structure
// - Auto-deletes oldest runs when count exceeds 10 per project

// AnnotationRenderer
// - Renders annotations onto image
// - Exports final image for clipboard/dispatch
// - Handles undo/redo stack

// ImageDispatchService
// - Copies images to clipboard
// - Integrates with TerminalService to paste into Terminal
// - Formats prompt with image content
```

### Claude Code Skill Update

The companion skill (`test-feature` or similar) needs to:
1. Check with Dispatch for screenshot save location (via hook server endpoint)
2. Save screenshots to `~/Library/Application Support/Dispatch/Screenshots/{project}/{run}/`
3. Write a manifest file with run metadata

**New HookServer Endpoints:**
```
GET /screenshots/location?project={name}
Response: { "path": "/path/to/save/screenshots", "run_id": "uuid" }

POST /screenshots/run
Body: { "project": "AppName", "name": "Login Flow Test", "device": "iPhone 15 Pro" }
Response: { "run_id": "uuid", "path": "/path/to/run/folder" }
```

### Views

```
Views/Simulator/
├── SimulatorRunsStripView.swift   // HScroll of run cards in project tab
├── SimulatorRunCard.swift         // Individual run card
├── ScreenshotStripView.swift      // Horizontal scrollable strip
├── ScreenshotThumbnailView.swift  // Individual thumbnail
├── AnnotationWindow.swift         // Separate window
├── AnnotationCanvasView.swift     // Main drawing canvas
├── AnnotationToolbar.swift        // Tool selection
├── SendQueueView.swift            // HScroll queue in right panel
└── BottomStripView.swift          // All screenshots strip
```

### ViewModels

```swift
@Observable
class SimulatorViewModel {
    var runs: [SimulatorRun]
    var selectedRun: SimulatorRun?
    var selectedScreenshot: Screenshot?
    // CRUD operations
    // Auto-cleanup to 10 runs per project
}

@Observable
class AnnotationViewModel {
    var activeImage: AnnotatedImage?
    var sendQueue: [AnnotatedImage]  // Max 5 images
    var currentTool: AnnotationType
    var currentColor: Color
    var undoStack: [AnnotationAction]
    var redoStack: [AnnotationAction]
    // Annotation operations
}
```

---

## Constraints

| Constraint | Value |
|------------|-------|
| Max images per dispatch | 5 |
| Max runs per project | 10 (auto-delete oldest) |
| Image dispatch method | Copy-paste to Terminal |
| Annotation persistence | Per-session only |

---

## Additional Features

### Quick Actions
- "Send all visible" - Dispatch all non-hidden screenshots with prompt
- "Mark run complete" - Archive/hide entire run
- "Export run" - Save all screenshots + annotations as folder/PDF

### Run Notes
- Add text notes to a run for context
- Notes included in prompt if desired

---

## Integration Points

### Existing Dispatch Features
- Uses existing `DispatchButton` component
- Integrates with `TerminalService` for sending
- Respects `ExecutionStateMachine` states
- History entries include image references

### Settings Additions
- Screenshot watch directory (default: auto-configured)
- Default annotation color

---

## User Flow

### Happy Path
1. Claude Code runs `/test-feature` skill
2. Skill requests run folder from Dispatch via hook endpoint
3. Screenshots saved to project-specific folder with manifest
4. Dispatch detects new run, displays in project's run strip
5. User taps run card to open Annotation Window
6. User reviews screenshots using arrow keys
7. User crops problem area, adds arrow annotation (auto-adds to queue)
8. User types prompt: "Fix this alignment issue"
9. User hits ⌘⏎ to dispatch
10. Images pasted into Terminal with prompt
11. Claude receives images + prompt, makes fix

### Multi-Image Flow
1. User opens first screenshot, crops issue (auto-adds to queue)
2. User clicks second screenshot from bottom strip (loads in canvas)
3. User annotates (auto-adds to queue)
4. User clicks third screenshot, annotates (auto-adds to queue)
5. User types unified prompt about all issues
6. Dispatch pastes all queued images with prompt to Terminal

---

## Success Metrics

- Time from screenshot capture to user review < 2 seconds
- Annotation + dispatch workflow completable in < 30 seconds
- Zero friction keyboard-only navigation
- Clear visual distinction between "will send" and "reference" images

---

## Out of Scope (v1)

- Video recording of simulator
- Automatic issue detection / AI-suggested annotations
- Comparison with design mockups
- Multi-device simultaneous capture
- Comparison mode (side-by-side diff) - future enhancement

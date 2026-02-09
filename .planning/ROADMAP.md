# Roadmap: Dispatch

## Milestones

- [x] **v1.0 MVP** - Phases 1-7 (shipped)
- [x] **v1.1 Screenshot Integration Fix** - Phases 8-13 (shipped 2026-02-07)
- [x] **v2.0 In-App Claude Code** - Phases 14-22 (shipped 2026-02-09)
- [ ] **v3.0 Screenshot Capture** - Phases 23-27 (in progress)

## Phases

<details>
<summary>v1.0 MVP (Phases 1-7) - SHIPPED</summary>

v1.0 phases were part of brownfield development. See `Docs/TODO_SimulatorScreenshots.md` for historical phase details.

**Delivered:**
- Core prompt dispatch functionality
- Queue management
- Chain execution
- Simulator screenshot annotation UI

</details>

<details>
<summary>v1.1 Screenshot Integration Fix (Phases 8-13) - SHIPPED 2026-02-07</summary>

**Milestone Goal:** Fix screenshot path routing so skills save to Dispatch-monitored location.

- [x] **Phase 8: Foundation** - Create shared bash library for Dispatch integration
- [x] **Phase 9: Hook Integration** - Add SessionStart hook for early Dispatch detection
- [x] **Phase 10: Dispatch App Updates** - Auto-install library and hooks via HookInstaller
- [x] **Phase 11: Skill Migration** - Update all screenshot-taking skills to use shared library
- [x] **Phase 12: Verification** - End-to-end testing of screenshot flow
- [x] **Phase 13: Polish** - Settings UI, tooltips, error display

See `milestones/v1.1-ROADMAP.md` for full archive (if exists).

</details>

<details>
<summary>v2.0 In-App Claude Code (Phases 14-22) - SHIPPED 2026-02-09</summary>

**Milestone Goal:** Replace Terminal.app dependency with embedded terminal sessions.

- [x] **Phase 14: SwiftTerm Integration** - SwiftTerm package and EmbeddedTerminalView
- [x] **Phase 15: Safe Terminal Wrapper** - Thread-safe data reception
- [x] **Phase 16: Process Lifecycle** - PID tracking, orphan cleanup, graceful termination
- [x] **Phase 17: Claude Code Integration** - Process spawning, prompt dispatch, completion detection
- [x] **Phase 18: Multi-Session UI** - Tab bar, split panes, session focus
- [x] **Phase 19: Session Persistence** - SwiftData model, resume on restart
- [x] **Phase 20: Service Integration** - Queue/chain wired to embedded terminals
- [x] **Phase 21: Status Display** - JSONL parsing, context window visualization
- [x] **Phase 22: Migration & Cleanup** - Terminal.app removal, deprecation

See `milestones/v2.0-ROADMAP.md` for full archive.

</details>

### v3.0 Screenshot Capture (In Progress)

**Milestone Goal:** Add quick screenshot capture with annotation and dispatch to Claude sessions.

- [x] **Phase 23: Region Capture** - Cross-hair region selection via native screencapture
- [x] **Phase 24: Window Capture** - Interactive window capture with hover-highlight
- [ ] **Phase 25: Annotation Integration** - Connect capture pipeline to annotation UI
- [ ] **Phase 26: Sidebar Integration** - Quick Capture section with MRU and thumbnails
- [ ] **Phase 27: Polish** - Keyboard shortcuts for capture modes

## Phase Details

### Phase 23: Region Capture
**Goal**: User can capture any screen region with native cross-hair selection
**Depends on**: Nothing (first phase of v3.0)
**Requirements**: CAPT-01
**Success Criteria** (what must be TRUE):
  1. User clicks "Region Capture" and sees native macOS cross-hair cursor
  2. User can drag to select any rectangular area on any display
  3. Captured image is saved to Dispatch's screenshot directory
  4. Capture service foundation exists for subsequent phases
**Plans**: 1 plan
Plans:
- [x] 23-01-PLAN.md — ScreenshotCaptureService with region capture via screencapture CLI

### Phase 24: Window Capture
**Goal**: User can capture entire windows with interactive selection
**Depends on**: Phase 23
**Requirements**: CAPT-02, CAPT-03
**Success Criteria** (what must be TRUE):
  1. User clicks "Window Capture" and sees hover-highlight mode
  2. User can select any window to capture (not just Dispatch)
  3. iOS Simulator windows appear prominently (system UI filtered)
  4. Captured window image saves to Dispatch's screenshot directory
**Plans**: 1 plan
Plans:
- [x] 24-01-PLAN.md — Interactive window capture with WindowCaptureSession

### Phase 25: Annotation Integration
**Goal**: Captured screenshots flow into annotation UI for markup before dispatch
**Depends on**: Phase 24
**Requirements**: ANNOT-01, ANNOT-02, ANNOT-03
**Success Criteria** (what must be TRUE):
  1. After capture, annotation UI opens automatically with the screenshot
  2. User can capture additional screenshots while annotation UI is open (queue)
  3. User can select target Claude session before dispatching annotated screenshot
  4. Existing annotation tools (arrows, boxes, text) work on captured screenshots
**Plans**: TBD

### Phase 26: Sidebar Integration
**Goal**: Quick Capture UI section in sidebar with recent captures and window thumbnails
**Depends on**: Phase 25
**Requirements**: UI-01, UI-03, UI-04, CAPT-04
**Success Criteria** (what must be TRUE):
  1. Quick Capture section appears in sidebar with Region and Window buttons
  2. Recent captures strip shows last 3-5 captures as clickable thumbnails
  3. Window picker shows live thumbnail previews of capturable windows
  4. User can re-capture previously captured windows from MRU list
  5. Clicking a recent capture opens it in annotation UI
**Plans**: TBD

### Phase 27: Polish
**Goal**: Keyboard shortcuts enable rapid capture workflows
**Depends on**: Phase 26
**Requirements**: UI-02
**Success Criteria** (what must be TRUE):
  1. User can invoke region capture via keyboard shortcut
  2. User can invoke window capture via keyboard shortcut
  3. Shortcuts are configurable in settings (or use sensible defaults)
**Plans**: TBD

## Progress

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1-7 | v1.0 | - | Complete | - |
| 8. Foundation | v1.1 | 1/1 | Complete | 2026-02-03 |
| 9. Hook Integration | v1.1 | 1/1 | Complete | 2026-02-03 |
| 10. Dispatch App Updates | v1.1 | 1/1 | Complete | 2026-02-03 |
| 11. Skill Migration | v1.1 | 3/3 | Complete | 2026-02-04 |
| 12. Verification | v1.1 | 3/3 | Complete | 2026-02-07 |
| 13. Polish | v1.1 | 2/2 | Complete | 2026-02-07 |
| 14. SwiftTerm Integration | v2.0 | 1/1 | Complete | 2026-02-07 |
| 15. Safe Terminal Wrapper | v2.0 | 1/1 | Complete | 2026-02-07 |
| 16. Process Lifecycle | v2.0 | 2/2 | Complete | 2026-02-08 |
| 17. Claude Code Integration | v2.0 | 4/4 | Complete | 2026-02-08 |
| 18. Multi-Session UI | v2.0 | 2/2 | Complete | 2026-02-08 |
| 19. Session Persistence | v2.0 | 2/2 | Complete | 2026-02-08 |
| 20. Service Integration | v2.0 | 2/2 | Complete | 2026-02-08 |
| 21. Status Display | v2.0 | 1/1 | Complete | 2026-02-08 |
| 22. Migration & Cleanup | v2.0 | 7/7 | Complete | 2026-02-09 |
| 23. Region Capture | v3.0 | 1/1 | Complete | 2026-02-09 |
| 24. Window Capture | v3.0 | 1/1 | Complete | 2026-02-09 |
| 25. Annotation Integration | v3.0 | 0/? | Not started | - |
| 26. Sidebar Integration | v3.0 | 0/? | Not started | - |
| 27. Polish | v3.0 | 0/? | Not started | - |

---
*Next: `/gsd:plan-phase 25` to plan Annotation Integration*

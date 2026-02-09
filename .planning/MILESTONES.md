# Milestones

## v1.0 — Core Dispatch + Screenshot Feature (Shipped)

**Phases completed:** 1-7 (from brownfield development)

**Delivered:**
- Core prompt dispatch functionality
- Queue management
- Chain execution
- Simulator screenshot annotation UI (phases 1-7)

**Notes:** Screenshot feature mostly complete but end-to-end flow broken due to path routing issues.

---

## v1.1 — Screenshot Integration Fix (Shipped)

**Goal:** Fix screenshot path routing and polish

**Phases completed:** 8-13

**Delivered:**
- Shared bash library (`~/.claude/lib/dispatch.sh`) for skill integration
- SessionStart hook for Dispatch detection
- Auto-install library and hooks via HookInstaller
- Skill migration to shared library (4 skills migrated)
- Settings UI for screenshot configuration
- Annotation tooltips and error handling
- Integration status indicator

**Started:** 2026-02-03
**Completed:** 2026-02-07

---

## v2.0 — In-App Claude Code (Shipped: 2026-02-09)

**Delivered:** Embedded terminal sessions fully replace Terminal.app, enabling Claude Code management entirely within Dispatch.

**Phases completed:** 14-22 (22 plans total)

**Key accomplishments:**
- SwiftTerm integration with PTY support replaces Terminal.app dependency
- Multi-session management (up to 4 concurrent sessions with tab bar and split panes)
- Session persistence across app restarts with automatic resume
- Process lifecycle with PID tracking, orphan cleanup, and graceful termination
- Service integration wires queue/chain execution to embedded terminals
- Terminal.app fully removed (no AppleScript or Automation permission required)

**Stats:**
- 104 files modified
- 21,035 lines of Swift
- +17,850 / -1,628 lines net change
- 9 phases, 22 plans
- 3 days from start to ship

**Git range:** `feat(14-01)` → `feat(22-07)`

---

## v3.0 — Screenshot Capture (In Progress)

**Goal:** Add quick screenshot capture with annotation and dispatch to Claude sessions.

**Phases:** 23-27 (5 phases)

**Target features:**
- Cross-hair region selection via native macOS screencapture
- Window capture via SCContentSharingPicker (no Screen Recording permission needed)
- Simulator-aware window listing
- Direct annotation pipeline with session targeting
- Quick Capture sidebar section with MRU and thumbnails
- Keyboard shortcuts

**Requirements:** 11 total
- Capture Modes: CAPT-01 through CAPT-04
- Annotation Pipeline: ANNOT-01 through ANNOT-03
- UI Integration: UI-01 through UI-04

**Started:** 2026-02-09

---

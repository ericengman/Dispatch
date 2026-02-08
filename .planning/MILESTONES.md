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

## v2.0 — In-App Claude Code (Current)

**Goal:** Replace Terminal.app with embedded terminal sessions

**Started:** 2026-02-07

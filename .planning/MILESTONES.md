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

**Phases:** 14-22

**Planned:**
- Phase 14: SwiftTerm Integration (TERM-01, TERM-02)
- Phase 15: Safe Terminal Wrapper (TERM-03)
- Phase 16: Process Lifecycle (PROC-01 through PROC-05)
- Phase 17: Claude Code Integration (TERM-04, TERM-05, TERM-06)
- Phase 18: Multi-Session UI (SESS-01 through SESS-06)
- Phase 19: Session Persistence (PERS-01 through PERS-05)
- Phase 20: Service Integration (INTG-01 through INTG-05)
- Phase 21: Status Display (TERM-07, TERM-08)
- Phase 22: Migration & Cleanup (MIGR-01 through MIGR-04)

**Requirements:** 33 total (all mapped)

**Started:** 2026-02-07

# Roadmap: Dispatch

## Milestones

- [x] **v1.0 MVP** - Phases 1-7 (shipped)
- [ ] **v1.1 Screenshot Integration Fix** - Phases 8-13 (in progress)

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

### v1.1 Screenshot Integration Fix (In Progress)

**Milestone Goal:** Fix screenshot path routing so skills save to Dispatch-monitored location, enabling end-to-end screenshot review workflow.

**Phase Numbering:**
- Integer phases (8, 9, 10...): Planned milestone work
- Decimal phases (8.1, 8.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [x] **Phase 8: Foundation** - Create shared bash library for Dispatch integration
- [x] **Phase 9: Hook Integration** - Add SessionStart hook for early Dispatch detection
- [x] **Phase 10: Dispatch App Updates** - Auto-install library and hooks via HookInstaller
- [x] **Phase 11: Skill Migration** - Update all screenshot-taking skills to use shared library
- [ ] **Phase 12: Verification** - End-to-end testing of screenshot flow
- [ ] **Phase 13: Polish** - Settings UI, tooltips, error display

## Phase Details

### Phase 8: Foundation
**Goal**: Shared bash library exists at `~/.claude/lib/dispatch.sh` with all integration functions
**Depends on**: Nothing (first phase of v1.1)
**Requirements**: FNDTN-01, FNDTN-02, FNDTN-03, FNDTN-04, FNDTN-05, FNDTN-06
**Success Criteria** (what must be TRUE):
  1. Library file exists at `~/.claude/lib/dispatch.sh` and is sourceable from bash
  2. Calling `dispatch_init` returns a valid screenshot directory path from Dispatch API
  3. Calling `dispatch_finalize` marks the run complete and triggers Dispatch filesystem scan
  4. When Dispatch is not running, library outputs clear fallback message and returns temp path
  5. Project name is derived from git root, not current working directory
**Plans:** 1 plan

Plans:
- [x] 08-01-PLAN.md — Create dispatch.sh shared library with init/finalize functions

### Phase 9: Hook Integration
**Goal**: SessionStart hook detects Dispatch availability at session start and sets environment variables
**Depends on**: Phase 8 (library must exist for hook to use)
**Requirements**: HOOK-01, HOOK-02, HOOK-03
**Success Criteria** (what must be TRUE):
  1. SessionStart hook exists at `~/.claude/hooks/session-start.sh`
  2. Hook sets environment variables via `CLAUDE_ENV_FILE` accessible throughout session
  3. Session-start output shows Dispatch health check result (available or not)
**Plans:** 1 plan

Plans:
- [x] 09-01-PLAN.md — Create session-start.sh hook with Dispatch health check and CLAUDE_ENV_FILE integration

### Phase 10: Dispatch App Updates
**Goal**: Dispatch app auto-installs shared library and hooks when launched
**Depends on**: Phase 8, Phase 9 (library and hook must be finalized before auto-install)
**Requirements**: APP-01, APP-02, APP-03
**Success Criteria** (what must be TRUE):
  1. Launching Dispatch creates/updates `~/.claude/lib/dispatch.sh` automatically
  2. Launching Dispatch creates/updates SessionStart hook automatically
  3. Dispatch version upgrade updates library with new version
**Plans:** 1 plan

Plans:
- [x] 10-01-PLAN.md — Bundle and auto-install library and hooks via HookInstaller on app launch

### Phase 11: Skill Migration
**Goal**: All screenshot-taking skills source the shared library instead of inline integration code
**Depends on**: Phase 10 (library must be installed before skills can source it)
**Requirements**: SKILL-01, SKILL-02, SKILL-03, SKILL-04, SKILL-05, SKILL-06
**Success Criteria** (what must be TRUE):
  1. Audit identifies all skills that take screenshots
  2. `test-feature`, `explore-app`, and `test-dynamic-type` skills source shared library
  3. All other screenshot-taking skills source shared library
  4. No duplicated Dispatch integration code remains in any skill
**Plans:** 3 plans

Plans:
- [x] 11-01-PLAN.md — Migrate single-run skills (test-feature, explore-app, qa-feature) to shared library
- [x] 11-02-PLAN.md — Migrate multi-run skill (test-dynamic-type) to shared library
- [x] 11-03-PLAN.md — Verify migration complete, no inline code remains

### Phase 12: Verification
**Goal**: End-to-end screenshot flow verified working across multiple skills
**Depends on**: Phase 11 (skills must be migrated before verification)
**Requirements**: VERIFY-01, VERIFY-02, VERIFY-03, VERIFY-04
**Success Criteria** (what must be TRUE):
  1. Running a skill that captures screenshots results in screenshots appearing in Dispatch UI
  2. Running same skill with Dispatch not running produces fallback behavior with clear message
  3. At least 3 different skills successfully route screenshots to Dispatch
  4. Skill documentation reflects new integration pattern
**Plans:** 3 plans

Plans:
- [ ] 12-01-PLAN.md — E2E verification of screenshot routing (VERIFY-01, VERIFY-03)
- [ ] 12-02-PLAN.md — Graceful degradation test without Dispatch (VERIFY-02)
- [ ] 12-03-PLAN.md — Update skill and library documentation (VERIFY-04)

### Phase 13: Polish
**Goal**: Screenshot feature has complete UI for configuration, hints, and error handling
**Depends on**: Phase 12 (core flow must work before polish)
**Requirements**: POLISH-01, POLISH-02, POLISH-03, POLISH-04
**Success Criteria** (what must be TRUE):
  1. Settings UI section exists for configuring screenshot directory and max runs
  2. Annotation tools show tooltip hints on hover
  3. Failed dispatch shows user-visible error message (not just log)
  4. Dispatch UI shows integration status indicator (library installed, hook active)
**Plans**: TBD

Plans:
- [ ] 13-01: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 8 -> 8.1 -> 8.2 -> 9 -> ...

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1-7 | v1.0 | - | Complete | - |
| 8. Foundation | v1.1 | 1/1 | Complete | 2026-02-03 |
| 9. Hook Integration | v1.1 | 1/1 | Complete | 2026-02-03 |
| 10. Dispatch App Updates | v1.1 | 1/1 | Complete | 2026-02-03 |
| 11. Skill Migration | v1.1 | 3/3 | Complete | 2026-02-04 |
| 12. Verification | v1.1 | 0/3 | Not started | - |
| 13. Polish | v1.1 | 0/? | Not started | - |

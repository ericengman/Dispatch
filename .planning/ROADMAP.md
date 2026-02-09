# Roadmap: Dispatch

## Milestones

- [x] **v1.0 MVP** - Phases 1-7 (shipped)
- [x] **v1.1 Screenshot Integration Fix** - Phases 8-13 (shipped 2026-02-07)
- [x] **v2.0 In-App Claude Code** - Phases 14-22 (shipped 2026-02-09)

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

---
*Next milestone: Use `/gsd:new-milestone` to start v2.1*

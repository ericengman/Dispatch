# Roadmap: Dispatch

## Milestones

- [x] **v1.0 MVP** - Phases 1-7 (shipped)
- [x] **v1.1 Screenshot Integration Fix** - Phases 8-13 (complete)
- [ ] **v2.0 In-App Claude Code** - Phases 14-22 (in progress)

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
<summary>v1.1 Screenshot Integration Fix (Phases 8-13) - COMPLETE</summary>

**Milestone Goal:** Fix screenshot path routing so skills save to Dispatch-monitored location.

- [x] **Phase 8: Foundation** - Create shared bash library for Dispatch integration
- [x] **Phase 9: Hook Integration** - Add SessionStart hook for early Dispatch detection
- [x] **Phase 10: Dispatch App Updates** - Auto-install library and hooks via HookInstaller
- [x] **Phase 11: Skill Migration** - Update all screenshot-taking skills to use shared library
- [x] **Phase 12: Verification** - End-to-end testing of screenshot flow
- [x] **Phase 13: Polish** - Settings UI, tooltips, error display

**Completed:** 2026-02-07

</details>

### v2.0 In-App Claude Code (In Progress)

**Milestone Goal:** Replace Terminal.app dependency with embedded terminal sessions, enabling full Claude Code management within Dispatch.

**Phase Numbering:**
- Integer phases (14, 15, 16...): Planned milestone work
- Decimal phases (14.1, 14.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [x] **Phase 14: SwiftTerm Integration** - Add terminal emulation dependency and basic view
- [x] **Phase 15: Safe Terminal Wrapper** - Implement thread-safe data reception to prevent crashes
- [x] **Phase 16: Process Lifecycle** - Track, persist, and clean up terminal processes
- [x] **Phase 17: Claude Code Integration** - Spawn Claude Code, dispatch prompts, detect completion
- [x] **Phase 18: Multi-Session UI** - Support multiple simultaneous terminal sessions with split panes
- [x] **Phase 19: Session Persistence** - Save and resume sessions across app restarts
- [x] **Phase 20: Service Integration** - Wire embedded terminals to queue and chain execution
- [x] **Phase 21: Status Display** - Parse JSONL for rich status and context window visualization
- [ ] **Phase 22: Migration & Cleanup** - Remove Terminal.app dependency and AppleScript code

## Phase Details

### Phase 14: SwiftTerm Integration
**Goal**: SwiftTerm package integrated and basic terminal view renders a bash shell
**Depends on**: Nothing (first phase of v2.0)
**Requirements**: TERM-01, TERM-02
**Success Criteria** (what must be TRUE):
  1. SwiftTerm package is added to Xcode project and builds successfully
  2. EmbeddedTerminalView displays in the Dispatch window with proper sizing
  3. User can type commands in the embedded terminal and see output
  4. Terminal supports ANSI colors and standard terminal escape sequences
**Plans:** 1 plan

Plans:
- [x] 14-01-PLAN.md — Add SwiftTerm package and create EmbeddedTerminalView

### Phase 15: Safe Terminal Wrapper
**Goal**: Terminal data reception is thread-safe and survives view lifecycle changes
**Depends on**: Phase 14
**Requirements**: TERM-03
**Success Criteria** (what must be TRUE):
  1. Rapidly closing and reopening terminal views does not crash the app
  2. Terminal continues receiving data during view updates/redraws
  3. No EXC_BAD_ACCESS crashes during process termination
**Plans:** 1 plan

Plans:
- [x] 15-01-PLAN.md — Add lifecycle-safe coordinator with deinit cleanup

### Phase 16: Process Lifecycle
**Goal**: Terminal processes are tracked, persisted, and cleaned up reliably
**Depends on**: Phase 15
**Requirements**: PROC-01, PROC-02, PROC-03, PROC-04, PROC-05
**Success Criteria** (what must be TRUE):
  1. TerminalProcessRegistry tracks all spawned process PIDs
  2. Quitting and relaunching Dispatch cleans up any orphaned processes from previous session
  3. Closing a terminal session terminates both shell and any child processes (Claude Code)
  4. Process termination uses graceful shutdown (SIGTERM first, SIGKILL if needed)
**Plans:** 2 plans

Plans:
- [x] 16-01-PLAN.md — Create TerminalProcessRegistry with PID tracking and persistence
- [x] 16-02-PLAN.md — Implement graceful termination and orphan cleanup

### Phase 17: Claude Code Integration
**Goal**: Claude Code runs in embedded terminal with prompt dispatch and completion detection
**Depends on**: Phase 16
**Requirements**: TERM-04, TERM-05, TERM-06
**Success Criteria** (what must be TRUE):
  1. Claude Code process launches in terminal with proper environment (PATH, TERM, COLORTERM)
  2. Dispatching a prompt writes it to the PTY and Claude Code receives it
  3. Completion is detected via output pattern matching (as backup to HookServer)
  4. Terminal shows Claude Code's colored output correctly
**Plans:** 4 plans (2 core + 2 gap closure)

Plans:
- [x] 17-01-PLAN.md — Create ClaudeCodeLauncher service with environment configuration
- [x] 17-02-PLAN.md — Implement prompt dispatch via PTY and completion detection
- [x] 17-03-PLAN.md — Wire Claude Code as default terminal launch mode (gap closure)
- [x] 17-04-PLAN.md — Create EmbeddedTerminalBridge for ExecutionManager dispatch (gap closure)

### Phase 18: Multi-Session UI
**Goal**: Users can manage multiple simultaneous Claude Code sessions
**Depends on**: Phase 17
**Requirements**: SESS-01, SESS-02, SESS-03, SESS-04, SESS-05, SESS-06
**Success Criteria** (what must be TRUE):
  1. User can create multiple terminal sessions (new session button/shortcut)
  2. Sessions display in a tab bar or side panel for easy switching
  3. User can view 2+ sessions simultaneously via split pane layout
  4. Clicking a session makes it the focused/active target for prompt dispatch
  5. User can enlarge a session to full panel size (focus mode)
**Plans:** 2 plans

Plans:
- [x] 18-01-PLAN.md — Session management infrastructure (TerminalSession model, TerminalSessionManager, bridge registry)
- [x] 18-02-PLAN.md — Multi-session UI (SessionTabBar, SessionPaneView, MultiSessionTerminalView, MainView integration)

### Phase 19: Session Persistence
**Goal**: Terminal sessions survive app restarts with context preserved
**Depends on**: Phase 18
**Requirements**: PERS-01, PERS-02, PERS-03, PERS-04, PERS-05
**Success Criteria** (what must be TRUE):
  1. Session metadata (project, working directory, last activity) persists in SwiftData
  2. Sessions are associated with Projects (project-session relationship)
  3. Reopening Dispatch offers to resume previous sessions
  4. Resuming a session uses `claude -r <sessionId>` to continue conversation
  5. Expired/stale sessions create fresh sessions gracefully
**Plans:** 2 plans

Plans:
- [x] 19-01-PLAN.md — Convert TerminalSession to @Model with Project relationship
- [x] 19-02-PLAN.md — Wire persistence (load on launch, resume picker, stale handling)

### Phase 20: Service Integration
**Goal**: Embedded terminals work with existing queue and chain execution
**Depends on**: Phase 19
**Requirements**: INTG-01, INTG-02, INTG-03, INTG-04, INTG-05
**Success Criteria** (what must be TRUE):
  1. EmbeddedTerminalService implements same dispatch interface as TerminalService
  2. Queue "Run Next" and "Run All" dispatch prompts to embedded terminal
  3. Chain execution dispatches sequence with configured delays
  4. ExecutionStateMachine transitions correctly for embedded terminal execution
  5. HookServer completion detection works alongside output pattern matching
**Plans:** 2 plans

Plans:
- [x] 20-01-PLAN.md — Create EmbeddedTerminalService with dispatch interface, session validation
- [x] 20-02-PLAN.md — Verify queue and chain integration, human verification checkpoint

### Phase 21: Status Display
**Goal**: Rich status display from Claude Code JSONL data
**Depends on**: Phase 20
**Requirements**: TERM-07, TERM-08
**Success Criteria** (what must be TRUE):
  1. Session status shows current state (thinking, executing, idle)
  2. Context window usage displays as visual indicator
  3. Status updates in near real-time as Claude Code progresses
**Plans**: 1 plan

Plans:
- [x] 21-01-PLAN.md — Parse JSONL session files and display status/context usage

### Phase 22: Migration & Cleanup
**Goal**: Terminal.app dependency fully removed, clean codebase
**Depends on**: Phase 21
**Requirements**: MIGR-01, MIGR-02, MIGR-03, MIGR-04
**Success Criteria** (what must be TRUE):
  1. TerminalService AppleScript methods are removed or deprecated
  2. MainView shows embedded terminal panel instead of external window controls
  3. Terminal.app Automation permission is no longer required
  4. QueueItem and Chain execution use embedded sessions exclusively
**Plans**: 2 plans

Plans:
- [ ] 22-01-PLAN.md — Replace TerminalService with embedded-only execution in ExecutionManager
- [ ] 22-02-PLAN.md — Remove Terminal.app UI controls and AppleEvents permission

## Progress

**Execution Order:**
Phases execute in numeric order: 14 -> 14.1 -> 14.2 -> 15 -> ...

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
| 22. Migration & Cleanup | v2.0 | 0/2 | Not started | - |

# Requirements: Dispatch v2.0

**Defined:** 2026-02-07
**Core Value:** Users can dispatch prompts to Claude Code with zero friction via embedded terminal sessions

## v2.0 Requirements

Requirements for In-App Claude Code milestone. Each maps to roadmap phases.

### Terminal Core

- [ ] **TERM-01**: Add SwiftTerm package dependency (v1.10.0+) for terminal emulation
- [ ] **TERM-02**: Create EmbeddedTerminalView (NSViewRepresentable) wrapping SwiftTerm's TerminalView
- [ ] **TERM-03**: Implement SafeLocalProcessTerminalView with NSLock-protected data reception to prevent deallocation crashes
- [ ] **TERM-04**: Spawn Claude Code process with proper environment (PATH, TERM, COLORTERM, LANG)
- [ ] **TERM-05**: Dispatch prompts to terminal via PTY write (replace AppleScript-based sending)
- [ ] **TERM-06**: Detect Claude Code completion via output pattern matching (complement to HookServer)
- [ ] **TERM-07**: Parse Claude Code JSONL session files for status display (thinking, executing, idle)
- [ ] **TERM-08**: Display context window usage visualization from JSONL data

### Process Lifecycle

- [ ] **PROC-01**: Implement TerminalProcessRegistry to track active PIDs across sessions
- [ ] **PROC-02**: Persist PIDs to UserDefaults for crash recovery
- [ ] **PROC-03**: Clean up orphaned Claude Code processes on app launch
- [ ] **PROC-04**: Implement two-stage graceful termination (SIGTERM, wait, SIGKILL)
- [ ] **PROC-05**: Use process group termination (killpg) to kill child processes

### Multi-Session

- [ ] **SESS-01**: Support multiple simultaneous terminal sessions
- [ ] **SESS-02**: Display sessions in tabs or panel list
- [ ] **SESS-03**: Implement split pane view for multiple visible sessions
- [ ] **SESS-04**: Track and manage session selection/focus state
- [ ] **SESS-05**: Provide full-screen/enlarge mode for focused session
- [ ] **SESS-06**: Limit maximum concurrent sessions to prevent resource exhaustion

### Persistence

- [ ] **PERS-01**: Create TerminalSession SwiftData model for session state
- [ ] **PERS-02**: Associate sessions with Project model (project-session relationship)
- [ ] **PERS-03**: Persist session metadata (working directory, project, last activity)
- [ ] **PERS-04**: Resume sessions on app restart using `claude -r <sessionId>`
- [ ] **PERS-05**: Handle stale session resume gracefully (create new if expired)

### Integration

- [ ] **INTG-01**: Create EmbeddedTerminalService implementing dispatch interface
- [ ] **INTG-02**: Wire queue execution (run next, run all) to embedded terminals
- [ ] **INTG-03**: Wire chain execution to embedded terminals with delay handling
- [ ] **INTG-04**: Integrate with ExecutionStateMachine for state transitions
- [ ] **INTG-05**: Maintain HookServer completion detection alongside output pattern

### Migration

- [ ] **MIGR-01**: Replace TerminalService AppleScript methods with EmbeddedTerminalService
- [ ] **MIGR-02**: Update MainView to show embedded terminal panel instead of external window controls
- [ ] **MIGR-03**: Remove Terminal.app automation permission requirements
- [ ] **MIGR-04**: Update QueueItem/Chain execution to target embedded sessions

## Future Requirements

Deferred to v2.1 or later.

### Enhanced Features

- **ENH-01**: Scrollback persistence (serialize terminal buffer to disk)
- **ENH-02**: Session search across all terminals
- **ENH-03**: Copy session output to clipboard
- **ENH-04**: Export session transcript

### Deferred Polish

- **POLISH-01**: Drag to reorder sessions
- **POLISH-02**: Custom terminal themes/colors
- **POLISH-03**: Keyboard shortcuts for session navigation

## Out of Scope

Explicitly excluded. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| Git worktree management | Dispatch is prompt management, not git workflow |
| Multi-provider support | Dispatch is Claude Code-specific |
| Repository picker UI | Use existing Project model |
| Approval notification service | Dispatch uses `--dangerously-skip-permissions` |
| Dual-mode toggle (Terminal.app fallback) | Full replacement is cleaner, no hybrid mode |
| Mac App Store distribution | Sandbox incompatible with forkpty() |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| TERM-01 | Phase 14 | Pending |
| TERM-02 | Phase 14 | Pending |
| TERM-03 | Phase 15 | Pending |
| TERM-04 | Phase 17 | Pending |
| TERM-05 | Phase 17 | Pending |
| TERM-06 | Phase 17 | Pending |
| TERM-07 | Phase 21 | Pending |
| TERM-08 | Phase 21 | Pending |
| PROC-01 | Phase 16 | Pending |
| PROC-02 | Phase 16 | Pending |
| PROC-03 | Phase 16 | Pending |
| PROC-04 | Phase 16 | Pending |
| PROC-05 | Phase 16 | Pending |
| SESS-01 | Phase 18 | Pending |
| SESS-02 | Phase 18 | Pending |
| SESS-03 | Phase 18 | Pending |
| SESS-04 | Phase 18 | Pending |
| SESS-05 | Phase 18 | Pending |
| SESS-06 | Phase 18 | Pending |
| PERS-01 | Phase 19 | Pending |
| PERS-02 | Phase 19 | Pending |
| PERS-03 | Phase 19 | Pending |
| PERS-04 | Phase 19 | Pending |
| PERS-05 | Phase 19 | Pending |
| INTG-01 | Phase 20 | Pending |
| INTG-02 | Phase 20 | Pending |
| INTG-03 | Phase 20 | Pending |
| INTG-04 | Phase 20 | Pending |
| INTG-05 | Phase 20 | Pending |
| MIGR-01 | Phase 22 | Pending |
| MIGR-02 | Phase 22 | Pending |
| MIGR-03 | Phase 22 | Pending |
| MIGR-04 | Phase 22 | Pending |

**Coverage:**
- v2.0 requirements: 33 total
- Mapped to phases: 33/33
- Unmapped: 0

---
*Requirements defined: 2026-02-07*
*Last updated: 2026-02-07 after roadmap creation*

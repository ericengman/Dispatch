# Requirements: Dispatch v2.0

**Defined:** 2026-02-07
**Core Value:** Users can dispatch prompts to Claude Code with zero friction via embedded terminal sessions

## v2.0 Requirements

Requirements for In-App Claude Code milestone. Each maps to roadmap phases.

### Terminal Core

- [x] **TERM-01**: Add SwiftTerm package dependency (v1.10.0+) for terminal emulation
- [x] **TERM-02**: Create EmbeddedTerminalView (NSViewRepresentable) wrapping SwiftTerm's TerminalView
- [x] **TERM-03**: Implement SafeLocalProcessTerminalView with NSLock-protected data reception to prevent deallocation crashes
- [x] **TERM-04**: Spawn Claude Code process with proper environment (PATH, TERM, COLORTERM, LANG)
- [x] **TERM-05**: Dispatch prompts to terminal via PTY write (replace AppleScript-based sending)
- [x] **TERM-06**: Detect Claude Code completion via output pattern matching (complement to HookServer)
- [x] **TERM-07**: Parse Claude Code JSONL session files for status display (thinking, executing, idle)
- [x] **TERM-08**: Display context window usage visualization from JSONL data

### Process Lifecycle

- [x] **PROC-01**: Implement TerminalProcessRegistry to track active PIDs across sessions
- [x] **PROC-02**: Persist PIDs to UserDefaults for crash recovery
- [x] **PROC-03**: Clean up orphaned Claude Code processes on app launch
- [x] **PROC-04**: Implement two-stage graceful termination (SIGTERM, wait, SIGKILL)
- [x] **PROC-05**: Use process group termination (killpg) to kill child processes

### Multi-Session

- [x] **SESS-01**: Support multiple simultaneous terminal sessions
- [x] **SESS-02**: Display sessions in tabs or panel list
- [x] **SESS-03**: Implement split pane view for multiple visible sessions
- [x] **SESS-04**: Track and manage session selection/focus state
- [x] **SESS-05**: Provide full-screen/enlarge mode for focused session
- [x] **SESS-06**: Limit maximum concurrent sessions to prevent resource exhaustion

### Persistence

- [x] **PERS-01**: Create TerminalSession SwiftData model for session state
- [x] **PERS-02**: Associate sessions with Project model (project-session relationship)
- [x] **PERS-03**: Persist session metadata (working directory, project, last activity)
- [x] **PERS-04**: Resume sessions on app restart using `claude -r <sessionId>`
- [x] **PERS-05**: Handle stale session resume gracefully (create new if expired)

### Integration

- [x] **INTG-01**: Create EmbeddedTerminalService implementing dispatch interface
- [x] **INTG-02**: Wire queue execution (run next, run all) to embedded terminals
- [x] **INTG-03**: Wire chain execution to embedded terminals with delay handling
- [x] **INTG-04**: Integrate with ExecutionStateMachine for state transitions
- [x] **INTG-05**: Maintain HookServer completion detection alongside output pattern

### Migration

- [x] **MIGR-01**: Replace TerminalService AppleScript methods with EmbeddedTerminalService
- [x] **MIGR-02**: Update MainView to show embedded terminal panel instead of external window controls
- [x] **MIGR-03**: Remove Terminal.app automation permission requirements
- [x] **MIGR-04**: Update QueueItem/Chain execution to target embedded sessions

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
| TERM-01 | Phase 14 | Complete |
| TERM-02 | Phase 14 | Complete |
| TERM-03 | Phase 15 | Complete |
| TERM-04 | Phase 17 | Complete |
| TERM-05 | Phase 17 | Complete |
| TERM-06 | Phase 17 | Complete |
| TERM-07 | Phase 21 | Complete |
| TERM-08 | Phase 21 | Complete |
| PROC-01 | Phase 16 | Complete |
| PROC-02 | Phase 16 | Complete |
| PROC-03 | Phase 16 | Complete |
| PROC-04 | Phase 16 | Complete |
| PROC-05 | Phase 16 | Complete |
| SESS-01 | Phase 18 | Complete |
| SESS-02 | Phase 18 | Complete |
| SESS-03 | Phase 18 | Complete |
| SESS-04 | Phase 18 | Complete |
| SESS-05 | Phase 18 | Complete |
| SESS-06 | Phase 18 | Complete |
| PERS-01 | Phase 19 | Complete |
| PERS-02 | Phase 19 | Complete |
| PERS-03 | Phase 19 | Complete |
| PERS-04 | Phase 19 | Complete |
| PERS-05 | Phase 19 | Complete |
| INTG-01 | Phase 20 | Complete |
| INTG-02 | Phase 20 | Complete |
| INTG-03 | Phase 20 | Complete |
| INTG-04 | Phase 20 | Complete |
| INTG-05 | Phase 20 | Complete |
| MIGR-01 | Phase 22 | Complete |
| MIGR-02 | Phase 22 | Complete |
| MIGR-03 | Phase 22 | Complete |
| MIGR-04 | Phase 22 | Complete |

**Coverage:**
- v2.0 requirements: 33 total
- Mapped to phases: 33/33
- Unmapped: 0

---
*Requirements defined: 2026-02-07*
*Last updated: 2026-02-09 after Milestone v2.0 completion*

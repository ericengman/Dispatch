# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-07)

**Core value:** Users can dispatch prompts to Claude Code with zero friction via embedded terminal sessions
**Current focus:** Milestone v2.0 complete — In-App Claude Code

## Current Position

Phase: 22 of 22 (Migration & Cleanup)
Plan: 7 of 7 in current phase (22-01, 22-02, 22-03, 22-04, 22-05, 22-06, and 22-07 complete)
Status: Phase complete
Last activity: 2026-02-09 — Completed 22-05-PLAN.md

Progress: [####################] 100% (9/9 v2.0 phases complete)

## Performance Metrics

**Velocity:**
- Total plans completed: 32 (12 v1.1, 20 v2.0)
- Average duration: 2.8m
- Total execution time: 91.2m

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 8 | 1 | 3m | 3m |
| 9 | 1 | 3m | 3m |
| 10 | 1 | 4m | 4m |
| 11 | 3 | 7m | 2.3m |
| 12 | 4 | 15m | 3.8m |
| 13 | 2 | 7m | 3.5m |
| 14 | 1 | 5m | 5m |
| 15 | 1 | 1m | 1m |
| 16 | 2 | 4m | 2m |
| 17 | 4 | 10m | 2.5m |
| 18 | 2 | 5m | 2.5m |
| 19 | 2 | 7.9m | 4.0m |
| 20 | 2 | 3.9m | 2.0m |
| 21 | 1 | 3.4m | 3.4m |
| 22 | 7 | 15.0m | 2.1m |

**Recent Trend:**
- Last 5 plans: 22-03 (1.0m), 22-04 (1.0m), 22-05 (3.0m), 22-06 (2.0m), 22-07 (2.0m)
- Trend: Migration cleanup complete, v2.0 finished

*Updated after each plan completion*

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- [v2.0]: Full Terminal.app replacement (no hybrid mode)
- [v2.0]: SwiftTerm + LocalProcess pattern (proven in AgentHub)
- [v2.0]: Multi-session split panes (matches AgentHub UX)
- [14-01]: SwiftTerm 1.10.1 via upToNextMinorVersion
- [14-01]: HSplitView terminal placement with Cmd+Shift+T toggle
- [14-01]: Respect user's $SHELL environment variable
- [15-01]: Strong reference cleanup pattern for Coordinator lifecycle
- [15-01]: sendIfRunning helper for safe command execution
- [16-01]: UserDefaults for PID persistence (simple, sufficient for crash recovery)
- [16-01]: NSLock over actor isolation for PID registry (synchronous API)
- [16-01]: Set<pid_t> in-memory structure for fast lookup
- [16-02]: Two-stage termination with 3s timeout (2s for deinit) prevents zombies while allowing graceful shutdown
- [16-02]: killpg sends signal to entire process group (shell + Claude Code children)
- [16-02]: kill(pid, 0) syscall for lightweight process existence check
- [17-01]: ClaudeCodeLauncher singleton for consistent process configuration
- [17-01]: TerminalLaunchMode enum in EmbeddedTerminalView for shell/Claude Code selection
- [17-01]: PATH prepending (~/.claude/local/bin, /usr/local/bin, /opt/homebrew/bin) for CLI discovery
- [17-01]: Terminal.getEnvironmentVariables() baseline ensures TERM=xterm-256color and COLORTERM=truecolor
- [17-01]: --dangerously-skip-permissions default true for embedded usage
- [17-02]: dispatchPrompt separate from sendIfRunning for different use cases
- [17-02]: getBufferAsData for terminal content access (not buffer.lines)
- [17-02]: Dual monitoring (HookServer + pattern) for robust completion detection
- [17-02]: 1.5s polling interval balances responsiveness and CPU usage
- [17-03]: Added ~/.local/bin to claude CLI search paths (npm global install location)
- [17-04]: Bridge pattern for ExecutionManager to embedded terminal coordinator
- [17-04]: Embedded terminal takes priority, Terminal.app as fallback
- [18-01]: @Observable over ObservableObject for modern SwiftUI integration
- [18-01]: maxSessions = 4 limit enforced by TerminalSessionManager (SESS-06)
- [18-01]: UUID identity for sessions enables registry lookups and logging
- [18-01]: Registry pattern with UUID-keyed dictionaries for multi-session support
- [18-01]: Full backward compatibility with legacy single-session API
- [18-02]: Tab bar always visible at top for quick session switching
- [18-02]: Layout mode picker only shows with 2+ sessions
- [18-02]: Close button always visible (not hover-only) for simplicity
- [18-02]: Blue border highlight indicates active session
- [18-02]: Split layouts show first 2 sessions only
- [18-02]: @State with singleton pattern for TerminalSessionManager
- [19-01]: Runtime refs (coordinator, terminal) stored in manager dictionaries, not @Model
- [19-01]: deleteRule: .nullify for Project → TerminalSession relationship
- [19-01]: lastActivity updated on session creation (Date())
- [19-02]: 7-day session retention window balances recency and cleanup
- [19-02]: Stale session detection via terminal output patterns (3s delay for init)
- [19-02]: Clear claudeSessionId on stale detection, let user close/reopen for fresh
- [19-02]: Activity timestamp updated on prompt dispatch for accurate recency
- [20-01]: EmbeddedTerminalService wraps EmbeddedTerminalBridge (parallel to TerminalService)
- [20-01]: Session activity updated automatically on dispatch (PERS-05 compliance)
- [20-01]: Hook completion validates executingSessionId to prevent cross-session confusion
- [20-02]: Tracing logs at execution boundaries (queue/chain → ExecutionManager)
- [20-02]: Info-level logs for execution flow visibility (not debug level)
- [21-01]: DispatchSource.FileSystemObject for JSONL file monitoring (event-driven)
- [21-01]: Tail-reading pattern with lastOffset tracking for incremental parsing
- [21-01]: Status shown only when not idle to reduce visual noise
- [21-01]: Remove deinit from MainActor class - rely on cancel handler for cleanup
- [22-02]: Mark deprecated rather than delete for reference during migration
- [22-02]: Remove NSAppleEventsUsageDescription entirely for clean new installs
- [22-01]: Deprecate TerminalService instead of deleting (allows rollback)
- [22-01]: Guard-else pattern for embedded service availability checks
- [22-03]: Remove terminal window tracking for embedded sessions
- [22-03]: Simplify history creation with nil windowId/windowName
- [22-04]: Mark deprecated rather than remove for backward compatibility until v3.0
- [22-04]: Clear deprecation message directs to embedded terminal dispatch
- [22-05]: Clipboard images + dispatchPrompt() workflow for image annotation dispatch
- [22-05]: Images remain in clipboard for manual paste (Cmd+V) - automatic paste not supported in embedded terminal
- [22-06]: Remove Terminal.app permission alerts (no longer relevant with embedded terminal)
- [22-06]: Remove Terminal.app window loading and matching (obsolete with session-based targeting)

### Pending Todos

None yet.

### Blockers/Concerns

None.

### Known Gaps (Future Work)

- 20 skills still use hardcoded `/tmp` paths instead of Dispatch library
- Phase 11 migrated only 4 skills; remaining skills need migration for complete integration
- Status monitoring only starts for resumed sessions (not new sessions until they get claudeSessionId)

## Session Continuity

Last session: 2026-02-09
Stopped at: Milestone v2.0 complete, all 9 phases verified
Resume file: None

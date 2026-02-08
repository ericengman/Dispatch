# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-07)

**Core value:** Users can dispatch prompts to Claude Code with zero friction via embedded terminal sessions
**Current focus:** Phase 17 - Claude Code Integration

## Current Position

Phase: 17 of 22 (Claude Code Integration)
Plan: 4 of 4 in current phase
Status: Phase complete
Last activity: 2026-02-08 — Completed 17-04-PLAN.md

Progress: [##################░░] 95% (19/20 phases complete across milestones)

## Performance Metrics

**Velocity:**
- Total plans completed: 20 (12 v1.1, 8 v2.0)
- Average duration: 3.0m
- Total execution time: 60m

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

**Recent Trend:**
- Last 5 plans: 17-01 (3m), 17-02 (3m), 17-03 (2m), 17-04 (2m)
- Trend: Terminal integration consistently fast (2-3m per plan)

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
- [17-04]: Bridge pattern for ExecutionManager to embedded terminal coordinator
- [17-04]: Embedded terminal takes priority, Terminal.app as fallback

### Pending Todos

None yet.

### Blockers/Concerns

- [Phase 19]: Claude Code's `-r` session resume behavior needs verification

### Known Gaps (Future Work)

- 20 skills still use hardcoded `/tmp` paths instead of Dispatch library
- Phase 11 migrated only 4 skills; remaining skills need migration for complete integration

## Session Continuity

Last session: 2026-02-08 10:58
Stopped at: Completed 17-04-PLAN.md (EmbeddedTerminalBridge)
Resume file: None

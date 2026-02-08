# Features Research: Dispatch v2.0 Terminal Embedding

**Domain:** macOS app with embedded Claude Code terminals
**Reference Implementation:** AgentHub (https://github.com/jamesrochabrun/AgentHub)
**Researched:** 2026-02-07
**Confidence:** HIGH (direct source code analysis)

## Table Stakes (v2.0 Must Have)

Features required for full Terminal.app replacement. Missing any of these = incomplete replacement.

| Feature | Why Essential | Complexity | Dispatch Integration | AgentHub Reference |
|---------|--------------|------------|---------------------|-------------------|
| **Embedded Terminal View** | Core replacement for Terminal.app | High | Replace AppleScript-based `TerminalService` | Uses SwiftTerm's `ManagedLocalProcessTerminalView` |
| **Process Lifecycle Management** | Must spawn, track, and terminate Claude Code processes | High | Integrate with `ExecutionStateMachine` | `TerminalProcessRegistry` with PID tracking, SIGTERM/SIGKILL cleanup |
| **Multi-Session Display** | User requires parallel terminals | Medium | New UI component, integrate with existing NavigationSplitView | `CLISessionsListView` with split-pane layout |
| **Session Selection/Focus** | Must target specific session for prompt dispatch | Medium | Replace `targetWindowId` in `QueueItem` with session reference | `primarySessionId` binding pattern |
| **Full-Screen/Enlarge Mode** | User-specified requirement | Low | Modal overlay or window state toggle | Full-screen terminal mode referenced in README |
| **ANSI Color Support** | Claude Code output uses colors extensively | Low (SwiftTerm handles) | Configure SwiftTerm properly | `TERM=xterm-256color`, `COLORTERM=truecolor` |
| **Input Dispatch to Session** | Core prompt sending functionality | Medium | Replace `sendPrompt()` AppleScript with PTY write | `send(txt:)` method on terminal view |
| **Session Persistence Metadata** | User requires persistence across restarts | Medium | New SwiftData model for session state | `SessionMetadataStore` using SQLite/GRDB |
| **Session Resume Capability** | User requires resume after restart | High | Store session IDs, use `claude -r` flag | Supports `-r` flag with session ID |
| **Completion Detection** | Existing feature must work | Medium | Adapt `HookServer` and polling to embedded context | File watcher on JSONL + modification time check |

### Terminal Core Details

AgentHub uses **SwiftTerm** (`ManagedLocalProcessTerminalView`) with a custom safe wrapper:

```swift
// Key implementation pattern from AgentHub
class SafeLocalProcessTerminalView: ManagedLocalProcessTerminalView {
    // Prevents crashes during deallocation race conditions
    // Handles dataReceived safely when terminal is being torn down
}
```

**Process Launch Pattern:**
- Spawns `/bin/bash` with configured working directory
- Injects environment: `TERM=xterm-256color`, `COLORTERM=truecolor`
- Sends `claude` or `claude -r <sessionId>` command
- Tracks PID in registry for cleanup

### Session State Detection

AgentHub infers state from JSONL file monitoring (not direct process inspection):

| State | Detection Method |
|-------|-----------------|
| Active | JSONL modified within 60 seconds |
| Idle | No recent JSONL modification |
| Thinking | Tool_use blocks in progress (from JSONL parsing) |
| Awaiting Approval | Pending tool uses detected |
| Executing Tool | Tool execution in progress |

**Dispatch Adaptation:** Can leverage existing `HookServer` for completion detection, supplement with JSONL parsing for richer state display.

## Differentiators (Could Defer to Post-v2.0)

Nice-to-have features that enhance UX but aren't required for Terminal.app replacement.

| Feature | Value Proposition | Complexity | Priority | Notes |
|---------|-------------------|------------|----------|-------|
| **Session JSONL Monitoring** | Rich status display (thinking, executing, etc.) | Medium | P2 | AgentHub parses `~/.claude/projects/*/session.jsonl` |
| **Context Window Bar** | Shows token usage as visual progress bar | Low | P2 | Useful but not essential for dispatch workflow |
| **Cross-Session Search** | Find sessions by content | Medium | P3 | Nice for power users with many sessions |
| **Token/Cost Metrics** | Display input/output tokens, cost | Low | P3 | AgentHub tracks from JSONL API response data |
| **Diff Preview** | View code changes before commit | High | P3 | AgentHub has full GitDiffView with file tree |
| **Inline Commenting** | Add comments to diff lines | High | P3 | Review workflow, not core to Dispatch's purpose |
| **Pending Changes View** | Show uncommitted changes | Medium | P3 | Git integration feature |
| **Web Preview** | Preview web content from sessions | Medium | P4 | `DevServerManager` + `WebPreviewResolver` |
| **Plan View** | Display AI-generated plans | Low | P4 | Markdown rendering of Claude's plans |

### Context Window Display (If Implemented)

AgentHub's implementation with honest caveats:

```markdown
Context usage is calculated from API response data (input + cache tokens).
Claude Code's internal /context command includes additional overhead like
autocompact buffer reservations that aren't exposed in session files.
```

Visual thresholds:
- Green: < 75% capacity
- Orange: 75-90% capacity
- Red: > 90% capacity

## Anti-Features (Don't Build)

Features AgentHub implements that Dispatch explicitly should NOT build, with reasoning.

| Anti-Feature | AgentHub Has It | Why NOT for Dispatch | Alternative |
|--------------|----------------|---------------------|-------------|
| **Git Worktree Management** | Full `GitWorktreeService` with create/list/remove | Dispatch is prompt management, not git workflow. Adds complexity without core value. | Users manage worktrees externally |
| **Multi-Provider Support** | `MultiProviderSessionsListView`, provider abstractions | Dispatch is Claude Code-specific. Provider abstraction adds indirection without benefit. | Direct Claude Code integration only |
| **Codex Support** | Coming soon, with dedicated services | Different tool, different workflow. Maintain focus. | Out of scope entirely |
| **Repository Picker UI** | `CLIRepositoryPickerView`, tree browser | Dispatch already has Project model. Don't duplicate. | Leverage existing Project paths |
| **Global Stats Aggregation** | `GlobalStatsService` with aggregate metrics | Analytics overkill for dispatch workflow. | Session-level stats only if needed |
| **Intelligence Input/Popover** | AI query input separate from terminal | Dispatch IS the prompt input. Redundant. | Use existing prompt editor |
| **Worktree Orchestration** | `WorktreeOrchestrationService` | Git-specific workflow outside Dispatch scope. | Not needed |
| **Branch Management UI** | `CLIWorktreeBranchRow`, branch selection | Git UI belongs in git tools, not prompt dispatch. | Not needed |
| **Approval Notification Service** | System notifications for tool approvals | Dispatch uses `--dangerously-skip-permissions`. Approvals aren't part of workflow. | Not applicable |

### Why These Are Anti-Features for Dispatch

**Dispatch's Core Value Proposition:**
1. Queue and dispatch prompts to Claude Code
2. Chain prompts for multi-step automation
3. Manage prompt library with templates

**What Dispatch is NOT:**
- A git client
- A repository browser
- A multi-AI-provider hub
- An analytics dashboard

AgentHub is a "Claude Code session manager" while Dispatch is a "prompt dispatch system." The embedded terminal is infrastructure, not the product.

## Integration with Existing Dispatch

How new terminal embedding features connect to existing functionality.

### Queue Execution Integration

**Current Flow (Terminal.app via AppleScript):**
```
QueueItem -> ExecutionManager.execute() -> TerminalService.sendPrompt() -> AppleScript
```

**New Flow (Embedded Terminal):**
```
QueueItem -> ExecutionManager.execute() -> EmbeddedTerminalService.send() -> PTY write
```

**Changes Required:**
1. `QueueItem.targetTerminalId` becomes session ID reference (already uses String, compatible)
2. `ExecutionStateMachine` state transitions remain identical
3. `ExecutionManager` replaces `TerminalService` calls with embedded terminal API
4. `HookServer` completion detection continues working (HTTP callback unchanged)

### Chain Execution Integration

**Current Chain Flow:**
```
ChainItem[] -> delay -> sendPrompt() -> wait for completion -> next item
```

**Embedded Terminal Changes:**
- Delay timing remains same
- Completion detection via hook or JSONL monitoring
- Session targeting uses internal session ID instead of window ID

**No changes to:**
- ChainItem model
- PromptChain model
- Chain execution logic

### Screenshot Annotation Integration

**Current Flow:**
```
ScreenshotWatcherService -> annotation UI -> paste to Terminal.app via clipboard
```

**New Flow:**
```
ScreenshotWatcherService -> annotation UI -> send to embedded session directly
```

**Benefits:**
- No clipboard manipulation needed
- Can reference session directly
- Faster dispatch (no AppleScript overhead)

### Prompt Library Integration

**No changes required:**
- Prompt model unchanged
- PlaceholderResolver works identically
- Template syntax unchanged
- Only dispatch target changes

### Project Integration

**Current:**
```
Project.path -> find matching Terminal.app window by name
```

**New:**
```
Project.path -> session working directory -> direct association
```

**Enhancement opportunity:**
- Store session IDs on Project model
- Auto-resume project sessions on app launch
- One-click "new session for project"

## Feature Dependency Graph

```
                    +-------------------------+
                    |   SwiftTerm Package     |
                    |   (External Dependency) |
                    +-----------+-------------+
                                |
                    +-----------v-------------+
                    |  EmbeddedTerminalView   |
                    |  (Wraps SwiftTerm)      |
                    +-----------+-------------+
                                |
          +---------------------+---------------------+
          |                     |                     |
+---------v---------+ +---------v---------+ +---------v---------+
| ProcessRegistry   | | SessionMetadata   | | TerminalTheme     |
| (PID tracking)    | | (Persistence)     | | (Colors, fonts)   |
+---------+---------+ +---------+---------+ +-------------------+
          |                     |
          +----------+----------+
                     |
          +----------v----------+
          |  SessionManager     |
          |  (Multi-session)    |
          +----------+----------+
                     |
    +----------------+----------------+
    |                |                |
+---v----+    +------v------+   +-----v-----+
| Queue  |    |   Chain     |   |  Direct   |
| Exec   |    |   Exec      |   |  Dispatch |
+--------+    +-------------+   +-----------+
```

## Implementation Order Recommendation

Based on dependencies and user requirements:

**Phase 1: Terminal Core**
1. SwiftTerm integration with safe wrapper
2. Single embedded terminal view
3. Basic process lifecycle (spawn, terminate)
4. Input dispatch (replace AppleScript)

**Phase 2: Multi-Session**
1. Session registry (track multiple terminals)
2. Split-pane UI with session list
3. Session selection/focus
4. Full-screen toggle

**Phase 3: Persistence**
1. Session metadata storage (SwiftData or SQLite)
2. Session resume on app launch
3. Project-session association

**Phase 4: Polish**
1. JSONL monitoring for rich status
2. Context window display (optional)
3. Theme customization

## Complexity Estimates

| Feature | Effort | Risk | Notes |
|---------|--------|------|-------|
| SwiftTerm integration | 2-3 days | Medium | Need safe wrapper pattern |
| Process lifecycle | 2-3 days | Medium | PID tracking, cleanup |
| Multi-session UI | 3-4 days | Low | Standard SwiftUI layout |
| Session persistence | 2-3 days | Low | SwiftData experience exists |
| Resume capability | 1-2 days | Low | Just `-r` flag handling |
| Queue/Chain integration | 2-3 days | Low | Replace service calls |
| Full-screen mode | 1 day | Low | Window state toggle |

**Total Estimate:** 13-19 days for table stakes features

## Sources

- https://github.com/jamesrochabrun/AgentHub (MIT license) - Primary reference
- https://github.com/jamesrochabrun/AgentHub/blob/main/app/modules/AgentHubCore/Sources/AgentHub/UI/EmbeddedTerminalView.swift - Terminal implementation
- https://github.com/jamesrochabrun/AgentHub/blob/main/app/modules/AgentHubCore/Sources/AgentHub/Services/TerminalLauncher.swift - Process launching
- https://github.com/jamesrochabrun/AgentHub/blob/main/app/modules/AgentHubCore/Sources/AgentHub/Services/TerminalProcessRegistry.swift - PID management
- https://github.com/jamesrochabrun/AgentHub/blob/main/app/modules/AgentHubCore/Sources/AgentHub/Services/CLISessionMonitorService.swift - Session monitoring
- https://github.com/jamesrochabrun/AgentHub/blob/main/app/modules/AgentHubCore/Sources/AgentHub/Services/SessionJSONLParser.swift - JSONL format
- https://github.com/jamesrochabrun/AgentHub/blob/main/app/modules/AgentHubCore/Sources/AgentHub/Services/SessionMetadataStore.swift - Persistence
- https://github.com/jamesrochabrun/AgentHub/blob/main/app/modules/AgentHubCore/Sources/AgentHub/ViewModels/CLISessionsViewModel.swift - State management
- https://github.com/migueldeicaza/SwiftTerm - Terminal emulator library (inferred from AgentHub usage)

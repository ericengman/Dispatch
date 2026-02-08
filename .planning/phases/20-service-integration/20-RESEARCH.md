# Phase 20: Service Integration - Research

**Researched:** 2026-02-08
**Domain:** Integration of embedded terminal dispatch with existing queue and chain execution infrastructure
**Confidence:** HIGH

## Summary

Phase 20 integrates the embedded terminal (built in phases 14-19) with Dispatch's existing queue and chain execution services. The core challenge is creating a unified dispatch interface that works with both embedded terminals (PTY-based, preferred) and Terminal.app (AppleScript-based, fallback), while maintaining all existing queue/chain features including delays, placeholders, completion detection, and multi-session support.

The existing architecture provides solid foundations: ExecutionManager already has a bridge pattern (via EmbeddedTerminalBridge), ExecutionStateMachine handles state transitions (IDLE → SENDING → EXECUTING → COMPLETED), and both QueueViewModel and ChainViewModel delegate to ExecutionManager.execute(). The key insight from Phase 17-04 is that ExecutionManager.execute() already checks EmbeddedTerminalBridge.isAvailable and dispatches to either embedded terminal or Terminal.app fallback.

The gap to close: While single prompt execution works via ExecutionManager, queue and chain execution need the same dispatch logic integrated. Currently, both QueueViewModel and ChainViewModel call ExecutionManager.execute(), which already has the embedded terminal dispatch path. The integration work is ensuring multi-session targeting, session-aware completion detection, and proper state transitions work correctly across all execution paths.

**Primary recommendation:** Verify existing integration points (queue/chain already use ExecutionManager), extend EmbeddedTerminalBridge for session-aware dispatch if not already complete, ensure ExecutionStateMachine handles session-specific monitoring, and test the complete execution flow from queue/chain through to embedded terminal completion.

## Standard Stack

The established services for this integration domain:

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| ExecutionManager | (Dispatch) | High-level execution orchestrator | Single entry point for all prompt execution (queue, chain, manual) |
| ExecutionStateMachine | (Dispatch) | State machine (IDLE → SENDING → EXECUTING → COMPLETED) | Manages lifecycle, timeout, cancellation across all execution types |
| EmbeddedTerminalBridge | (Dispatch) | Bridge from services to terminal coordinators | Decouples ExecutionManager from SwiftUI terminal views |
| QueueViewModel | (Dispatch) | Queue execution logic | Calls ExecutionManager.execute() for each queue item |
| ChainViewModel | (Dispatch) | Chain execution logic | Calls ExecutionManager.execute() for each chain step with delays |
| TerminalSessionManager | (Dispatch) | Multi-session registry | Maps session UUIDs to coordinators and terminals |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| HookServer | (Dispatch) | HTTP server for completion hooks (port 19847) | Primary completion detection for both Terminal.app and embedded terminal |
| ClaudeCodeLauncher | (Dispatch) | Pattern-based completion detection | Fallback/complement to HookServer via isClaudeCodeIdle() |
| PlaceholderResolver | (Dispatch) | Resolves {{placeholder}} syntax | Queue/chain execute must resolve before dispatch |
| TerminalService | (Dispatch) | AppleScript-based Terminal.app control | Fallback when embedded terminal unavailable |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Bridge pattern (current) | Direct coupling ExecutionManager → EmbeddedTerminalView | Bridge allows services to stay actor-isolated, decoupled from @MainActor views |
| Single ExecutionManager | Separate QueueExecutor, ChainExecutor | Unified manager reduces duplication, ensures consistent state machine usage |
| Session-aware dispatch | Always dispatch to active session | Session targeting needed for multi-terminal queue execution (future feature) |

**Installation:**
All components already integrated. No new dependencies required.

## Architecture Patterns

### Recommended Service Structure
```
Dispatch/Services/
├── ExecutionManager.swift           # High-level execute() orchestrator
├── ExecutionStateMachine.swift      # State machine for lifecycle
├── EmbeddedTerminalBridge.swift     # Multi-session coordinator registry
├── TerminalSessionManager.swift     # Session collection management
└── TerminalService.swift            # Terminal.app fallback

Dispatch/ViewModels/
├── QueueViewModel.swift             # Queue management → ExecutionManager
└── ChainViewModel.swift             # Chain management → ExecutionManager
```

### Pattern 1: Unified Dispatch Interface
**What:** Single execute() method that handles both embedded terminal and Terminal.app
**When to use:** All prompt execution (manual, queue, chain)
**Example:**
```swift
// Source: Dispatch/Services/ExecutionStateMachine.swift (lines 439-532)
@MainActor
final class ExecutionManager: ObservableObject {
    func execute(
        content: String,
        title: String = "Prompt",
        targetWindowId: String? = nil,
        targetWindowName: String? = nil,
        isFromChain: Bool = false,
        chainName: String? = nil,
        chainStepIndex: Int? = nil,
        chainTotalSteps: Int? = nil,
        useHooks: Bool = true,
        sendDelay: TimeInterval = 0.1
    ) async throws {
        // Check if embedded terminal is available (preferred)
        let bridge = EmbeddedTerminalBridge.shared

        if bridge.isAvailable {
            // Use embedded terminal (PTY dispatch)
            let dispatched = bridge.dispatchPrompt(content)
            guard dispatched else {
                throw TerminalServiceError.scriptExecutionFailed("Embedded terminal dispatch failed")
            }

            stateMachine.beginExecuting()

            // Start embedded terminal monitoring
            if let terminal = bridge.activeTerminal {
                stateMachine.startEmbeddedTerminalMonitoring(terminal: terminal)
            }
        } else {
            // Fall back to Terminal.app (AppleScript)
            try await terminalService.sendPrompt(content, toWindowId: targetWindowId, delay: sendDelay)
            stateMachine.beginExecuting()
            stateMachine.startPolling(windowId: targetWindowId, interval: 2.0)
        }
    }
}
```

**Key insight:** This pattern already exists! Queue and chain just need to call ExecutionManager.execute().

### Pattern 2: Session-Aware Bridge Dispatch
**What:** EmbeddedTerminalBridge maintains registry of session ID → coordinator mappings
**When to use:** Multi-session environments where dispatch must target specific session
**Example:**
```swift
// Source: Dispatch/Services/EmbeddedTerminalBridge.swift (lines 39-87)
@MainActor
final class EmbeddedTerminalBridge: ObservableObject {
    // Multi-session registry
    private var sessionCoordinators: [UUID: EmbeddedTerminalView.Coordinator] = [:]
    private var sessionTerminals: [UUID: LocalProcessTerminalView] = [:]

    // Legacy single-session API (backward compatibility)
    @Published private(set) var activeCoordinator: EmbeddedTerminalView.Coordinator?
    @Published private(set) var activeTerminal: LocalProcessTerminalView?

    // Session-aware registration
    func register(sessionId: UUID, coordinator: EmbeddedTerminalView.Coordinator, terminal: LocalProcessTerminalView) {
        sessionCoordinators[sessionId] = coordinator
        sessionTerminals[sessionId] = terminal
    }

    // Session-aware dispatch
    func dispatchPrompt(_ prompt: String, to sessionId: UUID) -> Bool {
        guard let coordinator = sessionCoordinators[sessionId] else {
            return false
        }
        return coordinator.dispatchPrompt(prompt)
    }

    // Legacy dispatch (uses TerminalSessionManager.activeSessionId)
    func dispatchPrompt(_ prompt: String) -> Bool {
        if let sessionId = TerminalSessionManager.shared.activeSessionId {
            return dispatchPrompt(prompt, to: sessionId)
        }
        // Fallback to legacy activeCoordinator
        return activeCoordinator?.dispatchPrompt(prompt) ?? false
    }
}
```

**Key insight:** Bridge already supports multi-session! Legacy API delegates to session-aware API using TerminalSessionManager.activeSessionId.

### Pattern 3: Queue Execution via ExecutionManager
**What:** Queue items dispatch through ExecutionManager for unified state machine
**When to use:** All queue execution (run next, run all)
**Example:**
```swift
// Source: Dispatch/ViewModels/QueueViewModel.swift (lines 261-304)
private func executeItem(_ item: QueueItem) async {
    guard let content = item.effectiveContent else {
        item.markFailed(error: "No content")
        return
    }

    isExecuting = true
    currentExecutingItem = item
    item.markExecuting()

    do {
        // Resolve placeholders
        let resolveResult = await PlaceholderResolver.shared.autoResolve(text: content)

        if !resolveResult.isFullyResolved {
            throw PromptError.unresolvedPlaceholders(resolveResult.unresolvedPlaceholders.map(\.name))
        }

        // Execute via ExecutionManager (handles embedded terminal vs Terminal.app)
        try await ExecutionManager.shared.execute(
            content: resolveResult.resolvedText,
            title: item.displayTitle,
            targetWindowId: item.targetTerminalId,
            targetWindowName: item.targetTerminalName
        )

        // Wait for completion signal from ExecutionStateMachine

    } catch {
        item.markFailed(error: error.localizedDescription)
        isExecuting = false
        currentExecutingItem = nil
    }
}
```

**Key insight:** Queue already uses ExecutionManager! Integration is complete for queue execution.

### Pattern 4: Chain Execution with Delays
**What:** Chain steps execute sequentially through ExecutionManager with configurable delays
**When to use:** Chain execution (play, step-through)
**Example:**
```swift
// Source: Dispatch/ViewModels/ChainViewModel.swift (lines 240-328)
func startExecution(of chain: PromptChain, targetWindowId: String? = nil) async {
    executionTask = Task {
        let items = chain.sortedItems

        for (index, item) in items.enumerated() {
            guard !Task.isCancelled else { break }

            // Check if paused
            while case .paused = executionState {
                if Task.isCancelled { break }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }

            currentStepIndex = index
            executionState = .running(currentStep: index, totalSteps: items.count)

            do {
                try await executeItem(item, index: index, totalSteps: items.count, targetWindowId: targetWindowId)

                // Wait for delay before next step
                if item.delaySeconds > 0 && index < items.count - 1 {
                    try await Task.sleep(nanoseconds: UInt64(item.delaySeconds) * 1_000_000_000)
                }

            } catch {
                executionState = .failed(error: error.localizedDescription)
                return
            }
        }

        executionState = .completed
    }
}

private func executeItem(_ item: ChainItem, index: Int, totalSteps: Int, targetWindowId: String?) async throws {
    guard let content = item.effectiveContent else {
        throw ExecutionError.chainItemInvalid
    }

    // Resolve placeholders
    let resolveResult = await PlaceholderResolver.shared.autoResolve(text: content)

    if !resolveResult.isFullyResolved {
        throw PromptError.unresolvedPlaceholders(resolveResult.unresolvedPlaceholders.map(\.name))
    }

    // Execute through ExecutionManager
    try await ExecutionManager.shared.execute(
        content: resolveResult.resolvedText,
        title: item.displayTitle,
        targetWindowId: targetWindowId,
        isFromChain: true,
        chainName: currentExecutingChain?.name,
        chainStepIndex: index,
        chainTotalSteps: totalSteps
    )

    // Wait for completion
    while ExecutionStateMachine.shared.state == .executing {
        try await Task.sleep(nanoseconds: 100_000_000)  // 0.1s
    }
}
```

**Key insight:** Chain already uses ExecutionManager! Delays handled at chain level, execution delegated to unified manager.

### Pattern 5: Dual Completion Detection (Hook + Pattern)
**What:** HookServer (primary) + terminal pattern matching (fallback) for robust completion detection
**When to use:** All execution types, both embedded terminal and Terminal.app
**Example:**
```swift
// Source: Dispatch/Services/ExecutionStateMachine.swift (lines 338-368, 370-381)

// Pattern-based monitoring (fallback/complement)
func startEmbeddedTerminalMonitoring(terminal: LocalProcessTerminalView, interval: TimeInterval = 1.5) {
    guard state == .executing else { return }

    pollingTask = Task {
        while !Task.isCancelled && state == .executing {
            try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))

            guard !Task.isCancelled else { break }

            // Check for completion pattern
            if ClaudeCodeLauncher.shared.isClaudeCodeIdle(in: terminal) {
                logInfo("Completion detected via embedded terminal pattern", category: .execution)
                await MainActor.run {
                    self.markCompleted(result: .success)
                }
                break
            }
        }
    }
}

// Hook-based notification (primary)
func handleHookCompletion(sessionId: String?) {
    guard state == .executing else {
        logDebug("Ignoring hook completion in state: \(state)", category: .execution)
        return
    }

    logInfo("Completion detected via hook (session: \(sessionId ?? "unknown"))", category: .execution)
    markCompleted(result: .success)
}
```

**Key insight:** Dual detection already implemented! HookServer receives POST from Claude Code stop hook, pattern matching provides fallback.

### Anti-Patterns to Avoid

- **Direct terminal access from ViewModels:** Queue/Chain should never directly access EmbeddedTerminalView - always go through ExecutionManager → EmbeddedTerminalBridge
- **Skipping ExecutionStateMachine:** All execution must use the state machine to ensure timeout, cancellation, and completion detection work
- **Per-service dispatch logic:** Don't duplicate embedded vs Terminal.app logic in queue/chain - keep it centralized in ExecutionManager
- **Ignoring multi-session:** Even if only one session active, use session-aware APIs to future-proof

## Don't Hand-Roll

Problems that look simple but have existing solutions:

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Queue → terminal dispatch | Custom dispatch in QueueViewModel | ExecutionManager.execute() | Already handles embedded/fallback, state machine, timeouts |
| Chain → terminal dispatch | Custom dispatch in ChainViewModel | ExecutionManager.execute() | Same unified logic, reuses state machine |
| Session targeting | Track active session in each ViewModel | TerminalSessionManager.activeSessionId | Single source of truth for active session |
| Completion detection | Poll terminal in ViewModels | ExecutionStateMachine monitoring | Centralized timeout, dual detection (hook + pattern) |
| Multi-session dispatch | Find coordinator in ViewModels | EmbeddedTerminalBridge registry | Bridge already maps session UUID → coordinator |

**Key insight:** Most integration work is already complete. The existing ExecutionManager → EmbeddedTerminalBridge → Coordinator path works for queue and chain because they already call ExecutionManager.execute().

## Common Pitfalls

### Pitfall 1: Assuming Queue/Chain Need New Dispatch Logic
**What goes wrong:** Duplicating embedded terminal dispatch logic in QueueViewModel/ChainViewModel
**Why it happens:** Not recognizing that ExecutionManager already handles dispatch routing
**How to avoid:** Review QueueViewModel.executeItem() and ChainViewModel.executeItem() - they already call ExecutionManager.execute()
**Warning signs:** Finding duplicate bridge.isAvailable checks or terminal.dispatchPrompt() calls outside ExecutionManager

### Pitfall 2: Ignoring Multi-Session Architecture
**What goes wrong:** Using EmbeddedTerminalBridge legacy API (activeCoordinator) instead of session-aware API
**Why it happens:** Phase 17 created single-session bridge, Phase 18 added multi-session, legacy API maintained for backward compatibility
**How to avoid:** Use session-aware dispatch where possible: bridge.dispatchPrompt(content, to: sessionId)
**Warning signs:** Dispatch failing when multiple sessions exist, always dispatching to first-created session

### Pitfall 3: Race Condition Between Hook and Pattern Detection
**What goes wrong:** Both HookServer and pattern matching call markCompleted(), causing double-completion
**Why it happens:** Pattern monitoring runs continuously while waiting for hook
**How to avoid:** ExecutionStateMachine.handleHookCompletion() already guards with `state == .executing` check - only first completion wins
**Warning signs:** Logs showing "Ignoring hook completion in state: completed"

### Pitfall 4: Missing Placeholder Resolution
**What goes wrong:** Queue/chain items with {{placeholders}} fail silently or error without resolution
**Why it happens:** Forgetting to call PlaceholderResolver.autoResolve() before execute()
**How to avoid:** Both QueueViewModel and ChainViewModel already call autoResolve() - verify this step isn't skipped
**Warning signs:** Prompts arriving at Claude Code with literal "{{clipboard}}" text

### Pitfall 5: State Machine Not Transitioning Correctly
**What goes wrong:** ExecutionStateMachine stuck in .executing after completion, blocking queue/chain
**Why it happens:** Pattern monitoring or hook not calling markCompleted(), or monitoring task never started
**How to avoid:** Ensure ExecutionManager starts monitoring (either startEmbeddedTerminalMonitoring or startPolling) after beginExecuting()
**Warning signs:** Queue "Run All" stopping after first item, chain execution hanging mid-sequence

## Code Examples

Verified patterns from existing codebase:

### Queue Execution Flow (End-to-End)
```swift
// Source: Dispatch/ViewModels/QueueViewModel.swift
// User action: Click "Run Next" in queue panel

func runNext() async {
    guard let nextItem = items.first(where: { $0.isReady }) else { return }
    await executeItem(nextItem)
}

private func executeItem(_ item: QueueItem) async {
    guard let content = item.effectiveContent else {
        item.markFailed(error: "No content")
        return
    }

    isExecuting = true
    item.markExecuting()

    // 1. Resolve placeholders
    let resolveResult = await PlaceholderResolver.shared.autoResolve(text: content)
    guard resolveResult.isFullyResolved else {
        throw PromptError.unresolvedPlaceholders(...)
    }

    // 2. Execute via unified manager (handles embedded vs Terminal.app)
    try await ExecutionManager.shared.execute(
        content: resolveResult.resolvedText,
        title: item.displayTitle,
        targetWindowId: item.targetTerminalId,
        targetWindowName: item.targetTerminalName
    )

    // ExecutionManager will:
    // - Check EmbeddedTerminalBridge.isAvailable
    // - If available: bridge.dispatchPrompt() → embedded terminal PTY
    // - If not: TerminalService.sendPrompt() → Terminal.app AppleScript
    // - Start completion monitoring (pattern or polling)

    // ExecutionStateMachine will:
    // - Transition IDLE → SENDING → EXECUTING
    // - Monitor for completion (hook or pattern)
    // - Call completionHandler when done
    // - Transition EXECUTING → COMPLETED → IDLE
}

// Completion handler (registered in setupExecutionObserver)
ExecutionStateMachine.shared.onCompletion { result in
    switch result {
    case .success:
        currentItem.markCompleted()
        modelContext.delete(currentItem) // Remove from queue
    case .failure(let error):
        currentItem.markFailed(error: error.localizedDescription)
    case .cancelled:
        currentItem.reset()
    }
}
```

### Chain Execution Flow (End-to-End)
```swift
// Source: Dispatch/ViewModels/ChainViewModel.swift
// User action: Click "Play" on a chain

func startExecution(of chain: PromptChain, targetWindowId: String? = nil) async {
    executionTask = Task {
        for (index, item) in chain.sortedItems.enumerated() {
            guard !Task.isCancelled else { break }

            // Check pause state
            while case .paused = executionState {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }

            executionState = .running(currentStep: index, totalSteps: items.count)

            // 1. Resolve placeholders
            let resolveResult = await PlaceholderResolver.shared.autoResolve(text: content)

            // 2. Execute via unified manager (same path as queue)
            try await ExecutionManager.shared.execute(
                content: resolveResult.resolvedText,
                title: item.displayTitle,
                targetWindowId: targetWindowId,
                isFromChain: true,
                chainName: chain.name,
                chainStepIndex: index,
                chainTotalSteps: items.count
            )

            // 3. Wait for completion (poll ExecutionStateMachine.state)
            while ExecutionStateMachine.shared.state == .executing {
                try await Task.sleep(nanoseconds: 100_000_000)
            }

            // 4. Check result
            if case .failure(let error) = ExecutionStateMachine.shared.lastResult {
                throw error
            }

            // 5. Apply delay before next step
            if item.delaySeconds > 0 && index < items.count - 1 {
                try await Task.sleep(nanoseconds: UInt64(item.delaySeconds) * 1_000_000_000)
            }
        }

        executionState = .completed
    }
}
```

### Multi-Session Dispatch (Session-Aware)
```swift
// Source: Dispatch/Services/EmbeddedTerminalBridge.swift
// Future enhancement: target specific session instead of always using active

// Current (legacy): Always dispatches to active session
func dispatchPrompt(_ prompt: String) -> Bool {
    // Uses TerminalSessionManager.shared.activeSessionId internally
    if let sessionId = TerminalSessionManager.shared.activeSessionId {
        return dispatchPrompt(prompt, to: sessionId)
    }
    return activeCoordinator?.dispatchPrompt(prompt) ?? false
}

// Future: Queue items could target specific sessions
func executeItem(_ item: QueueItem) async {
    // If item.targetSessionId is set, use session-aware dispatch
    if let sessionId = item.targetSessionId {
        let bridge = EmbeddedTerminalBridge.shared
        if bridge.isAvailable(sessionId: sessionId) {
            _ = bridge.dispatchPrompt(content, to: sessionId)
            // ... start session-specific monitoring
        }
    } else {
        // Default: dispatch to active session (current behavior)
        try await ExecutionManager.shared.execute(...)
    }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| AppleScript-only dispatch | Embedded terminal (PTY) preferred, AppleScript fallback | Phase 17 | Faster dispatch, no Terminal.app focus stealing, direct PTY control |
| Single terminal instance | Multi-session registry (UUID-keyed) | Phase 18 | Support 2-4 simultaneous Claude Code sessions |
| Polling-only completion | Dual detection (HookServer + pattern) | Phase 9, 17 | More reliable completion, faster detection, fallback for hook failures |
| Direct TerminalService calls | Unified ExecutionManager.execute() | Phase 17-04 | Consistent dispatch logic, easier to maintain, single state machine |
| In-memory session state | SwiftData persistence | Phase 19 | Sessions survive app restart, resume previous Claude Code sessions |

**Deprecated/outdated:**
- Direct TerminalService.sendPrompt() from ViewModels: Use ExecutionManager.execute() instead
- Accessing EmbeddedTerminalView directly from services: Use EmbeddedTerminalBridge registry
- Single-session assumptions in dispatch logic: Use session-aware APIs with UUID targeting

## Open Questions

Things that couldn't be fully resolved:

1. **Queue Item Session Targeting**
   - What we know: QueueItem has targetTerminalId/targetTerminalName (Terminal.app window targeting)
   - What's unclear: Should queue items target specific embedded terminal sessions? QueueItem model doesn't have targetSessionId field
   - Recommendation: Current behavior (always dispatch to active session) is acceptable for Phase 20. Add targetSessionId to QueueItem in future phase if multi-session queue dispatch is needed

2. **Chain Execution Session Pinning**
   - What we know: ChainViewModel.startExecution() accepts targetWindowId for Terminal.app fallback
   - What's unclear: Should chains be pinned to the session where they started, or follow active session changes?
   - Recommendation: Current behavior (use active session at time of execution) is acceptable. Consider session pinning if users report confusion from mid-chain session switches

3. **Completion Detection Session Matching**
   - What we know: HookServer receives sessionId in POST payload, ExecutionStateMachine.handleHookCompletion(sessionId:) accepts it
   - What's unclear: Does state machine validate that completion hook matches the currently executing session?
   - Recommendation: Verify that sessionId validation exists, or add check to prevent completion from wrong session

4. **Multi-Session "Run All Queue" Behavior**
   - What we know: Queue "Run All" dispatches sequentially to ExecutionManager
   - What's unclear: Should queue items with different targetSessionId values execute in parallel across sessions?
   - Recommendation: Current sequential behavior is safer. Parallel multi-session execution is complex (what if one session fails? how to show multi-session progress?) - defer to future phase

## Sources

### Primary (HIGH confidence)
- Dispatch/Services/ExecutionStateMachine.swift - ExecutionManager.execute() implementation (lines 439-532)
- Dispatch/Services/EmbeddedTerminalBridge.swift - Multi-session registry pattern (lines 19-145)
- Dispatch/ViewModels/QueueViewModel.swift - Queue execution via ExecutionManager (lines 189-304)
- Dispatch/ViewModels/ChainViewModel.swift - Chain execution via ExecutionManager (lines 219-328)
- Dispatch/Services/TerminalSessionManager.swift - Session management and active session tracking (lines 1-340)
- Dispatch/Services/ClaudeCodeLauncher.swift - Pattern-based completion detection (lines 134-163)
- Dispatch/Services/HookServer.swift - HTTP server for completion hooks (lines 343-378)

### Secondary (MEDIUM confidence)
- .planning/phases/17-claude-code-integration/17-RESEARCH.md - Bridge pattern rationale
- .planning/phases/17-claude-code-integration/17-04-PLAN.md - ExecutionManager integration design
- .planning/phases/18-multi-session-ui/18-RESEARCH.md - Multi-session architecture patterns

### Tertiary (LOW confidence)
- None - all findings verified with codebase

## Metadata

**Confidence breakdown:**
- Queue integration: HIGH - QueueViewModel already uses ExecutionManager.execute()
- Chain integration: HIGH - ChainViewModel already uses ExecutionManager.execute()
- Multi-session dispatch: MEDIUM-HIGH - EmbeddedTerminalBridge has session-aware API, legacy API for backward compatibility
- Completion detection: HIGH - Dual detection (hook + pattern) implemented in ExecutionStateMachine
- Session targeting: MEDIUM - Active session targeting works, explicit session ID targeting exists but not fully wired for queue/chain

**Research date:** 2026-02-08
**Valid until:** 30 days (stable architecture, unlikely to change rapidly)

## Key Findings for Planning

### What Already Works
1. **Queue execution dispatches to embedded terminal** - QueueViewModel.executeItem() → ExecutionManager.execute() → EmbeddedTerminalBridge.dispatchPrompt()
2. **Chain execution dispatches to embedded terminal** - ChainViewModel.executeItem() same flow
3. **ExecutionStateMachine handles embedded terminal monitoring** - startEmbeddedTerminalMonitoring() polls terminal buffer for completion patterns
4. **HookServer completion detection works** - handleHookCompletion() called when POST received on /hook/complete
5. **Multi-session registry exists** - EmbeddedTerminalBridge tracks sessionId → coordinator/terminal mappings
6. **Placeholder resolution integrated** - Both queue and chain call PlaceholderResolver.autoResolve() before execute()

### What Needs Verification/Testing
1. **Multi-session targeting** - Verify dispatch goes to correct session when multiple sessions active
2. **Session-specific completion** - Verify hook completion matches executing session ID
3. **Queue "Run All" with embedded terminal** - Test sequential execution completes each item before starting next
4. **Chain delays with embedded terminal** - Test configured delays work correctly between steps
5. **Fallback to Terminal.app** - Verify AppleScript dispatch still works when no embedded terminal available
6. **State machine transitions** - Verify no race conditions between hook and pattern detection

### What Might Need Implementation
1. **EmbeddedTerminalService class** - Requirement INTG-01 asks for explicit service class, but EmbeddedTerminalBridge might already fulfill this role
2. **Session ID validation in completion handler** - Ensure completion hooks match executing session
3. **Multi-session queue targeting** - Add targetSessionId to QueueItem if explicit session targeting needed (currently uses active session)
4. **Error handling for session not found** - Handle case where targetSessionId doesn't exist in registry

**Recommended Next Steps:**
1. Review INTG-01 requirement - determine if EmbeddedTerminalBridge counts as "service implementing dispatch interface" or if new wrapper needed
2. Test current integration with multi-session scenarios
3. Add any missing session validation logic
4. Document any edge cases discovered during testing

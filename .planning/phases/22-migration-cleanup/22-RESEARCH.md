# Phase 22: Migration & Cleanup - Research

**Researched:** 2026-02-08
**Domain:** Code migration, service deprecation, permission cleanup
**Confidence:** HIGH

## Summary

This phase completes the v2.0 transition by removing Terminal.app dependencies and consolidating on the embedded terminal system built in Phases 14-21. The migration involves deprecating AppleScript-based TerminalService methods, updating ExecutionManager to use only EmbeddedTerminalService, removing UI controls for Terminal.app, and cleaning up Info.plist permissions.

The codebase already has the infrastructure in place: EmbeddedTerminalService wraps EmbeddedTerminalBridge (Phase 20), ExecutionManager checks `EmbeddedTerminalService.isAvailable` and falls back to Terminal.app (Phase 17), and MainView includes the embedded terminal panel. This phase removes the fallback path and legacy UI.

**Primary recommendation:** Use Swift's `@available(*, deprecated)` annotation for gradual migration, maintain TerminalService as deprecated (not deleted) for one version cycle, and remove NSAppleEventsUsageDescription from Info.plist to eliminate permission prompts.

## Standard Stack

### Core Libraries (Already Integrated)

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| SwiftTerm | 1.10.1 | Terminal emulation | Proven PTY-based terminal, used in AgentHub |
| LocalProcess | (SwiftTerm) | Process management | PTY spawning, process lifecycle |
| SwiftData | macOS 14.0+ | Data persistence | Modern replacement for Core Data |

### Supporting Infrastructure (Already Built)

| Component | Location | Purpose | When to Use |
|-----------|----------|---------|-------------|
| EmbeddedTerminalBridge | Services/ | Session registry | Multi-session prompt dispatch |
| EmbeddedTerminalService | Services/ | Service-layer wrapper | Primary dispatch interface |
| ExecutionStateMachine | Services/ | State management | Queue/chain execution |
| TerminalSessionManager | Services/ | Session lifecycle | Multi-session UI coordination |

### No New Dependencies Required

All infrastructure for embedded terminal execution is already in place. This phase removes code rather than adding libraries.

## Architecture Patterns

### Deprecation-Based Migration Pattern

The standard approach for removing major features from Swift apps:

```swift
// Step 1: Mark as deprecated with guidance
@available(*, deprecated, message: "Use EmbeddedTerminalService instead. Terminal.app support will be removed in v3.0.")
actor TerminalService {
    // Keep implementation intact for one version cycle
}

// Step 2: Update call sites to check for deprecation
#if DEBUG
#warning("TerminalService is deprecated - update to EmbeddedTerminalService")
#endif
```

**When to use:** Gradual migration where existing code continues to work but warns developers.

### Facade/Adapter Removal Pattern

Current architecture uses adapter pattern where ExecutionManager checks availability:

```swift
// Current (Phase 17-21):
if embeddedService.isAvailable {
    // Use embedded terminal
} else {
    // Fall back to Terminal.app
}

// After Phase 22:
// Remove fallback entirely, embedded-only
let dispatched = embeddedService.dispatchPrompt(content)
guard dispatched else {
    throw ExecutionError.noTerminalAvailable
}
```

**Key insight:** ExecutionManager is already designed with this branching logic, making removal straightforward.

### UI Conditional Rendering Cleanup

MainView already shows embedded terminal panel. No major restructuring needed:

```swift
// Current:
if showTerminal && !isFileViewerActive {
    HSplitView {
        contentWrapper
        MultiSessionTerminalView()
    }
}

// After Phase 22: Same structure, just remove Terminal.app controls
// No "Open Terminal.app" buttons, no window selection dropdowns
```

### Permission Cleanup Pattern

Info.plist entries that request permissions persist until explicitly removed:

```xml
<!-- Current Info.plist -->
<key>NSAppleEventsUsageDescription</key>
<string>Dispatch needs to control Terminal.app to send prompts to Claude Code.</string>

<!-- After Phase 22: Remove this key entirely -->
<!-- macOS will no longer prompt for Terminal.app automation -->
```

**Critical:** Users who granted permission previously will retain it in TCC database, but new installs won't be prompted.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Gradual API migration | Custom warning system | `@available(*, deprecated)` | Xcode integration, automatic fix-its |
| Permission revocation | Custom TCC reset scripts | Remove Info.plist keys | macOS handles cleanup automatically on reinstall |
| Service abstraction | Complex factory patterns | Simple protocol with single impl | Over-engineering for migration phase |
| Version checking | Manual version comparisons | Git tags + release notes | Standard release management |

**Key insight:** Swift and macOS provide built-in migration tools. Use them instead of custom solutions.

## Common Pitfalls

### Pitfall 1: Immediate Deletion of Deprecated Code

**What goes wrong:** Deleting TerminalService entirely breaks any code that hasn't been updated yet, creates merge conflicts, and prevents rollback if issues are found.

**Why it happens:** Eager cleanup without considering transition period or rollback scenarios.

**How to avoid:**
- Mark TerminalService as `@available(*, deprecated)` but keep implementation
- Plan removal for next major version (v3.0)
- Document migration path in deprecation message

**Warning signs:** Compiler errors in code you didn't modify, sudden inability to build project.

### Pitfall 2: Removing Permissions Without Testing Fresh Install

**What goes wrong:** Removing NSAppleEventsUsageDescription causes no issues for existing users (permission already granted), but fresh installs fail silently if code still calls Terminal.app.

**Why it happens:** Testing only with development environment where permissions already exist.

**How to avoid:**
- Create fresh test user account on macOS
- Install app from scratch (not Xcode run)
- Verify no Terminal.app permission prompts appear
- Test all execution paths (queue, chain, direct dispatch)

**Warning signs:** Bug reports from new users about "automation permission denied" errors.

### Pitfall 3: Forgetting UI References to Terminal.app

**What goes wrong:** Backend code migrated to embedded terminal, but UI still shows "Select Terminal Window" dropdowns, "Open Terminal.app" buttons, or references to AppleScript execution.

**Why it happens:** UI and service layer updated separately, incomplete search for all references.

**How to avoid:**
- Search codebase for "Terminal.app", "AppleScript", "window", "activate"
- Audit all ViewModels for Terminal.app-related state
- Check toolbar buttons, context menus, settings panels
- Review accessibility labels and help text

**Warning signs:** UI elements that do nothing when clicked, error messages referencing Terminal.app.

### Pitfall 4: Breaking Existing QueueItem/ChainItem Terminal References

**What goes wrong:** QueueItem model has `targetTerminalId` and `targetTerminalName` fields for Terminal.app windows. Migration removes support but doesn't migrate data or handle legacy values.

**Why it happens:** Focus on code migration without considering persisted data.

**How to avoid:**
- Keep model fields but mark as deprecated
- ExecutionManager ignores these fields (they become no-ops)
- Don't break SwiftData schema by removing fields yet
- Plan data migration for v3.0 when TerminalService is fully removed

**Warning signs:** SwiftData migration errors, crashes when loading old queue items.

### Pitfall 5: Incomplete ExecutionManager Branching Removal

**What goes wrong:** Removing `terminalService` reference but leaving conditional checks causes runtime crashes or unreachable code.

**Why it happens:** Partial refactoring that doesn't follow all code paths.

**How to avoid:**
- Identify all branching points: `if embeddedService.isAvailable else { ... }`
- Remove entire else block, not just TerminalService calls
- Update error handling to reflect embedded-only execution
- Add guard statements for embedded terminal availability

**Warning signs:** Xcode warnings about unreachable code, nil unwrapping crashes.

## Code Examples

Verified patterns from project codebase and Swift best practices:

### Deprecating TerminalService

```swift
// Source: Swift API Availability (NSHipster) + project patterns
// File: Dispatch/Services/TerminalService.swift

@available(*, deprecated, message: "TerminalService is deprecated. Use EmbeddedTerminalService for embedded terminal dispatch. Terminal.app support will be removed in v3.0.")
actor TerminalService {
    static let shared = TerminalService()

    // Keep all existing methods with deprecation warnings
    @available(*, deprecated, renamed: "EmbeddedTerminalService.dispatchPrompt")
    func sendPrompt(_ content: String, toWindowId windowId: String? = nil) async throws {
        // Implementation remains for compatibility
        // ...
    }

    // Other methods similarly marked...
}
```

### Updating ExecutionManager to Embedded-Only

```swift
// Source: Current ExecutionManager.swift (modified)
// File: Dispatch/Services/ExecutionStateMachine.swift

@MainActor
final class ExecutionManager: ObservableObject {
    static let shared = ExecutionManager()

    private let stateMachine = ExecutionStateMachine.shared
    // Remove: private let terminalService = TerminalService.shared

    func execute(
        content: String,
        title: String = "Prompt",
        targetWindowId: String? = nil,  // Deprecated, ignored
        targetWindowName: String? = nil, // Deprecated, ignored
        isFromChain: Bool = false,
        chainName: String? = nil,
        chainStepIndex: Int? = nil,
        chainTotalSteps: Int? = nil,
        useHooks: Bool = true,
        sendDelay: TimeInterval = 0.1
    ) async throws {
        guard !content.isEmpty else {
            throw TerminalServiceError.invalidPromptContent
        }

        guard stateMachine.state == .idle else {
            throw ExecutionError.alreadyExecuting
        }

        let context = ExecutionContext(
            promptContent: content,
            promptTitle: title,
            targetWindowId: nil,  // No longer used
            targetWindowName: nil,
            isFromChain: isFromChain,
            chainName: chainName,
            chainStepIndex: chainStepIndex,
            chainTotalSteps: chainTotalSteps
        )

        stateMachine.beginSending(context: context)

        do {
            let embeddedService = EmbeddedTerminalService.shared

            // Remove fallback check - embedded only
            guard embeddedService.isAvailable else {
                throw ExecutionError.noTerminalAvailable
            }

            logInfo("Dispatching via embedded terminal", category: .execution)

            let dispatched = embeddedService.dispatchPrompt(content)
            guard dispatched else {
                throw TerminalServiceError.scriptExecutionFailed("Embedded terminal dispatch failed")
            }

            stateMachine.setExecutingSession(embeddedService.activeSessionId)
            stateMachine.beginExecuting()

            if let sessionId = embeddedService.activeSessionId,
               let terminal = embeddedService.getTerminal(for: sessionId) {
                stateMachine.startEmbeddedTerminalMonitoring(terminal: terminal)
            }

        } catch {
            logError("Execution failed: \(error)", category: .execution)
            stateMachine.markCompleted(result: .failure(error))
            throw error
        }
    }
}

// Add new error case
enum ExecutionError: Error, LocalizedError {
    case noTerminalAvailable

    var errorDescription: String? {
        switch self {
        case .noTerminalAvailable:
            return "No embedded terminal session available. Create a session to dispatch prompts."
        // ... other cases
        }
    }
}
```

### Removing UI Controls for Terminal.app

```swift
// Source: Current MainView.swift (modified)
// File: Dispatch/Views/MainView.swift

struct MainView: View {
    // Remove any Terminal.app-related state
    // @State private var selectedTerminalWindow: TerminalWindow?

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            // Execution state indicator (unchanged)
            if executionState.state.isActive {
                // ...
            }

            // Terminal toggle (unchanged - embedded terminal)
            Button {
                showTerminal.toggle()
            } label: {
                Label("Terminal", systemImage: showTerminal ? "terminal.fill" : "terminal")
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])

            // New session (unchanged)
            if showTerminal {
                Button {
                    _ = TerminalSessionManager.shared.createSession()
                } label: {
                    Label("New Session", systemImage: "plus.rectangle")
                }
                .keyboardShortcut("t", modifiers: .command)
                .disabled(!TerminalSessionManager.shared.canCreateSession)
            }

            // REMOVE: Any "Select Terminal Window" pickers
            // REMOVE: Any "Open Terminal.app" buttons
            // REMOVE: Any Terminal.app status indicators
        }
    }
}
```

### Info.plist Permission Cleanup

```bash
# Source: macOS permission management best practices
# Remove NSAppleEventsUsageDescription from Info.plist

# Option 1: Xcode project settings
# Target → Info → Custom macOS Application Target Properties
# Delete row: "Privacy - AppleEvents Sending Usage Description"

# Option 2: Command-line (if using .plist file directly)
/usr/libexec/PlistBuddy -c "Delete :NSAppleEventsUsageDescription" Info.plist

# Verify removal
plutil -p DerivedData/Dispatch-*/Build/Products/Debug/Dispatch.app/Contents/Info.plist | grep -i "apple\|automation"
# Should return nothing
```

### QueueViewModel/ChainViewModel - Ignoring Legacy Terminal Fields

```swift
// Source: Current QueueViewModel.swift (modified)
// File: Dispatch/ViewModels/QueueViewModel.swift

private func executeItem(_ item: QueueItem) async {
    guard let content = item.effectiveContent else {
        logError("Queue item has no content", category: .queue)
        item.markFailed(error: "No content")
        return
    }

    logInfo("Queue executing item: '\(item.displayTitle)' via ExecutionManager", category: .queue)

    isExecuting = true
    currentExecutingItem = item
    item.markExecuting()
    saveContext()

    do {
        let resolveResult = await PlaceholderResolver.shared.autoResolve(text: content)

        if !resolveResult.isFullyResolved {
            throw PromptError.unresolvedPlaceholders(resolveResult.unresolvedPlaceholders.map(\.name))
        }

        // Remove targetWindowId/targetWindowName parameters
        // ExecutionManager will dispatch to active embedded session
        try await ExecutionManager.shared.execute(
            content: resolveResult.resolvedText,
            title: item.displayTitle
            // targetWindowId and targetWindowName no longer used
        )

    } catch {
        await MainActor.run {
            item.markFailed(error: error.localizedDescription)
            self.error = error.localizedDescription
            self.isExecuting = false
            self.currentExecutingItem = nil
            self.saveContext()
            self.fetchItems()
        }
    }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| AppleScript Terminal.app control | PTY-based embedded terminal | Phase 14-17 (v2.0) | No external dependencies, better UX |
| NSAppleScript async execution | LocalProcess spawning | Phase 14-17 (v2.0) | Native Swift concurrency, no permission prompts |
| Single Terminal.app window | Multi-session embedded panels | Phase 18-19 (v2.0) | User controls sessions within app |
| Window ID targeting | Session UUID targeting | Phase 18-20 (v2.0) | Reliable session identity |
| AppleScript polling for completion | Hook + pattern monitoring | Phase 17 (v2.0) | Faster, more reliable detection |

**Deprecated/outdated:**
- **TerminalService actor**: Replaced by EmbeddedTerminalService. Keep as deprecated in v2.0, remove in v3.0.
- **NSAppleEventsUsageDescription**: Required for AppleScript automation. No longer needed with PTY-based execution.
- **targetTerminalId/targetTerminalName**: QueueItem and ChainItem fields for Terminal.app windows. Ignored in embedded-only execution.
- **Terminal window selection UI**: Pickers, dropdowns for choosing Terminal.app windows. Replaced by session tabs.

## Open Questions

### 1. Rollback Strategy if Embedded Terminal Has Issues

**What we know:**
- Embedded terminal is fully implemented and tested (Phases 14-21)
- Phase 21 included status monitoring and session lifecycle management
- Current ExecutionManager has fallback to Terminal.app

**What's unclear:**
- Should we keep TerminalService fallback code for emergency rollback?
- What's the deprecation timeline if we need to revert?

**Recommendation:**
- Keep TerminalService marked as `@available(*, deprecated)` for v2.0
- Monitor crash reports and user feedback for 1-2 releases
- If no major issues, remove entirely in v3.0
- If critical issues found, update deprecation message to "Terminal.app support reinstated temporarily"

### 2. User Communication About Terminal.app Removal

**What we know:**
- Users who installed v1.x have Terminal.app automation permission granted
- Fresh v2.0 installs won't prompt for permission
- Embedded terminal is visually different from external Terminal.app

**What's unclear:**
- Do we need in-app notification about the change?
- Should release notes mention permission cleanup?

**Recommendation:**
- Add to v2.0 release notes: "Terminal.app dependency removed. All Claude Code execution now happens in embedded terminal panels."
- No in-app migration wizard needed (change is transparent)
- Document rollback instructions if users prefer Terminal.app (downgrade to v1.x)

### 3. Testing Strategy for Permission Removal

**What we know:**
- Current tests run in Xcode environment with full permissions
- Permission prompts only appear on fresh installs
- TCC database is per-user, requires macOS reset to test cleanly

**What's unclear:**
- How to automate testing of fresh install experience?
- What's the test matrix for permission states?

**Recommendation:**
- Manual testing: Create fresh macOS user account, install .app bundle, verify no prompts
- Automated testing: Not feasible for TCC permission flows (requires user interaction)
- Acceptance criteria: No permission prompts + successful prompt dispatch to embedded terminal
- Test with VMs or multiple user accounts for confidence

## Sources

### Primary (HIGH confidence)

- **Codebase analysis**: Dispatch project (ExecutionManager.swift, TerminalService.swift, EmbeddedTerminalService.swift, MainView.swift)
  - Current implementation shows clear fallback pattern ready for removal
  - EmbeddedTerminalBridge already has multi-session registry infrastructure

- **Swift Language Documentation**: [@available attribute patterns](https://www.hackingwithswift.com/example-code/language/how-to-use-available-to-deprecate-old-apis)
  - Official Swift deprecation annotations

- **Apple Developer**: [macOS Terminal scripting](https://support.apple.com/guide/terminal/automate-tasks-using-applescript-and-terminal-trml1003/mac)
  - Confirms AppleScript automation patterns being replaced

### Secondary (MEDIUM confidence)

- **Design Patterns**: [Facade and Adapter patterns in Swift](https://www.appcoda.com/design-pattern-structural/)
  - Structural patterns for migration

- **Migration Guide**: [iOS 26 Migration Guide](https://medium.com/@saianbusekar/ios-26-migration-guide-update-your-legacy-apps-like-a-pro-f49b3a3aae9e)
  - Modern app update patterns

- **Swift Evolution**: [Deprecation best practices](https://medium.com/@dhruvmanavadaria/navigating-change-deprecating-old-apis-in-swift-12cd0c29eaf2)
  - Community patterns for API deprecation

### Tertiary (LOW confidence - general context)

- **Swift by Sundell**: [Replacing legacy code using protocols](https://www.swiftbysundell.com/articles/replacing-legacy-code-using-swift-protocols/)
  - General refactoring patterns (not specific to this migration)

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - All components already in codebase, no new libraries needed
- Architecture: HIGH - Deprecation patterns well-documented, ExecutionManager branching straightforward
- Pitfalls: MEDIUM-HIGH - Common issues identified from codebase analysis, some edge cases require testing

**Research date:** 2026-02-08
**Valid until:** 60 days (stable migration patterns, not dependent on fast-moving tech)

**Migration complexity:** LOW-MEDIUM
- Code changes are localized (ExecutionManager, MainView, Info.plist)
- Existing infrastructure already supports embedded-only execution
- Main risk is incomplete cleanup leaving UI references or permission requirements

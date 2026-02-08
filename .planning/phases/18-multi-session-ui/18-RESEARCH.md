# Phase 18: Multi-Session UI - Research

**Researched:** 2026-02-08
**Domain:** Multi-session terminal management, SwiftUI split pane layouts, session state tracking
**Confidence:** MEDIUM-HIGH

## Summary

Phase 18 adds multi-session management to Dispatch's embedded terminal. Users can create multiple simultaneous Claude Code sessions, view them in split panes, and switch focus between them. The core challenge is: (1) managing a collection of terminal sessions with unique identities, (2) implementing dynamic split pane layouts that support 2+ simultaneous views, (3) tracking which session receives dispatched prompts, and (4) providing focus/enlarge modes.

Research confirms that the current single-terminal architecture (EmbeddedTerminalView + Coordinator + Bridge) provides a solid foundation. Each session will be an independent instance of this pattern, identified by UUID. SwiftUI's HSplitView and VSplitView can handle dynamic splits, though native support for 3+ panes is limited. Third-party libraries like Bonsplit (2026) offer advanced split pane management with animations and programmatic control, but may be overkill for initial implementation.

For session management, the standard Swift pattern is an @Observable model (TerminalSession) conforming to Identifiable, stored in an array, with ForEach for dynamic view creation. Focus state uses @FocusState or selection binding to track the active session. The EmbeddedTerminalBridge needs to evolve from singleton (single session) to registry pattern (multiple sessions), with explicit session ID targeting.

**Primary recommendation:** Create a TerminalSessionManager @Observable class that manages an array of TerminalSession models (Identifiable with UUID). Use ForEach with HSplitView/VSplitView for 2-way splits, with a session list/tab bar for selection. Extend EmbeddedTerminalBridge to map session IDs to coordinators. Implement focus mode with conditional layout (single session fullscreen vs multi-pane split).

## Standard Stack

The established patterns for multi-session terminal management:

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| SwiftUI HSplitView | (SwiftUI) | Horizontal split pane layout | Native SwiftUI component for macOS side-by-side views with resizable divider |
| SwiftUI VSplitView | (SwiftUI) | Vertical split pane layout | Native SwiftUI component for above-and-below views |
| @Observable | (Observation) | Session state management | Modern Swift observation for reactive state (replaces ObservableObject in Swift 5.9+) |
| Identifiable protocol | (Swift) | Session identification | Standard protocol for ForEach view identity |
| ForEach | (SwiftUI) | Dynamic view generation | SwiftUI's pattern for creating views from collections |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| @FocusState | (SwiftUI) | Focus tracking | Track which session is focused for keyboard input |
| UUID | (Foundation) | Unique session IDs | Generate stable identifiers for each terminal session |
| UserDefaults | (Foundation) | Session layout persistence | Save/restore split configuration between launches |
| matchedGeometryEffect | (SwiftUI) | Focus mode animation | Smooth expand/collapse transitions |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Native HSplitView/VSplitView | [Bonsplit library](https://github.com/almonk/bonsplit) | Bonsplit offers 120fps animations, drag-drop reordering, and programmatic splits but adds dependency. Native is simpler for 2-3 panes. |
| Native splits | [SplitView package](https://github.com/stevengharris/SplitView) | More flexible nested splits, programmatic hide/show, but additional dependency. |
| Session array in manager | TabView with tabs | TabView hides inactive sessions (good for memory) but prevents simultaneous viewing. Split panes show multiple at once (requirement SESS-03). |
| @Observable | @StateObject + ObservableObject | @Observable is modern (Swift 5.9+), less boilerplate, better performance. Use ObservableObject only if supporting older Swift. |

**Installation:**
All core components are native SwiftUI/Swift. No new dependencies required for basic multi-session support.

## Architecture Patterns

### Recommended Project Structure
```
Dispatch/Services/
├── TerminalSessionManager.swift    # Manages session collection, creation, focus (NEW)
├── EmbeddedTerminalBridge.swift    # Extend to multi-session registry (MODIFY)
├── TerminalProcessRegistry.swift   # Already handles multiple PIDs (EXISTING)
└── ClaudeCodeLauncher.swift        # Already supports multiple launches (EXISTING)

Dispatch/Models/
└── TerminalSession.swift           # Session model: ID, name, state, coordinator (NEW)

Dispatch/Views/Terminal/
├── EmbeddedTerminalView.swift      # Per-session terminal (EXISTING)
├── MultiSessionTerminalView.swift  # Container with splits and session list (NEW)
├── SessionListView.swift           # Tab bar or sidebar for session switching (NEW)
└── SessionPaneView.swift           # Wrapper for individual session with controls (NEW)
```

### Pattern 1: Session Model with Unique Identity
**What:** Identifiable model representing a single terminal session
**When to use:** Core data structure for session tracking
**Example:**
```swift
// Source: SwiftUI Identifiable patterns + existing coordinator architecture
import Foundation
import SwiftTerm

@Observable
final class TerminalSession: Identifiable {
    let id: UUID
    var name: String
    var isActive: Bool = false
    var coordinator: EmbeddedTerminalView.Coordinator?
    var terminal: LocalProcessTerminalView?
    let createdAt: Date

    init(name: String? = nil) {
        self.id = UUID()
        self.name = name ?? "Session \(UUID().uuidString.prefix(8))"
        self.createdAt = Date()
    }

    var isReady: Bool {
        coordinator?.isReadyForDispatch ?? false
    }
}
```

### Pattern 2: Session Manager as Central State
**What:** @Observable manager that holds session collection and active session
**When to use:** Single source of truth for multi-session state
**Example:**
```swift
// Source: SwiftUI state management patterns + session tracking best practices
@Observable
final class TerminalSessionManager {
    static let shared = TerminalSessionManager()

    private(set) var sessions: [TerminalSession] = []
    var activeSessionId: UUID?
    var layoutMode: LayoutMode = .single
    var maxSessions: Int = 4 // SESS-06: limit to prevent resource exhaustion

    enum LayoutMode {
        case single // Focus mode (one session fullscreen)
        case horizontalSplit // Side-by-side
        case verticalSplit // Above-and-below
        case quad // 2x2 grid (future)
    }

    private init() {}

    var activeSession: TerminalSession? {
        sessions.first { $0.id == activeSessionId }
    }

    func createSession(name: String? = nil) -> TerminalSession? {
        guard sessions.count < maxSessions else {
            logWarning("Max sessions (\(maxSessions)) reached", category: .terminal)
            return nil
        }

        let session = TerminalSession(name: name)
        sessions.append(session)

        // Auto-activate if first session
        if activeSessionId == nil {
            activeSessionId = session.id
        }

        logInfo("Created session: \(session.name) (\(session.id))", category: .terminal)
        return session
    }

    func closeSession(_ sessionId: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionId }) else { return }

        let session = sessions[index]

        // Cleanup coordinator (triggers deinit, process termination)
        session.coordinator = nil
        session.terminal = nil

        sessions.remove(at: index)
        logInfo("Closed session: \(session.name)", category: .terminal)

        // If active session closed, select another
        if activeSessionId == sessionId {
            activeSessionId = sessions.first?.id
        }
    }

    func setActiveSession(_ sessionId: UUID) {
        guard sessions.contains(where: { $0.id == sessionId }) else { return }
        activeSessionId = sessionId
        logDebug("Active session changed to: \(sessionId)", category: .terminal)
    }

    func toggleLayoutMode() {
        layoutMode = layoutMode == .single ? .horizontalSplit : .single
    }
}
```

### Pattern 3: Multi-Session Bridge Registry
**What:** Extend EmbeddedTerminalBridge from singleton to session registry
**When to use:** ExecutionManager needs to dispatch to specific session
**Example:**
```swift
// Source: Existing bridge pattern + registry pattern
@MainActor
final class EmbeddedTerminalBridge: ObservableObject {
    static let shared = EmbeddedTerminalBridge()

    // Changed from single coordinator to registry
    private var sessionCoordinators: [UUID: EmbeddedTerminalView.Coordinator] = [:]
    private var sessionTerminals: [UUID: LocalProcessTerminalView] = [:]

    private init() {}

    /// Register a session's coordinator
    func register(sessionId: UUID, coordinator: EmbeddedTerminalView.Coordinator, terminal: LocalProcessTerminalView) {
        sessionCoordinators[sessionId] = coordinator
        sessionTerminals[sessionId] = terminal
        logInfo("Session \(sessionId) registered for dispatch", category: .terminal)
    }

    /// Unregister a session
    func unregister(sessionId: UUID) {
        sessionCoordinators.removeValue(forKey: sessionId)
        sessionTerminals.removeValue(forKey: sessionId)
        logInfo("Session \(sessionId) unregistered", category: .terminal)
    }

    /// Check if a specific session is available
    func isAvailable(sessionId: UUID) -> Bool {
        sessionCoordinators[sessionId]?.isReadyForDispatch ?? false
    }

    /// Dispatch to active session (default behavior)
    func dispatchPrompt(_ prompt: String) -> Bool {
        guard let activeId = TerminalSessionManager.shared.activeSessionId else {
            logDebug("Cannot dispatch: no active session", category: .terminal)
            return false
        }
        return dispatchPrompt(prompt, to: activeId)
    }

    /// Dispatch to specific session
    func dispatchPrompt(_ prompt: String, to sessionId: UUID) -> Bool {
        guard let coordinator = sessionCoordinators[sessionId] else {
            logDebug("Cannot dispatch: session \(sessionId) not registered", category: .terminal)
            return false
        }
        return coordinator.dispatchPrompt(prompt)
    }

    /// Get terminal for monitoring (for ExecutionStateMachine)
    func getTerminal(for sessionId: UUID) -> LocalProcessTerminalView? {
        sessionTerminals[sessionId]
    }
}
```

### Pattern 4: ForEach with Dynamic Split Layout
**What:** SwiftUI ForEach to create terminal views dynamically based on session array
**When to use:** Rendering visible sessions in split panes
**Example:**
```swift
// Source: SwiftUI ForEach + HSplitView patterns
struct MultiSessionTerminalView: View {
    @Environment(TerminalSessionManager.self) private var sessionManager

    var body: some View {
        VStack(spacing: 0) {
            // Session list/tabs at top
            SessionTabBar()

            Divider()

            // Terminal panes
            Group {
                switch sessionManager.layoutMode {
                case .single:
                    // Focus mode: only active session
                    if let activeSession = sessionManager.activeSession {
                        SessionPaneView(session: activeSession)
                    } else {
                        ContentUnavailableView("No Session", systemImage: "terminal")
                    }

                case .horizontalSplit:
                    // Side-by-side: show up to 2 sessions
                    HSplitView {
                        ForEach(sessionManager.sessions.prefix(2)) { session in
                            SessionPaneView(session: session)
                                .frame(minWidth: 300)
                        }
                    }

                case .verticalSplit:
                    // Above-and-below
                    VSplitView {
                        ForEach(sessionManager.sessions.prefix(2)) { session in
                            SessionPaneView(session: session)
                                .frame(minHeight: 200)
                        }
                    }

                case .quad:
                    // 2x2 grid (future enhancement)
                    // Would use nested HSplitView/VSplitView
                    EmptyView()
                }
            }
        }
    }
}
```

### Pattern 5: Session Pane with Focus Indicator
**What:** Wrapper view for each terminal session showing focus state
**When to use:** Individual pane in split layout
**Example:**
```swift
// Source: SwiftUI border highlighting + tap gesture patterns
struct SessionPaneView: View {
    @Environment(TerminalSessionManager.self) private var sessionManager
    let session: TerminalSession

    private var isActive: Bool {
        sessionManager.activeSessionId == session.id
    }

    var body: some View {
        VStack(spacing: 0) {
            // Session header with name and close button
            HStack {
                Text(session.name)
                    .font(.caption)
                    .foregroundStyle(isActive ? .primary : .secondary)

                Spacer()

                Button(action: { sessionManager.closeSession(session.id) }) {
                    Image(systemName: "xmark")
                        .font(.caption)
                }
                .buttonStyle(.plain)
            }
            .padding(4)
            .background(isActive ? Color.accentColor.opacity(0.1) : Color.clear)

            // Terminal view
            EmbeddedTerminalView(
                sessionId: session.id,
                launchMode: .claudeCode(workingDirectory: nil, skipPermissions: true)
            )
            .border(isActive ? Color.accentColor : Color.clear, width: 2)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            // Clicking pane makes it active (SESS-04)
            sessionManager.setActiveSession(session.id)
        }
    }
}
```

### Pattern 6: Session Tab Bar for Switching
**What:** Tab bar showing all sessions, allowing quick switching
**When to use:** SESS-02 requirement - display sessions in tabs or panel list
**Example:**
```swift
// Source: SwiftUI custom tab bar patterns
struct SessionTabBar: View {
    @Environment(TerminalSessionManager.self) private var sessionManager

    var body: some View {
        HStack(spacing: 0) {
            ForEach(sessionManager.sessions) { session in
                SessionTabButton(session: session)
            }

            Spacer()

            // New session button
            Button(action: {
                _ = sessionManager.createSession()
            }) {
                Image(systemName: "plus")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .padding(8)
            .disabled(sessionManager.sessions.count >= sessionManager.maxSessions)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

struct SessionTabButton: View {
    @Environment(TerminalSessionManager.self) private var sessionManager
    let session: TerminalSession

    private var isActive: Bool {
        sessionManager.activeSessionId == session.id
    }

    var body: some View {
        Button(action: {
            sessionManager.setActiveSession(session.id)
        }) {
            HStack(spacing: 4) {
                Text(session.name)
                    .font(.caption)

                // Close button (on hover)
                Button(action: {
                    sessionManager.closeSession(session.id)
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .background(isActive ? Color.accentColor.opacity(0.2) : Color.clear)
    }
}
```

### Pattern 7: Focus Mode Toggle with Animation
**What:** Expand active session to fullscreen, collapse back to split
**When to use:** SESS-05 requirement - enlarge session to full panel size
**Example:**
```swift
// Source: SwiftUI animation + conditional layout patterns
struct MultiSessionTerminalView: View {
    @Environment(TerminalSessionManager.self) private var sessionManager

    var body: some View {
        VStack {
            // ... session tab bar ...

            Group {
                if sessionManager.layoutMode == .single {
                    // Focus mode
                    if let activeSession = sessionManager.activeSession {
                        SessionPaneView(session: activeSession)
                            .transition(.opacity.combined(with: .scale))
                    }
                } else {
                    // Split mode
                    splitLayout
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: sessionManager.layoutMode)
        }
        .toolbar {
            Button(action: {
                sessionManager.toggleLayoutMode()
            }) {
                Image(systemName: sessionManager.layoutMode == .single ? "square.split.2x1" : "arrow.up.left.and.arrow.down.right")
            }
            .keyboardShortcut("m", modifiers: .command)
        }
    }

    @ViewBuilder
    private var splitLayout: some View {
        HSplitView {
            ForEach(sessionManager.sessions) { session in
                SessionPaneView(session: session)
            }
        }
    }
}
```

### Anti-Patterns to Avoid
- **Recreating terminal views on state changes:** Terminal creation is expensive and loses state. Use stable view identity with `.id(session.id)` and ensure ForEach uses proper Identifiable.
- **Global singleton bridge without session IDs:** Don't assume single terminal. Always register with session UUID and dispatch to specific session.
- **Not limiting session count:** SESS-06 requires max limit. Unbounded session creation leads to memory/CPU exhaustion and too many zombie processes.
- **Shared coordinator across sessions:** Each terminal needs its own Coordinator. Don't try to reuse coordinators - they manage process lifecycle tied to one terminal.
- **Blocking UI on session creation:** Terminal spawn and Claude Code launch are async. Use Task/async-await, don't block main thread.

## Don't Hand-Roll

Problems that look simple but have existing solutions:

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Session identity/equality | Custom ID comparison | UUID + Identifiable protocol | SwiftUI ForEach requires stable identity. UUID guarantees uniqueness, Identifiable integrates with SwiftUI. |
| Split pane layout | Custom NSView split logic | HSplitView/VSplitView | Native components handle divider dragging, resize constraints, keyboard navigation. Tested and accessible. |
| Focus state tracking | Manual boolean flags per session | @FocusState or selection binding | SwiftUI's @FocusState handles focus management, keyboard events, and window focus properly. Manual flags miss edge cases. |
| Session persistence | Custom file format | Codable + UserDefaults/JSON | Session metadata (name, layout) can use Codable. Only persist config, not terminal state (not possible). |
| Smooth expand animations | Custom geometry calculations | matchedGeometryEffect or standard transitions | SwiftUI's animation system handles layout transitions. matchedGeometryEffect for "hero" animations, .transition for appear/disappear. |
| Coordinator lifecycle | Manual retain/release | SwiftUI Coordinator + weak refs | NSViewRepresentable's Coordinator pattern handles lifecycle. Use weak refs to avoid cycles. SwiftUI manages deallocation. |

**Key insight:** Multi-session is fundamentally about collection management (array of sessions) and dynamic view generation (ForEach). Don't fight SwiftUI's patterns - use Identifiable, ForEach, and standard layouts. The complexity is in coordinator/bridge registry, not UI layout.

## Common Pitfalls

### Pitfall 1: Session Limit Not Enforced
**What goes wrong:** Users create 10+ sessions, app becomes sluggish, system runs out of memory or file descriptors. Multiple Claude Code processes consume CPU/RAM.
**Why it happens:** No guard on session creation. Each terminal requires PTY file descriptors, memory buffers, and a Claude Code process (~200MB+ each).
**How to avoid:**
1. Enforce `maxSessions` limit in `createSession()` - return nil if exceeded
2. Show user feedback when limit reached (alert or disabled button)
3. Consider session count UI indicator (e.g., "3/4 sessions")
4. SESS-06 suggests 4-6 as reasonable limit for typical hardware
**Warning signs:**
- App becomes unresponsive with many sessions
- "Too many open files" errors in console
- Memory pressure warnings or swap usage spikes

### Pitfall 2: Active Session Not Updated on Close
**What goes wrong:** Active session closed, but activeSessionId still points to closed session. Prompt dispatch fails silently or crashes.
**Why it happens:** `closeSession()` removes from array but doesn't update `activeSessionId` if it was the active one.
**How to avoid:**
1. In `closeSession()`, check if `sessionId == activeSessionId`
2. If true, select next available session: `activeSessionId = sessions.first?.id`
3. Publish state change so UI updates (remove focus highlight)
**Warning signs:**
- Close button works but session still shows as active
- Prompts don't dispatch after closing active session
- Nil coordinator errors in logs

### Pitfall 3: Coordinator Not Bound to Session
**What goes wrong:** Terminal view creates coordinator but session model doesn't hold reference. Session can't be used for dispatch because coordinator is unknown.
**Why it happens:** EmbeddedTerminalView creates coordinator internally (NSViewRepresentable pattern), but session model isn't notified.
**How to avoid:**
1. Extend EmbeddedTerminalView to accept session binding
2. In `makeNSView`, store coordinator reference in session: `session.coordinator = context.coordinator`
3. Register with bridge using session ID: `bridge.register(sessionId: session.id, coordinator: coordinator, terminal: terminal)`
4. Ensure binding is @Binding or direct reference, not a copy
**Warning signs:**
- Terminal renders but prompts can't be sent to it
- `session.isReady` always returns false
- Bridge registry is empty after session creation

### Pitfall 4: Split View Recreates Terminals on Layout Change
**What goes wrong:** Switching from horizontal to vertical split causes terminals to restart, losing running processes and scrollback.
**Why it happens:** SwiftUI sees layout change as different view hierarchy, recreates EmbeddedTerminalView instances.
**How to avoid:**
1. Use stable view identity: `.id(session.id)` on each EmbeddedTerminalView
2. Keep session array stable - don't rebuild, just reorder or filter
3. Use `@State` or `@Environment` for layoutMode, not rebuild entire view tree
4. Consider using single layout container that adjusts internally vs switching view types
**Warning signs:**
- Terminal prompt reappears on layout change
- Running commands (vim, top) restart
- Session history lost when switching layouts

### Pitfall 5: Focus State Doesn't Update on Click
**What goes wrong:** User clicks terminal pane expecting to type there, but keystrokes go to wrong session or nowhere. Visual focus indicator doesn't update.
**Why it happens:** NSView inside NSViewRepresentable doesn't automatically update SwiftUI state. Tap gesture on wrapper doesn't reach through to NSView.
**How to avoid:**
1. Add `.onTapGesture` to SessionPaneView wrapper (before NSViewRepresentable)
2. Call `sessionManager.setActiveSession(session.id)` in tap handler
3. Use `.contentShape(Rectangle())` to ensure entire area is tappable, not just visible content
4. Consider using focusedValue/focusedBinding for proper focus chain
**Warning signs:**
- Clicking pane doesn't highlight it
- Typing goes to wrong terminal after clicking
- Focus indicator shows one session, input goes to another

### Pitfall 6: Terminal Size Wrong in Split View
**What goes wrong:** Terminal appears with wrong dimensions (80x25 default) after split, even though pane is larger. Text wraps incorrectly.
**Why it happens:** EmbeddedTerminalView initialized before SwiftUI layout runs. Split view frame constraints don't propagate immediately.
**How to avoid:**
1. Set `.frame(minWidth:minHeight:)` on EmbeddedTerminalView in split
2. Let SwiftUI layout run before starting Claude Code (defer startProcess)
3. Terminal auto-recalculates cols/rows from frame on layout
4. Don't manually set cols/rows unless you have specific requirements
**Warning signs:**
- Split pane terminal shows 80 columns when pane is larger
- Claude Code output wraps oddly
- `$COLUMNS` in terminal doesn't match visible width

### Pitfall 7: Memory Leak from Coordinator Retain Cycles
**What goes wrong:** Closing sessions doesn't free memory. Instruments shows leaked LocalProcessTerminalView and Coordinator instances.
**Why it happens:** Coordinator holds strong reference to session or manager, which holds coordinator. Circular reference prevents deallocation.
**How to avoid:**
1. Use `weak var session: TerminalSession?` in Coordinator if referencing back
2. Ensure `session.coordinator` is properly cleared in `closeSession()`
3. Don't capture `self` strongly in coordinator closures
4. Verify deinit is called: add `deinit { print("Session deinit") }` during testing
**Warning signs:**
- Memory usage grows with each session open/close cycle
- Instruments Allocations shows growing LocalProcessTerminalView count
- deinit never prints/breakpoint never hits

## Code Examples

Verified patterns from research and existing codebase:

### Complete Session Creation Flow
```swift
// Source: Existing patterns + session management best practices
extension TerminalSessionManager {
    func createAndConfigureSession(name: String? = nil, workingDirectory: String? = nil) async -> TerminalSession? {
        // Check limit
        guard sessions.count < maxSessions else {
            logWarning("Cannot create session: max limit (\(maxSessions)) reached", category: .terminal)
            return nil
        }

        // Create session model
        let session = TerminalSession(name: name)
        sessions.append(session)

        // Will be configured when EmbeddedTerminalView is created
        // (coordinator and terminal set in makeNSView)

        logInfo("Created session: \(session.name) (\(session.id))", category: .terminal)

        // Auto-activate if first session
        if sessions.count == 1 {
            activeSessionId = session.id
        }

        return session
    }
}
```

### EmbeddedTerminalView with Session Binding
```swift
// Source: Existing EmbeddedTerminalView + session integration
struct EmbeddedTerminalView: NSViewRepresentable {
    typealias NSViewType = LocalProcessTerminalView

    let sessionId: UUID
    var launchMode: TerminalLaunchMode = .shell
    var onProcessExit: ((Int32?) -> Void)?

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        logDebug("Creating terminal for session: \(sessionId)", category: .terminal)

        let terminal = LocalProcessTerminalView(frame: .zero)
        terminal.processDelegate = context.coordinator

        // Store terminal reference in coordinator
        context.coordinator.terminalView = terminal
        context.coordinator.sessionId = sessionId

        // Register with bridge using session ID
        EmbeddedTerminalBridge.shared.register(
            sessionId: sessionId,
            coordinator: context.coordinator,
            terminal: terminal
        )

        // Update session model with coordinator reference
        if let session = TerminalSessionManager.shared.sessions.first(where: { $0.id == sessionId }) {
            session.coordinator = context.coordinator
            session.terminal = terminal
        }

        // Launch process based on mode
        switch launchMode {
        case .shell:
            let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/bash"
            terminal.startProcess(executable: shell)

        case let .claudeCode(workingDirectory, skipPermissions):
            ClaudeCodeLauncher.shared.launchClaudeCode(
                in: terminal,
                workingDirectory: workingDirectory,
                skipPermissions: skipPermissions
            )
        }

        return terminal
    }

    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {
        context.coordinator.onProcessExit = onProcessExit
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(sessionId: sessionId, onProcessExit: onProcessExit)
    }

    class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
        var sessionId: UUID
        var onProcessExit: ((Int32?) -> Void)?
        var terminalView: LocalProcessTerminalView?

        init(sessionId: UUID, onProcessExit: ((Int32?) -> Void)?) {
            self.sessionId = sessionId
            self.onProcessExit = onProcessExit
            super.init()
        }

        deinit {
            logDebug("Coordinator deinit for session: \(sessionId)", category: .terminal)

            MainActor.assumeIsolated {
                EmbeddedTerminalBridge.shared.unregister(sessionId: sessionId)
            }

            // Terminate process group
            if let terminal = terminalView {
                let pid = terminal.process.shellPid
                TerminalProcessRegistry.shared.terminateProcessGroupGracefully(pgid: pid, timeout: 2.0)
                TerminalProcessRegistry.shared.unregister(pid: pid)
            }

            terminalView = nil
        }

        // ... delegate methods same as before ...

        func processTerminated(source: TerminalView, exitCode: Int32?) {
            logDebug("Terminal process exited for session \(sessionId): \(exitCode ?? -1)", category: .terminal)

            if let terminal = terminalView {
                TerminalProcessRegistry.shared.unregister(pid: terminal.process.shellPid)
            }

            terminalView = nil

            DispatchQueue.main.async {
                self.onProcessExit?(exitCode)

                // Optionally auto-close session on process exit
                // TerminalSessionManager.shared.closeSession(self.sessionId)
            }
        }

        func dispatchPrompt(_ prompt: String) -> Bool {
            guard let terminal = terminalView else {
                logDebug("Cannot dispatch to session \(sessionId): no terminal", category: .terminal)
                return false
            }

            let fullPrompt = prompt.hasSuffix("\n") ? prompt : prompt + "\n"
            logInfo("Dispatching prompt to session \(sessionId) (\(fullPrompt.count) chars)", category: .terminal)
            terminal.send(txt: fullPrompt)

            return true
        }

        var isReadyForDispatch: Bool {
            terminalView != nil
        }
    }
}
```

### ExecutionManager Integration with Session Targeting
```swift
// Source: Existing ExecutionManager + multi-session targeting
extension ExecutionManager {
    /// Execute prompt with explicit session targeting
    func execute(
        content: String,
        title: String = "Prompt",
        targetSessionId: UUID? = nil, // NEW: explicit session targeting
        isFromChain: Bool = false,
        chainName: String? = nil,
        chainStepIndex: Int? = nil,
        chainTotalSteps: Int? = nil
    ) async throws {
        guard !content.isEmpty else {
            throw TerminalServiceError.invalidPromptContent
        }

        guard stateMachine.state == .idle else {
            throw ExecutionError.alreadyExecuting
        }

        // Determine target session
        let sessionId = targetSessionId ?? TerminalSessionManager.shared.activeSessionId

        guard let sessionId = sessionId else {
            throw ExecutionError.noActiveSession
        }

        let context = ExecutionContext(
            promptContent: content,
            promptTitle: title,
            targetSessionId: sessionId, // Store in context
            isFromChain: isFromChain,
            chainName: chainName,
            chainStepIndex: chainStepIndex,
            chainTotalSteps: chainTotalSteps
        )

        logInfo("Executing prompt '\(title)' to session \(sessionId)", category: .execution)

        stateMachine.beginSending(context: context)

        do {
            let bridge = EmbeddedTerminalBridge.shared

            // Dispatch to specific session
            guard bridge.isAvailable(sessionId: sessionId) else {
                throw TerminalServiceError.sessionNotReady
            }

            let dispatched = bridge.dispatchPrompt(content, to: sessionId)
            guard dispatched else {
                throw TerminalServiceError.scriptExecutionFailed("Dispatch failed")
            }

            stateMachine.beginExecuting()

            // Start monitoring for this session
            if let terminal = bridge.getTerminal(for: sessionId) {
                stateMachine.startEmbeddedTerminalMonitoring(terminal: terminal)
            }

        } catch {
            stateMachine.markCompleted(result: .failure(error))
            throw error
        }
    }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Single global terminal | Multi-session with UUID identity | This phase | Users can manage multiple Claude Code instances simultaneously |
| Singleton bridge pattern | Registry pattern with session IDs | This phase | Explicit session targeting for prompt dispatch |
| Manual session tracking | @Observable + Identifiable pattern | Swift 5.9+ (2023) | Less boilerplate, better SwiftUI integration |
| Custom split view logic | Native HSplitView/VSplitView | Always (SwiftUI) | Accessible, tested, handles edge cases |
| @StateObject + ObservableObject | @Observable macro | Swift 5.9 | Cleaner syntax, better performance, less boilerplate |
| Conditional views for layout | Layout enum + animation | SwiftUI best practice | Smooth transitions, predictable state |

**Deprecated/outdated:**
- **Singleton EmbeddedTerminalBridge:** Replaced by session registry with UUID targeting
- **Single activeCoordinator property:** Now sessionCoordinators dictionary
- **ObservableObject for session models:** Use @Observable instead (Swift 5.9+)

## Open Questions

Things that couldn't be fully resolved:

1. **Maximum session limit value (SESS-06)**
   - What we know: Requirement specifies limiting concurrent sessions to prevent exhaustion
   - What's unclear: Optimal limit depends on hardware. Each session = ~200MB+ RAM, 2 file descriptors
   - Recommendation: Start with 4 sessions max. Make configurable in settings. Test with 6-8 on various hardware.

2. **Session persistence across app restarts**
   - What we know: Can persist session names and layout configuration via Codable
   - What's unclear: Should we restore terminal content/scrollback? Claude Code state isn't serializable.
   - Recommendation: Persist layout and names only. Start fresh terminals on launch (simpler, cleaner state).

3. **Split layout beyond 2 panes**
   - What we know: HSplitView/VSplitView work well for 2-way splits
   - What's unclear: 3+ panes require nested splits or custom layout. Bonsplit library supports this.
   - Recommendation: Start with 2-pane splits (horizontal/vertical). Defer 3+ pane "quad view" to future phase if requested.

4. **Session naming strategy**
   - What we know: Auto-generated names like "Session 1" work but aren't memorable
   - What's unclear: Should we prompt user for name on creation? Auto-detect project from working directory?
   - Recommendation: Default to "Session N", allow inline rename (double-click tab). Consider project detection later.

5. **Session state after Claude Code exit**
   - What we know: When Claude Code exits, terminal process ends
   - What's unclear: Should session auto-close? Show "Session ended" state? Auto-restart?
   - Recommendation: Keep session visible with "Process exited" message, show restart button. Don't auto-close (user might want scrollback).

6. **Split pane size persistence**
   - What we know: HSplitView allows user to resize via divider
   - What's unclear: Should divider position persist per-layout in UserDefaults?
   - Recommendation: Start without persistence (simpler). Add if users request it. Use GeometryReader to capture sizes.

## Sources

### Primary (HIGH confidence)
- [Existing EmbeddedTerminalView](/Users/eric/Dispatch/Dispatch/Views/Terminal/EmbeddedTerminalView.swift) - Current single-session implementation
- [Existing EmbeddedTerminalBridge](/Users/eric/Dispatch/Dispatch/Services/EmbeddedTerminalBridge.swift) - Singleton pattern to extend
- [Phase 17 Research](/Users/eric/Dispatch/.planning/phases/17-claude-code-integration/17-RESEARCH.md) - Claude Code integration patterns
- [Phase 14 Research](/Users/eric/Dispatch/.planning/phases/14-swiftterm-integration/14-RESEARCH.md) - SwiftTerm architecture
- [Apple HSplitView Documentation](https://developer.apple.com/documentation/swiftui/hsplitview) - Official split view API
- [Swift Identifiable Protocol](https://developer.apple.com/documentation/swift/identifiable) - Session identity pattern

### Secondary (MEDIUM confidence)
- [Bonsplit Library](https://github.com/almonk/bonsplit) - Advanced macOS split panes with animations (2026)
- [SplitView Package](https://github.com/stevengharris/SplitView) - Flexible SwiftUI split views
- [SwiftUI Navigation Guide 2026](https://levelup.gitconnected.com/swiftui-navigation-in-ios-a-practical-guide-2a4820971681) - Session management patterns
- [SwiftUI Focus Management](https://www.kodeco.com/31569019-focus-management-in-swiftui-getting-started) - @FocusState patterns
- [SwiftUI Identifiable Guide](https://tanaschita.com/swiftui-identifiable/) - ForEach with Identifiable
- [SwiftUI Animation Patterns](https://dev.to/sebastienlato/swiftui-animation-masterclass-springs-curves-smooth-motion-3e4o) - Focus mode transitions

### Tertiary (LOW confidence)
- AgentHub reference (mentioned in requirements but no public documentation found) - Assumed to be similar pattern
- Optimal session limits - hardware-dependent, no authoritative source
- Session persistence best practices - application-specific choice

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - Native SwiftUI components, well-documented patterns
- Architecture: MEDIUM-HIGH - Extends proven Phase 14-17 patterns, but multi-session is new complexity
- Session management: HIGH - Standard Swift/SwiftUI patterns (Identifiable, ForEach, @Observable)
- Split pane layout: MEDIUM - Native components work well for 2-pane, 3+ pane less documented
- Bridge registry: HIGH - Standard registry pattern, clear extension from singleton

**Research date:** 2026-02-08
**Valid until:** 2026-03-08 (30 days - stable domain, SwiftUI patterns don't change rapidly)

**Note on AgentHub:** Requirements mention "multi-session split panes (matches AgentHub UX)" but AgentHub appears to be internal/private reference. Research proceeded with standard multi-session terminal patterns and native SwiftUI split views.

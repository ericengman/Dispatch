# Architecture Research: Embedded Terminal Integration (v2.0)

**Domain:** In-app Claude Code terminal embedding for macOS
**Researched:** 2026-02-07
**Confidence:** HIGH (verified against SwiftTerm documentation, AgentHub reference implementation, and Dispatch codebase)

## Executive Summary

Dispatch v2.0 replaces Terminal.app-based AppleScript control with embedded SwiftTerm terminals running Claude Code directly in the app. This eliminates the need for automation permissions, improves reliability, and enables richer integration.

**Reference Implementation:** [AgentHub](https://github.com/jamesrochabrun/AgentHub) (MIT licensed) provides a production-ready pattern for SwiftTerm + Claude Code integration.

**Key Architectural Decision:** Create a parallel `EmbeddedTerminalService` that implements the same interface as `TerminalService`, allowing gradual migration and dual-mode operation.

---

## AgentHub Pattern Analysis

AgentHub implements embedded Claude Code terminals with this architecture:

```
SwiftUI View (EmbeddedTerminalView)
    |
    +-- NSViewRepresentable wrapper
        |
        +-- TerminalContainerView (NSView)
            |
            +-- ManagedLocalProcessTerminalView (subclass of TerminalView)
                |
                +-- LocalProcess (PTY management)
                    |
                    +-- bash -c "claude --dangerously-skip-permissions"
```

### Key AgentHub Components

| Component | Purpose | Dispatch Equivalent |
|-----------|---------|---------------------|
| `ManagedLocalProcessTerminalView` | Extended TerminalView with process lifecycle | New: `DispatchTerminalView` |
| `EmbeddedTerminalView` | SwiftUI NSViewRepresentable wrapper | New: `EmbeddedTerminalView` |
| `TerminalLauncher` | Process spawning, environment setup | Replaces: `TerminalService.launchTerminal()` |
| `TerminalProcessRegistry` | PID tracking, cleanup on quit | New: `TerminalProcessRegistry` |

### AgentHub Key Patterns

**1. Thread-Safe Data Reception**
```swift
class SafeLocalProcessTerminalView: LocalProcessTerminalView {
    private let lock = NSLock()
    private var isReceivingData = true

    func stopDataReception() {
        lock.lock()
        isReceivingData = false
        lock.unlock()
    }

    override func dataReceived(slice: ArraySlice<UInt8>) {
        lock.lock()
        defer { lock.unlock() }
        guard isReceivingData else { return }
        super.dataReceived(slice: slice)
    }
}
```

**2. Graceful Process Termination**
```swift
func terminateProcessTree(gracePeriod: TimeInterval = 0.3) {
    // 1. Send SIGTERM to process group
    killpg(pid, SIGTERM)

    // 2. Wait grace period
    Thread.sleep(forTimeInterval: gracePeriod)

    // 3. Force kill if still alive
    if processStillRunning(pid) {
        killpg(pid, SIGKILL)
    }
}
```

**3. Prompt Delivery via stdin**
```swift
// Send text directly to PTY stdin
func sendPrompt(_ text: String) {
    guard let data = text.data(using: .utf8) else { return }
    localProcess.send(data: data)
}
```

---

## Dispatch Integration Plan

### New Components

#### 1. `EmbeddedTerminalView.swift` (SwiftUI)

**Location:** `Dispatch/Views/Terminal/EmbeddedTerminalView.swift`

```swift
struct EmbeddedTerminalView: NSViewRepresentable {
    let session: TerminalSession
    @Binding var isActive: Bool

    func makeNSView(context: Context) -> TerminalContainerView {
        let container = TerminalContainerView()
        container.configure(session: session)
        return container
    }

    func updateNSView(_ nsView: TerminalContainerView, context: Context) {
        // Handle appearance changes, focus state
    }
}
```

**Integration Point:** Replaces `TerminalPickerView` functionality for embedded sessions.

#### 2. `TerminalContainerView.swift` (AppKit)

**Location:** `Dispatch/Views/Terminal/TerminalContainerView.swift`

NSView wrapper that owns the SwiftTerm TerminalView and LocalProcess.

```swift
class TerminalContainerView: NSView {
    private var terminalView: DispatchTerminalView?
    private var session: TerminalSession?

    func configure(session: TerminalSession) {
        self.session = session
        setupTerminalView()
        startProcess(workingDirectory: session.workingDirectory)
    }

    private func startProcess(workingDirectory: URL) {
        let environment = prepareEnvironment()
        terminalView?.startProcess(
            executable: "/bin/bash",
            args: ["-c", "claude --dangerously-skip-permissions"],
            environment: environment,
            currentDirectory: workingDirectory.path
        )
    }
}
```

#### 3. `DispatchTerminalView.swift` (SwiftTerm Subclass)

**Location:** `Dispatch/Views/Terminal/DispatchTerminalView.swift`

Extended TerminalView with Dispatch-specific features.

```swift
class DispatchTerminalView: LocalProcessTerminalView {
    // Thread-safe data reception
    private let dataLock = NSLock()
    private var isReceiving = true

    // Completion detection via output parsing
    weak var completionDelegate: TerminalCompletionDelegate?

    override func dataReceived(slice: ArraySlice<UInt8>) {
        dataLock.lock()
        defer { dataLock.unlock() }
        guard isReceiving else { return }

        super.dataReceived(slice: slice)

        // Check for Claude Code completion patterns
        if let text = String(bytes: slice, encoding: .utf8) {
            checkForCompletionPattern(text)
        }
    }

    private func checkForCompletionPattern(_ text: String) {
        // Claude Code prompt patterns indicate completion
        let patterns = ["╭─", "> ", "claude>"]
        for pattern in patterns {
            if text.contains(pattern) {
                completionDelegate?.terminalDidComplete(self)
                break
            }
        }
    }
}
```

#### 4. `TerminalSession.swift` (Model)

**Location:** `Dispatch/Models/TerminalSession.swift`

SwiftData model for embedded terminal sessions.

```swift
@Model
final class TerminalSession {
    var id: UUID
    var name: String
    var workingDirectory: String
    var createdAt: Date
    var lastActiveAt: Date
    var processId: Int32?
    var isActive: Bool

    // Relationship to Project
    var project: Project?

    // Terminal state for restoration
    var scrollbackBuffer: Data?
}
```

#### 5. `EmbeddedTerminalService.swift` (Actor)

**Location:** `Dispatch/Services/EmbeddedTerminalService.swift`

Actor-based service parallel to `TerminalService`.

```swift
actor EmbeddedTerminalService {
    static let shared = EmbeddedTerminalService()

    private var sessions: [UUID: WeakTerminalReference] = [:]
    private var processRegistry = TerminalProcessRegistry()

    // MARK: - Session Management

    func createSession(
        name: String,
        workingDirectory: URL,
        project: Project?
    ) async throws -> TerminalSession

    func getSession(id: UUID) async -> TerminalSession?
    func getAllSessions() async -> [TerminalSession]
    func terminateSession(id: UUID) async

    // MARK: - Prompt Dispatch (matches TerminalService interface)

    func sendPrompt(
        _ content: String,
        toSession sessionId: UUID
    ) async throws

    func dispatchPrompt(
        content: String,
        projectPath: String?,
        projectName: String?,
        pressEnter: Bool
    ) async throws -> TerminalSession
}
```

#### 6. `TerminalProcessRegistry.swift` (Process Tracking)

**Location:** `Dispatch/Services/TerminalProcessRegistry.swift`

Tracks embedded terminal PIDs for cleanup.

```swift
final class TerminalProcessRegistry: @unchecked Sendable {
    private var entries: [Int32: Date] = [:]
    private let lock = NSLock()

    func register(pid: Int32) {
        lock.lock()
        defer { lock.unlock() }
        entries[pid] = Date()
        persist()
    }

    func unregister(pid: Int32) {
        lock.lock()
        defer { lock.unlock() }
        entries.removeValue(forKey: pid)
        persist()
    }

    func cleanupAll() {
        lock.lock()
        let pids = Array(entries.keys)
        lock.unlock()

        for pid in pids {
            terminateProcess(pid)
            unregister(pid: pid)
        }
    }

    private func terminateProcess(_ pid: Int32) {
        // Graceful termination with escalation
        kill(pid, SIGTERM)
        usleep(300_000) // 300ms
        if processExists(pid) {
            kill(pid, SIGKILL)
        }
    }
}
```

### Modified Components

#### 1. `ExecutionStateMachine.swift` (Enhancement)

**Changes:**
- Add `sessionId: UUID?` to `ExecutionContext` for embedded sessions
- Modify completion detection to use direct terminal output parsing (not just hooks/polling)
- Add `terminalMode: TerminalMode` enum (`.external`, `.embedded`)

```swift
enum TerminalMode: String, Sendable {
    case external  // Terminal.app via AppleScript
    case embedded  // In-app SwiftTerm terminal
}

struct ExecutionContext: Sendable {
    // Existing properties...
    let terminalMode: TerminalMode
    let embeddedSessionId: UUID?  // Only for embedded mode
}
```

#### 2. `ExecutionManager.swift` (Enhancement)

**Changes:**
- Route execution through either `TerminalService` or `EmbeddedTerminalService` based on mode
- Unified interface, different backends

```swift
func execute(
    content: String,
    title: String,
    mode: TerminalMode = .embedded,  // Default to embedded in v2.0
    sessionId: UUID? = nil,
    // ... existing parameters
) async throws {
    switch mode {
    case .embedded:
        try await executeEmbedded(content: content, sessionId: sessionId)
    case .external:
        try await executeExternal(content: content, windowId: targetWindowId)
    }
}
```

#### 3. `HookServer.swift` (Enhancement)

**Changes:**
- Add endpoint for embedded terminal completion notifications (optional, for symmetry)
- Could receive notifications from terminal output parser

No breaking changes - hooks remain the primary completion mechanism for external terminals.

#### 4. `QueueItem.swift` (Enhancement)

**Changes:**
- Add `targetSessionId: UUID?` for embedded terminal targeting
- Add `terminalMode: TerminalMode` preference

```swift
@Model
final class QueueItem {
    // Existing properties...

    /// Target embedded terminal session (for embedded mode)
    var targetSessionId: UUID?

    /// Preferred terminal mode
    var terminalModeRaw: String?

    var terminalMode: TerminalMode? {
        get { terminalModeRaw.flatMap { TerminalMode(rawValue: $0) } }
        set { terminalModeRaw = newValue?.rawValue }
    }
}
```

#### 5. `MainView.swift` (Enhancement)

**Changes:**
- Add terminal panel/area for embedded sessions
- Toggle between prompt library and terminal views
- Consider split view layout

```swift
// New state
@State private var showTerminalPanel: Bool = true
@State private var terminalSessions: [TerminalSession] = []

// New view section (conceptual)
var body: some View {
    NavigationSplitView {
        SidebarView(selection: $selection)
    } detail: {
        HSplitView {
            // Existing prompt/content area
            contentView

            // New terminal panel
            if showTerminalPanel {
                TerminalPanelView(sessions: $terminalSessions)
            }
        }
    }
}
```

#### 6. `Project.swift` (Enhancement)

**Changes:**
- Add relationship to `TerminalSession`
- Track associated embedded terminals per project

```swift
@Model
final class Project {
    // Existing properties...

    @Relationship(deleteRule: .cascade, inverse: \TerminalSession.project)
    var terminalSessions: [TerminalSession] = []
}
```

### Removed Components

#### 1. `TerminalService.swift` - AppleScript Dependency (Deprecated, Not Removed)

**Status:** Keep for backwards compatibility, but deprecate.

The existing `TerminalService` with AppleScript should remain for users who prefer Terminal.app. Mark methods as deprecated with migration guidance.

```swift
@available(*, deprecated, message: "Use EmbeddedTerminalService for embedded terminals")
func sendPrompt(_ content: String, toWindowId windowId: String?) async throws
```

**Rationale:** Some users may have workflows depending on Terminal.app. Complete removal should be a v3.0 consideration after usage data.

#### 2. Window Caching Logic in TerminalService (Simplify)

The `cachedWindows`, `lastWindowFetchTime`, and window enumeration logic becomes unnecessary for embedded terminals. The embedded service tracks sessions directly in SwiftData.

---

## Data Flow

### Prompt Dispatch Flow (Embedded Mode)

```
User Action (Send Prompt)
    |
    v
PromptViewModel / QueueViewModel
    |
    v
ExecutionManager.execute(mode: .embedded)
    |
    v
ExecutionStateMachine.beginSending()
    |
    v
EmbeddedTerminalService.dispatchPrompt()
    |
    +-- Find or create TerminalSession for project
    |
    +-- Get DispatchTerminalView reference
    |
    v
DispatchTerminalView.send(data:)
    |
    v
LocalProcess writes to PTY stdin
    |
    v
Claude Code processes prompt
    |
    v
Output appears in terminal
    |
    v
DispatchTerminalView.dataReceived()
    |
    +-- Render to screen
    |
    +-- Check for completion patterns
    |
    v
CompletionDelegate.terminalDidComplete()
    |
    v
ExecutionStateMachine.markCompleted()
    |
    v
Queue advances / Chain continues
```

### Session Lifecycle

```
App Launch
    |
    +-- TerminalProcessRegistry loads persisted PIDs
    |
    +-- Cleanup orphaned processes from previous crash
    |
    v
User Opens Project
    |
    v
EmbeddedTerminalService.createSession()
    |
    +-- Create TerminalSession in SwiftData
    |
    +-- TerminalContainerView spawns LocalProcess
    |
    +-- Register PID in TerminalProcessRegistry
    |
    v
Normal Operation (prompts, output, etc.)
    |
    v
User Closes Session / App Quits
    |
    v
TerminalProcessRegistry.cleanupAll()
    |
    +-- SIGTERM to each process
    |
    +-- Wait 300ms
    |
    +-- SIGKILL if still alive
    |
    v
Clean Exit
```

---

## Suggested Build Order

### Phase 1: Core Terminal Infrastructure

**Goal:** Get a single embedded terminal working.

1. Add SwiftTerm package dependency
2. Create `DispatchTerminalView` (SwiftTerm subclass)
3. Create `TerminalContainerView` (NSView wrapper)
4. Create `EmbeddedTerminalView` (SwiftUI wrapper)
5. Create simple test view showing embedded terminal

**Deliverable:** A view that shows a bash shell embedded in Dispatch.

### Phase 2: Process Management

**Goal:** Proper process lifecycle and cleanup.

1. Create `TerminalProcessRegistry`
2. Implement graceful termination
3. Add crash recovery (cleanup orphaned processes on launch)
4. Create `TerminalSession` SwiftData model

**Deliverable:** Processes terminate cleanly on app quit, survive app restart.

### Phase 3: Claude Code Integration

**Goal:** Claude Code running in embedded terminal.

1. Implement Claude Code launch in `TerminalContainerView`
2. Configure proper environment variables
3. Implement completion detection via output parsing
4. Integrate with `ExecutionStateMachine`

**Deliverable:** Can dispatch prompts to embedded Claude Code session.

### Phase 4: Service Layer

**Goal:** Full `EmbeddedTerminalService` parallel to `TerminalService`.

1. Create `EmbeddedTerminalService` actor
2. Implement session management (create, list, terminate)
3. Implement `dispatchPrompt()` matching existing interface
4. Update `ExecutionManager` for dual-mode execution

**Deliverable:** Unified execution API works with both terminal types.

### Phase 5: UI Integration

**Goal:** Terminal panel in main Dispatch UI.

1. Create `TerminalPanelView` for managing sessions
2. Create `TerminalTabView` for multiple sessions
3. Integrate into `MainView` with split view
4. Add project-terminal association

**Deliverable:** Full terminal panel in Dispatch UI.

### Phase 6: Model Updates

**Goal:** SwiftData integration for sessions.

1. Update `Project` model with terminal session relationship
2. Update `QueueItem` with embedded terminal targeting
3. Implement session persistence and restoration
4. Add scrollback buffer persistence (optional)

**Deliverable:** Sessions persist across app restarts.

### Phase 7: Migration & Polish

**Goal:** Smooth transition from Terminal.app.

1. Deprecate `TerminalService` methods
2. Add settings toggle for terminal mode preference
3. Implement dual-mode UI (embedded + external)
4. Documentation and migration guide

**Deliverable:** Complete v2.0 terminal system.

---

## Key Dependencies

### SwiftTerm Package

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/migueldeicaza/SwiftTerm", from: "1.6.0"),
    // Existing HotKey dependency
    .package(url: "https://github.com/soffes/HotKey", from: "0.2.0")
]
```

**Key Classes:**
- `TerminalView`: Base terminal emulator view (NSView)
- `LocalProcess`: PTY and process management
- `LocalProcessTerminalView`: Convenience subclass combining both
- `LocalProcessDelegate`: Lifecycle callbacks

### System Frameworks

- `Foundation`: Process, FileManager
- `Darwin`: POSIX signals (SIGTERM, SIGKILL), PTY functions
- `Network`: Existing HookServer (no changes)

---

## Risk Mitigation

### Risk: SwiftTerm Compatibility Issues

**Mitigation:**
- SwiftTerm is mature (used by Secure Shellfish, La Terminal, CodeEdit)
- MIT license allows forking if needed
- AgentHub provides tested integration pattern

### Risk: Process Cleanup Failures

**Mitigation:**
- Registry persists to UserDefaults
- Cleanup runs on app launch
- Multiple termination strategies (SIGTERM -> SIGKILL)

### Risk: Completion Detection Reliability

**Mitigation:**
- Multiple detection patterns
- Fallback to hook server
- Polling remains as last resort

---

## Sources

### Official Documentation
- [SwiftTerm GitHub](https://github.com/migueldeicaza/SwiftTerm) - Terminal emulator library
- [SwiftTerm Documentation](https://migueldeicaza.github.io/SwiftTermDocs/documentation/swiftterm/) - API reference

### Reference Implementation
- [AgentHub GitHub](https://github.com/jamesrochabrun/AgentHub) - Production embedded terminal with Claude Code
- `ManagedLocalProcessTerminalView.swift` - PTY management pattern
- `EmbeddedTerminalView.swift` - SwiftUI wrapper pattern
- `TerminalLauncher.swift` - Process spawning pattern
- `TerminalProcessRegistry.swift` - Process tracking pattern

### Dispatch Codebase
- `/Users/eric/Dispatch/Dispatch/Services/TerminalService.swift` - Existing AppleScript implementation
- `/Users/eric/Dispatch/Dispatch/Services/HookServer.swift` - Completion detection server
- `/Users/eric/Dispatch/Dispatch/Services/ExecutionStateMachine.swift` - Execution lifecycle
- `/Users/eric/Dispatch/Dispatch/Models/QueueItem.swift` - Queue item model
- `/Users/eric/Dispatch/Dispatch/Models/Project.swift` - Project model
- `/Users/eric/Dispatch/Dispatch/Views/MainView.swift` - Main UI structure

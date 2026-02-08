# Phase 19: Session Persistence - Research

**Researched:** 2026-02-08
**Domain:** SwiftData persistence, Claude Code session management
**Confidence:** HIGH

## Summary

Phase 19 adds session persistence to survive app restarts by storing terminal session metadata in SwiftData and offering resume on launch. The existing codebase already has comprehensive session discovery (ClaudeSessionDiscoveryService), in-memory session models (TerminalSession), and UI for session resumption (SessionResumePicker). The research confirms Claude Code's `-r` (resume) flag works reliably with session IDs stored in `~/.claude/projects/<project>/sessions-index.json`, and the path escaping/discovery logic is already implemented.

The core implementation involves: (1) Creating a SwiftData @Model version of TerminalSession with Project relationship, (2) Persisting active sessions on state changes, (3) Loading persisted sessions on app launch and showing the resume picker, (4) Handling stale session resume failures gracefully by creating fresh sessions.

**Primary recommendation:** Convert TerminalSession from @Observable to @Model, add Project relationship with nullify delete rule, persist on state changes, and show SessionResumePicker on app launch if sessions exist.

## Standard Stack

The established libraries/tools for this domain:

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| SwiftData | macOS 14.0+ | Native persistence framework | Apple's modern replacement for Core Data, type-safe |
| SwiftUI | macOS 14.0+ | UI framework | Already used throughout app for reactive UI |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| @Observable macro | Swift 6 | State management | Already used for TerminalSession in Phase 18 |
| @Model macro | SwiftData | Model persistence | Required for SwiftData entities |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| SwiftData | UserDefaults | UserDefaults can't handle relationships, loses type safety |
| SwiftData | SQLite.swift | More control but requires manual schema management |
| @Model macro | Core Data | SwiftData is modern replacement with simpler API |

**Installation:**
No additional dependencies needed - SwiftData is part of macOS 14.0+

## Architecture Patterns

### Recommended Project Structure
```
Dispatch/Models/
├── TerminalSession.swift     # Convert to @Model (currently @Observable)
├── Project.swift              # Add sessions relationship
└── ...                        # Other models

Dispatch/Services/
├── ClaudeSessionDiscoveryService.swift  # Already exists - discovers sessions
└── TerminalSessionManager.swift         # Update to persist sessions
```

### Pattern 1: SwiftData Model with Project Relationship
**What:** Add @Model macro to TerminalSession and establish bidirectional relationship with Project
**When to use:** When session should be associated with a project and persist across app restarts
**Example:**
```swift
// Source: Based on existing Prompt.swift and PromptChain.swift patterns
@Model
final class TerminalSession: Identifiable {
    var id: UUID
    var name: String
    var createdAt: Date
    var lastActivity: Date

    // Claude Code session resumption support
    var claudeSessionId: String? // Claude session ID if resuming
    var workingDirectory: String? // Project path for Claude Code

    // Relationship to Project (nullify on project deletion)
    var project: Project?

    init(name: String, claudeSessionId: String? = nil, workingDirectory: String? = nil) {
        id = UUID()
        self.name = name
        createdAt = Date()
        lastActivity = Date()
        self.claudeSessionId = claudeSessionId
        self.workingDirectory = workingDirectory
    }
}

// In Project.swift - add inverse relationship
@Relationship(deleteRule: .nullify, inverse: \TerminalSession.project)
var sessions: [TerminalSession] = []
```

### Pattern 2: Hybrid @Model + @Observable Pattern
**What:** Cannot combine @Model and @Observable on same class - must choose one
**When to use:** For persistence, use @Model. For runtime-only state, use @Observable separately
**Example:**
```swift
// Source: SwiftData best practices from research
// WRONG - Cannot mix @Model and @Observable
@Model
@Observable
final class TerminalSession { ... } // COMPILE ERROR

// RIGHT - Use @Model for persistence, separate runtime state
@Model
final class TerminalSession {
    var id: UUID
    var name: String
    // ... persisted properties only
}

// Runtime coordinator/terminal references in separate manager
@Observable
final class TerminalSessionManager {
    var sessions: [TerminalSession] = []
    var coordinators: [UUID: EmbeddedTerminalView.Coordinator] = [:]
    var terminals: [UUID: LocalProcessTerminalView] = [:]
}
```

### Pattern 3: Session Resume on App Launch
**What:** Check for persisted sessions on app launch, offer resume picker if found
**When to use:** Every app launch to provide continuity
**Example:**
```swift
// Source: SessionResumePicker already exists, integrate with MainView
struct MainView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TerminalSession.lastActivity, order: .reverse)
    var persistedSessions: [TerminalSession]

    @State private var showResumePicker = false

    var body: some View {
        // ... main view content
        .onAppear {
            if !persistedSessions.isEmpty {
                // Convert to ClaudeCodeSession for picker
                Task {
                    let claudeSessions = await loadClaudeSessions(from: persistedSessions)
                    if !claudeSessions.isEmpty {
                        showResumePicker = true
                    }
                }
            }
        }
        .sheet(isPresented: $showResumePicker) {
            SessionResumePicker(sessions: claudeSessions) { session in
                if let session = session {
                    resumeSession(session)
                } else {
                    createFreshSession()
                }
            }
        }
    }
}
```

### Pattern 4: Graceful Stale Session Handling
**What:** Detect when `claude -r <sessionId>` fails due to stale/expired session, create fresh session instead
**When to use:** When resuming session that may have been cleaned up by Claude Code
**Example:**
```swift
// Source: Claude Code resume behavior from official docs
func attemptSessionResume(sessionId: String, workingDirectory: String?) async -> Bool {
    // Launch with resume flag
    ClaudeCodeLauncher.shared.launchClaudeCode(
        in: terminal,
        workingDirectory: workingDirectory,
        skipPermissions: true,
        resumeSessionId: sessionId
    )

    // Monitor terminal output for error indicators
    // Claude Code will show "Session not found" or similar if stale
    try? await Task.sleep(nanoseconds: 2_000_000_000) // 2s to detect failure

    let terminalContent = getTerminalContent(terminal)
    if terminalContent.contains("Session not found") ||
       terminalContent.contains("No session") {
        logWarning("Session \(sessionId) is stale, creating fresh session", category: .terminal)
        return false
    }

    return true
}
```

### Anti-Patterns to Avoid
- **Storing runtime references in @Model:** Coordinator and terminal references cannot be persisted, must be in separate manager
- **Optional vs Required confusion:** If Project relationship is required (non-optional), must use cascade delete rule or always set project
- **Forgetting inverse relationships:** Always specify inverse for One-to-Many relationships to avoid data inconsistency
- **Not handling stale sessions:** Always gracefully fallback to fresh session if resume fails

## Don't Hand-Roll

Problems that look simple but have existing solutions:

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Session state persistence | Custom JSON serialization | SwiftData @Model | Type-safe, automatic change tracking, relationships |
| Claude session discovery | Parse JSON manually | ClaudeSessionDiscoveryService (exists) | Already handles path escaping, JSON parsing, filtering |
| Session resume UI | Custom picker | SessionResumePicker (exists) | Already built with metadata display, filtering |
| Project-session association | Manual foreign keys | SwiftData @Relationship | Automatic inverse updates, delete rules |
| Stale session detection | Polling indefinitely | 2-3s timeout with error pattern check | Claude Code shows error quickly if session missing |

**Key insight:** The codebase already has 80% of the infrastructure (discovery service, resume picker, launch modes). Phase 19 is primarily about adding SwiftData persistence to existing runtime models.

## Common Pitfalls

### Pitfall 1: Mixing @Model and @Observable
**What goes wrong:** Attempting to use both macros on TerminalSession causes compile errors
**Why it happens:** @Model and @Observable use incompatible property wrapper implementations
**How to avoid:** Use @Model for TerminalSession (persistence), move coordinator/terminal refs to TerminalSessionManager
**Warning signs:** Compiler error "Type 'TerminalSession' does not conform to protocol 'Observable'"

### Pitfall 2: Non-Optional Relationships Without Delete Rules
**What goes wrong:** If `var project: Project` is required (non-optional), deleting project crashes unless delete rule is cascade
**Why it happens:** SwiftData enforces referential integrity - required relationships cannot be null
**How to avoid:** Use optional relationship `var project: Project?` with nullify delete rule (sessions can exist without project)
**Warning signs:** Crash when deleting project that has associated sessions

### Pitfall 3: Forgetting to Update lastActivity
**What goes wrong:** Sessions show stale "last activity" times, resume picker shows wrong order
**Why it happens:** lastActivity not updated when session receives prompts or shows terminal activity
**How to avoid:** Update lastActivity whenever: (1) prompt dispatched, (2) new terminal session created, (3) session becomes active
**Warning signs:** Resume picker shows sessions in wrong chronological order

### Pitfall 4: Assuming Session IDs Are Always Valid
**What goes wrong:** App tries to resume session that Claude Code has cleaned up, gets stuck or crashes
**Why it happens:** Claude Code may delete old sessions, or sessions from reinstalls
**How to avoid:** Always check for resume failure within 2-3 seconds, fallback to fresh session creation
**Warning signs:** Terminal shows "Session not found" error, app hangs waiting for session to load

### Pitfall 5: Path Escaping Mismatch
**What goes wrong:** Session discovery fails to find sessions because path escaping doesn't match Claude Code's scheme
**Why it happens:** Claude Code uses specific escaping (`/` → `-`, e.g., `/Users/eric/Dispatch` → `-Users-eric-Dispatch`)
**How to avoid:** Use ClaudeSessionDiscoveryService which already implements correct escaping/unescaping
**Warning signs:** `~/.claude/projects/<project>` exists but discovery returns empty array

## Code Examples

Verified patterns from official sources and existing codebase:

### TerminalSession as SwiftData Model
```swift
// Source: Existing Prompt.swift and PromptChain.swift patterns
@Model
final class TerminalSession: Identifiable {
    // MARK: - Properties
    var id: UUID
    var name: String
    var createdAt: Date
    var lastActivity: Date

    // Claude Code session resumption support
    var claudeSessionId: String? // Claude session ID if resuming
    var workingDirectory: String? // Project path for Claude Code

    // MARK: - Relationships
    var project: Project? // Optional - sessions can exist without project

    // MARK: - Initialization
    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        lastActivity: Date = Date(),
        claudeSessionId: String? = nil,
        workingDirectory: String? = nil,
        project: Project? = nil
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.lastActivity = lastActivity
        self.claudeSessionId = claudeSessionId
        self.workingDirectory = workingDirectory
        self.project = project
    }

    // MARK: - Computed Properties
    var isResumable: Bool {
        claudeSessionId != nil
    }

    var relativeLastActivity: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: lastActivity, relativeTo: Date())
    }

    // MARK: - Methods
    func updateActivity() {
        lastActivity = Date()
    }
}
```

### Project Model Update - Add Sessions Relationship
```swift
// Source: Existing Project.swift pattern
// In Project.swift, add to relationships section:

@Relationship(deleteRule: .nullify, inverse: \TerminalSession.project)
var sessions: [TerminalSession] = []

// Computed property for convenience
var sessionCount: Int {
    sessions.count
}
```

### Session Resume Flow with Stale Handling
```swift
// Source: Claude Code --resume documentation and existing ClaudeCodeLauncher
func resumeOrCreateSession(_ persistedSession: TerminalSession) async {
    guard let sessionId = persistedSession.claudeSessionId else {
        // No Claude session ID - create fresh
        createFreshSession(name: persistedSession.name)
        return
    }

    // Attempt resume
    let terminalSession = TerminalSessionManager.shared.createSession(
        name: persistedSession.name
    )

    // Session will use launchMode based on claudeSessionId property
    terminalSession?.claudeSessionId = sessionId
    terminalSession?.workingDirectory = persistedSession.workingDirectory

    // Wait for terminal to initialize and check for resume failure
    try? await Task.sleep(nanoseconds: 2_000_000_000) // 2s

    if let terminal = terminalSession?.terminal {
        let content = String(data: terminal.getTerminal().getBufferAsData(), encoding: .utf8) ?? ""

        if content.contains("Session not found") || content.contains("No session") {
            logWarning("Session \(sessionId) is stale, creating fresh", category: .terminal)

            // Close stale session and create fresh one
            if let id = terminalSession?.id {
                TerminalSessionManager.shared.closeSession(id)
            }
            createFreshSession(name: persistedSession.name)
        }
    }
}
```

### Persisting Session State Changes
```swift
// Source: SwiftData automatic change tracking
import SwiftData

@MainActor
final class TerminalSessionManager {
    // ... existing properties

    private var modelContext: ModelContext?

    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func createSession(name: String? = nil, project: Project? = nil) -> TerminalSession? {
        guard canCreateSession else { return nil }

        let sessionName = name ?? "Session \(nextSessionNumber)"
        nextSessionNumber += 1

        // Create SwiftData model
        let session = TerminalSession(name: sessionName, project: project)

        // Insert into context for persistence
        modelContext?.insert(session)

        sessions.append(session)

        if activeSessionId == nil {
            activeSessionId = session.id
        }

        logInfo("Created persistent session: \(session.name)", category: .terminal)
        return session
    }

    func updateSessionActivity(_ sessionId: UUID) {
        guard let session = sessions.first(where: { $0.id == sessionId }) else { return }
        session.updateActivity()
        // SwiftData automatically persists changes
    }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| @Observable only | @Model with SwiftData | Phase 19 | Sessions persist across app restarts |
| No project association | Project-session relationship | Phase 19 | Sessions organized by project |
| Manual session creation | Resume picker on launch | Phase 19 | Continuity, token savings from resume |
| Hardcoded session paths | ClaudeSessionDiscoveryService | Already exists | Reliable session discovery |

**Deprecated/outdated:**
- In-memory only sessions: Now persisted with SwiftData
- Weak references to coordinator/terminal in model: Move to separate runtime manager

## Open Questions

Things that couldn't be fully resolved:

1. **Session Cleanup Strategy**
   - What we know: Claude Code stores sessions in `~/.claude/projects/<project>/*.jsonl`
   - What's unclear: When does Claude Code prune old sessions? What triggers cleanup?
   - Recommendation: Keep Dispatch sessions for 7 days, prune on app launch. Match Claude Code's behavior if documented.

2. **Multiple Sessions Per Project**
   - What we know: User can have max 4 terminal sessions open simultaneously (SESS-06)
   - What's unclear: Should all 4 persist across restart, or only "active" one?
   - Recommendation: Persist all sessions up to max, show resume picker with all options

3. **Session-Project Auto-Association**
   - What we know: ClaudeCodeSession has projectPath, Dispatch has Project model with optional path
   - What's unclear: Should we auto-associate resumed session with Project by matching paths?
   - Recommendation: YES - on resume, lookup Project by path and set relationship. Saves manual organization.

## Sources

### Primary (HIGH confidence)
- [Claude Code Common Workflows - Official Docs](https://code.claude.com/docs/en/common-workflows) - Session resumption with `--resume`, `--continue`, session storage
- [Claude Code Memory Management - Official Docs](https://code.claude.com/docs/en/memory) - Session storage location `~/.claude/projects/<project>/memory/`
- Existing codebase models (Prompt.swift, PromptChain.swift, Project.swift) - SwiftData patterns
- Existing ClaudeSessionDiscoveryService.swift - Session discovery implementation
- Existing SessionResumePicker.swift - Resume UI implementation
- Existing TerminalSession.swift (@Observable) - Current session model

### Secondary (MEDIUM confidence)
- [SwiftData Relationships - Hacking with Swift](https://www.hackingwithswift.com/quick-start/swiftdata/how-to-create-cascade-deletes-using-relationships) - Delete rules and inverse relationships
- [SwiftData Relationships - FatBobMan](https://fatbobman.com/en/posts/relationships-in-swiftdata-changes-and-considerations/) - Best practices for relationships
- [Apple SwiftData @Relationship Documentation](https://developer.apple.com/documentation/swiftdata/relationship(_:deleterule:minimummodelcount:maximummodelcount:originalname:inverse:hashmodifier:)) - Official API reference
- [Resume Claude Code Sessions - Mehmet Baykar](https://mehmetbaykar.com/posts/resume-claude-code-sessions-after-restart/) - Community best practices

### Tertiary (LOW confidence)
- [GitHub Issue #22030 - Stale sessions-index.json](https://github.com/anthropics/claude-code/issues/22030) - Known issue with stale session metadata
- [GitHub Issue #21067 - Resume hangs with large outputs](https://github.com/anthropics/claude-code/issues/21067) - Performance issue, not directly related but good to be aware

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - SwiftData is established, codebase already uses it extensively
- Architecture: HIGH - Existing models provide clear patterns, discovery service is already built
- Pitfalls: MEDIUM - Some pitfalls inferred from best practices, not from direct experience
- Stale session handling: MEDIUM - Claude Code behavior documented but edge cases may exist

**Research date:** 2026-02-08
**Valid until:** 2026-03-08 (30 days - stable API)

## Summary for Planner

**What's already built (reuse these):**
- ClaudeSessionDiscoveryService - Discovers sessions from `~/.claude/projects/`
- SessionResumePicker - UI for selecting session to resume
- TerminalSession (@Observable) - In-memory session model with resume support
- ClaudeCodeLauncher - Handles `--resume <sessionId>` flag
- TerminalLaunchMode.claudeCodeResume - Launch mode for resuming sessions

**What needs to be built:**
- Convert TerminalSession to @Model (remove @Observable, coordinator/terminal refs)
- Add Project.sessions relationship (inverse, nullify delete rule)
- Persist sessions in TerminalSessionManager using ModelContext
- Load persisted sessions on app launch, show SessionResumePicker
- Implement stale session detection and fallback to fresh session
- Update lastActivity timestamp on session activity
- Auto-associate resumed sessions with Projects by matching paths

**Key architectural decision:**
Cannot mix @Model and @Observable on TerminalSession. Solution: Use @Model for persistence, move runtime references (coordinator, terminal) to TerminalSessionManager dictionaries keyed by UUID.

**Critical for success:**
1. Use existing ClaudeSessionDiscoveryService - don't rewrite path escaping logic
2. Handle stale sessions gracefully - 2-3s timeout, check for error patterns
3. Update lastActivity on every session interaction for accurate resume picker ordering
4. Test with actual Claude Code sessions in `~/.claude/projects/` directory

# Architecture

**Analysis Date:** 2026-02-03

## Pattern Overview

**Overall:** MVVM (Model-View-ViewModel) with Actor-based concurrency and layered service architecture.

**Key Characteristics:**
- SwiftUI-based declarative UI with reactive view models
- SwiftData for persistent storage (SQLite-backed)
- Actor-based services for concurrent operations (Terminal, HookServer, SkillDiscovery)
- MainActor-constrained ViewModels for UI thread safety
- Singleton pattern for shared services and view models
- Observable objects for state management and reactive UI updates
- Separation of concerns: Models → ViewModels → Views with Services layer

## Layers

**Models (Data Layer):**
- Purpose: Define the domain entities and business logic
- Location: `Dispatch/Models/`
- Contains: SwiftData `@Model` classes, enums, and supporting utilities
- Depends on: Foundation, SwiftData
- Used by: ViewModels, Services, Views via environment injection

**Services (Business Logic Layer):**
- Purpose: Handle external system interactions, concurrent operations, and complex logic
- Location: `Dispatch/Services/`
- Contains: Actor-based services, HTTP server, file system operations, Terminal integration
- Depends on: Models, Foundation, AppKit, Network framework
- Used by: ViewModels, app initialization, and other services

**ViewModels (Presentation Logic Layer):**
- Purpose: Transform and manage data for UI presentation, handle user actions
- Location: `Dispatch/ViewModels/`
- Contains: `@MainActor` ObservableObject classes with `@Published` properties
- Depends on: Models, Services, SwiftData, Combine
- Used by: Views via environment objects and state bindings

**Views (Presentation Layer):**
- Purpose: Define the UI hierarchy and user interactions
- Location: `Dispatch/Views/`
- Contains: SwiftUI View structures organized by feature area
- Depends on: Models, ViewModels (via EnvironmentObject), SwiftUI
- Used by: App entry point and parent views

**App Entry Point:**
- Location: `Dispatch/DispatchApp.swift`
- Triggers: Application launch and scene lifecycle
- Responsibilities: SwiftData container setup, singleton initialization, keyboard shortcuts, menu bar integration

## Data Flow

**Prompt Execution Flow:**

1. User selects prompt in UI (PromptListView)
2. View calls PromptViewModel method or posts notification
3. ViewModel retrieves Prompt model, resolves placeholders via PlaceholderResolver
4. QueueViewModel adds QueueItem to execution queue
5. TerminalService sends prompt content via AppleScript to Terminal.app
6. ExecutionStateMachine transitions: IDLE → SENDING → EXECUTING
7. HookServer receives HTTP POST from Claude Code's stop hook
8. ExecutionStateMachine transitions: EXECUTING → COMPLETED
9. QueueViewModel auto-runs next item or waits for manual trigger
10. PromptHistory records completed execution

**Chain Execution Flow:**

1. User selects PromptChain in UI (ChainEditorView)
2. ChainViewModel triggers execution via QueueViewModel
3. For each ChainItem in order:
   - Resolve content (library Prompt or inline)
   - Add to queue with configurable delay
   - Wait for hook completion signal
4. After all items complete, notify completion

**Data Persistence:**

1. SwiftData models persist automatically to SQLite
2. ViewModels configured with ModelContext on app launch
3. Manual saves via context.save() for batch operations
4. SettingsManager loads/creates singleton AppSettings on startup

**State Management:**

- **UI State**: Held in View @State properties (navigation, sheets, selections)
- **Presentation State**: Held in ViewModel @Published properties (search, sort, filter)
- **Execution State**: Held in ExecutionStateMachine (current state, context, result)
- **Persistent State**: Held in SwiftData models (Prompts, Projects, Chains, History)
- **Settings State**: Held in AppSettings model with SettingsManager singleton

## Key Abstractions

**Prompt:**
- Purpose: Core reusable unit of content sent to Claude Code
- Examples: `Dispatch/Models/Prompt.swift`
- Pattern: SwiftData `@Model` with computed properties for display, relationships to projects and chains

**PromptChain:**
- Purpose: Represents ordered sequence of prompts with delays
- Examples: `Dispatch/Models/PromptChain.swift`
- Pattern: SwiftData `@Model` containing array of ChainItem with ordering logic

**QueueItem:**
- Purpose: Pending execution unit (either library reference or inline content)
- Examples: `Dispatch/Models/QueueItem.swift`
- Pattern: SwiftData `@Model` with status enum, factory methods for creation

**ExecutionStateMachine:**
- Purpose: Manages state transitions during prompt execution
- Examples: `Dispatch/Services/ExecutionStateMachine.swift`
- Pattern: Actor-based singleton managing ExecutionState enum and ExecutionContext

**TerminalService:**
- Purpose: Encapsulates all Terminal.app interactions via AppleScript
- Examples: `Dispatch/Services/TerminalService.swift`
- Pattern: Actor-based singleton with caching for window enumeration, error handling for AppleScript failures

**HookServer:**
- Purpose: Local HTTP server (port 19847) receiving completion notifications from Claude Code
- Examples: `Dispatch/Services/HookServer.swift`
- Pattern: Actor-based manager implementing NWListener, handles `/hook/complete` and screenshot routes

**PlaceholderResolver:**
- Purpose: Parses and resolves `{{placeholder_name}}` template syntax in prompts
- Examples: `Dispatch/Services/PlaceholderResolver.swift`
- Pattern: Enum-based with regex patterns, supports built-in (clipboard, date, time) and custom placeholders

**SkillDiscoveryService & SkillManager:**
- Purpose: Load and manage Claude Code skills (custom slash commands) from filesystem
- Examples: `Dispatch/Models/Skill.swift`
- Pattern: Actor-based discovery with MainActor manager for starred/demoted tracking

## Entry Points

**Application Launch:**
- Location: `Dispatch/DispatchApp.swift` - @main struct
- Triggers: System launches Dispatch app
- Responsibilities:
  - Create and configure SwiftData ModelContainer
  - Initialize singleton services (HotkeyManager, HookServer, ScreenshotWatcher)
  - Register global hotkey (⌘⇧D default)
  - Install Claude Code hooks
  - Set up keyboard shortcuts and menu commands

**Main Window:**
- Location: `Dispatch/Views/MainView.swift`
- Triggers: App startup, reopened via dock/menu bar
- Responsibilities: Navigation hub, view model configuration, content routing

**Global Hotkey:**
- Location: `Dispatch/Services/HotkeyManager.swift`
- Triggers: User presses configured hotkey (default ⌘⇧D)
- Responsibilities: Show main window, optionally send clipboard as prompt

**Queue Execution:**
- Location: `Dispatch/ViewModels/QueueViewModel.swift` - runNext()/runAll()
- Triggers: User clicks button, menu item, or keyboard shortcut
- Responsibilities: Dequeue next item, resolve placeholders, execute via TerminalService

**Completion Detection:**
- Location: `Dispatch/Services/HookServer.swift` - POST /hook/complete
- Triggers: Claude Code stop hook calls webhook
- Responsibilities: Signal ExecutionStateMachine completion, advance to next queue item

## Error Handling

**Strategy:** Typed errors with localized descriptions, logged at appropriate levels, surfaced to UI via ViewModel error properties.

**Patterns:**

- **TerminalServiceError**: Enum with variants for Terminal-specific failures (not running, window not found, AppleScript execution failed, permission denied, timeout)
  - Location: `Dispatch/Services/TerminalService.swift`
  - Handling: Logged with category, displayed in error sheets or alerts in views

- **Try-Catch in Services**: Services wrap fallible operations with error handling
  - Location: `Dispatch/Services/TerminalService.swift`, `HookServer.swift`, `PlaceholderResolver.swift`
  - Pattern: Log error at appropriate level, return typed error or return nil for optional results

- **ViewModel Error Property**: ViewModels maintain @Published error property for UI binding
  - Location: All ViewModels (`PromptViewModel`, `QueueViewModel`, `ProjectViewModel`, etc.)
  - Pattern: Catch errors in async tasks, set error property which triggers UI error display

- **Logging Service**: Centralized logging with categories and levels
  - Location: `Dispatch/Services/LoggingService.swift`
  - Pattern: `logError()`, `logWarning()`, `logInfo()`, `logDebug()`, `logCritical()` global functions

## Cross-Cutting Concerns

**Logging:**
- Implementation: LoggingService with OSLog integration
- Categories: app, data, ui, queue, execution, terminal, hooks, settings, chain, simulator, skills
- Levels: debug, info, warning, error, critical
- Pattern: Global functions `logDebug()`, `logInfo()`, `logWarning()`, `logError()`, `logCritical()`

**Validation:**
- Prompt content: PlaceholderResolver validates placeholder syntax during parsing
- QueueItem: `hasContent` property validates presence of prompt or inline content
- PromptChain: `isValid` computed property checks all items have valid content
- AppSettings: Setter methods validate ranges (port 1024-65535, font size 12-18, retention 1-365 days)
- Implementation: Guards and conditional checks in model initializers and setters

**Authentication:**
- Terminal.app control: Requires Accessibility permission (macOS) - verified at runtime
- AppleScript execution: Error handling surfaces permission denied errors
- Hook server: Listens on localhost only (127.0.0.1), no authentication (single-user desktop app)

**Threading:**
- MainActor: All ViewModels and UI-related code
- Actor: Services (TerminalService, HookServer, SkillDiscoveryService) for concurrent safety
- Task: Async operations wrapped in Tasks, dispatched to appropriate actors
- UI Updates: All SwiftUI binding changes must occur on MainActor (enforced by compiler)

**File I/O:**
- Skill discovery: Async file enumeration via FileManager in SkillDiscoveryService
- AppSettings: Persisted via SwiftData ModelContext
- Hook installer: Writes ~/.claude/hooks/stop.sh for Claude Code integration
- Screenshot watcher: Monitors ~/Claude\ Code\ Simulator directory for new screenshots

**Concurrency:**
- Actor-based services prevent race conditions on shared state
- Published properties on MainActor ViewModels ensure thread-safe UI updates
- Async/await for all long-running operations (Terminal commands, HTTP server, file I/O)
- Proper task cancellation in QueueViewModel when user cancels execution

---

*Architecture analysis: 2026-02-03*

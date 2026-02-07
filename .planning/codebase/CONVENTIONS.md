# Coding Conventions

**Analysis Date:** 2026-02-03

## Naming Patterns

**Files:**
- PascalCase with descriptive names: `PromptViewModel.swift`, `TerminalService.swift`, `DispatchButton.swift`
- Component views: `[Name]View.swift` for screen-level views
- Reusable components: `[Name]Component.swift` or simple name like `DispatchButton.swift`
- Services: `[Name]Service.swift` (e.g., `TerminalService.swift`, `LoggingService.swift`)
- Models: Direct type name (e.g., `Prompt.swift`, `Project.swift`)

**Functions:**
- camelCase: `fetchPrompts()`, `createPrompt()`, `sendPrompt()`
- Verb-first for actions: `toggleStarred()`, `updatePrompt()`, `deletePrompt()`
- Boolean functions use `is`, `has`, or simple verb: `isTerminalRunning()`, `hasPlaceholders`, `shouldLog()`
- Private functions prefixed with underscore for true private methods: `_applyFilters()`, `_setupSearchDebounce()`

**Variables:**
- camelCase: `selectedPrompt`, `isLoading`, `searchText`
- Boolean flags: `isStarred`, `isLoading`, `isPaused`, `isFromChain`, `useHooks`
- Published properties: `@Published var prompts: [Prompt] = []`

**Types:**
- PascalCase enums: `ExecutionState`, `PromptSortOption`, `LogLevel`
- Enum cases: lowercase raw values or camelCase: `case idle`, `case recentlyUsed`
- Struct/Class types: `ExecutionContext`, `TerminalWindow`, `LogEntry`

**View Models & State Objects:**
- Suffix with `ViewModel`: `PromptViewModel`, `ProjectViewModel`, `ChainViewModel`
- Singleton pattern common: `ProjectViewModel.shared`, `ChainViewModel.shared`

## Code Style

**Formatting:**
- 4-space indentation (Swift default)
- Line length limit appears to be ~120 characters (no explicit config detected)
- Imports organized: Foundation/SwiftUI first, then custom modules
- Space around operators

**Linting:**
- No `.swiftlint.yml` or SwiftFormat config detected
- Code follows standard Swift conventions without external linters
- Consistent indentation and spacing across codebase

## Import Organization

**Order:**
1. Foundation/system imports: `import Foundation`, `import SwiftUI`, `import AppKit`
2. Framework imports: `import SwiftData`, `import Combine`
3. Custom imports: `@testable import Dispatch`

**Path Aliases:**
- None detected (no module aliases or custom paths used)
- Direct imports from main Dispatch target

## Error Handling

**Patterns:**
- Typed errors preferred: Custom `Error` enums with `LocalizedError` conformance
- Error enums defined at file scope: `enum PromptError`, `enum TerminalServiceError`, `enum ExecutionError`
- Each error type implements `errorDescription` property for user-facing messages
- Async/await used for error propagation: `func sendPrompt() async throws`
- Try-catch blocks with `logError()` calls: Errors logged at point of catch, not silently swallowed
- Guard statements for early returns on error conditions

**Common Error Types:**
- `PromptError`: `.unresolvedPlaceholders`, `.emptyContent`
- `TerminalServiceError`: `.terminalNotRunning`, `.noWindowsOpen`, `.timeout`, `.permissionDenied`
- `ExecutionError`: `.alreadyExecuting`, `.queueEmpty`, `.chainEmpty`
- `HookServerError`, `HookInstallerError`, `ScreenshotWatcherError`, `PlaceholderValidationError`

**Error Logging:**
```swift
// Pattern: Log at catch point
catch {
    self.error = error.localizedDescription
    logError("Failed to fetch prompts: \(error)", category: .data)
}

// Or via extension method
error.log(as: .warning, category: .app, context: "Context description")
```

## Logging

**Framework:** Custom `LoggingService` (actor-based, not print/console)

**Log Levels:** debug, info, warning, error, critical

**Log Categories:**
- `.app` - App lifecycle, general
- `.data` - SwiftData operations, persistence
- `.terminal` - Terminal integration, AppleScript
- `.queue` - Queue operations
- `.chain` - Chain execution
- `.hooks` - Hook server, completion detection
- `.hotkey` - Global hotkey
- `.placeholder` - Placeholder resolution
- `.ui` - View updates, user interactions
- `.settings` - Settings changes
- `.history` - History operations
- `.execution` - Execution state machine
- `.network` - Network operations
- `.simulator` - Simulator screenshot operations

**Patterns:**
```swift
logDebug("Message", category: .data)
logInfo("Message", category: .execution)
logWarning("Message", category: .terminal)
logError("Failed operation: \(error)", category: .data)
logCritical("Critical error", category: .app)
```

**Special utilities:**
- `PerformanceLogger`: For measuring operation duration
- `measurePerformance()`: Generic function for scoped timing
- `LogEntry.formattedMessage`: Includes timestamp, level, category, thread indicator, file:line, function

## Comments

**When to Comment:**
- `// MARK: - Section Name` for organizing code into sections (widely used throughout codebase)
- Only one TODO found in codebase (`// TODO: Save to library with sheet for title`), indicating code generally complete
- Comments explain WHY, not WHAT: "Cache windows for 2 seconds to avoid redundant queries"
- Doc comments for public APIs: "Checks if Terminal.app is running"

**Mark Sections:**
Standard sections in most types:
- `// MARK: - Properties` (or Published Properties, Private Properties)
- `// MARK: - Initialization`
- `// MARK: - Computed Properties`
- `// MARK: - Methods`
- `// MARK: - State Transitions`
- `// MARK: - Polling Support`
- `// MARK: - Error Handling`

Example from `PromptViewModel`:
```swift
// MARK: - Sort Options
// MARK: - Filter Options
// MARK: - Prompt ViewModel
// MARK: - Published Properties
// MARK: - Private Properties
// MARK: - Initialization
// MARK: - Fetch
// MARK: - CRUD Operations
// MARK: - Selection
// MARK: - Actions
// MARK: - Sending
```

## Function Design

**Size:** Functions typically 10-40 lines; larger methods (60-100 lines) broken into helper functions
- `fetchPrompts()`: 42 lines (acceptable for complex SwiftData query)
- `execute()` in ExecutionManager: 59 lines (orchestration function, acceptable)
- Helper functions extracted: `_applyFilters()`, `_setupSearchDebounce()`, `_notifyStateChange()`

**Parameters:**
- Default parameters used for optional behavior: `func createPrompt(title: String = "", content: String = "")`
- Parameter labels descriptive: `toWindowId`, `isFromChain`, `useHooks`
- No excessive parameters (max ~8); multi-parameter functions use structs for context (e.g., `ExecutionContext`)

**Return Values:**
- Explicit optionals for nullable results: `func createPrompt() -> Prompt?`
- Result enums for complex outcomes: `enum ExecutionResult` with cases `.success`, `.failure(Error)`, `.cancelled`
- Async/await preferred over completion handlers: `async throws` pattern

## Module Design

**Exports:**
- All public types are class/struct definitions in their files
- No explicit export declarations needed (Swift default behavior)
- Service classes marked `final` to prevent subclassing: `final class PromptViewModel`, `final class ExecutionStateMachine`

**Barrel Files:**
- No barrel files detected
- Each file exports its primary type only

**Actor Usage:**
- `LoggingService` implements Swift 5.5+ actors for thread safety
- `TerminalService` is actor-based for AppleScript isolation
- Services use `actor` keyword for concurrent safety without manual locks

**Singleton Pattern:**
- Common for shared services: `static let shared = TerminalService()`
- ViewModels also use shared instances: `ProjectViewModel.shared`, `ChainViewModel.shared`
- Private initializers enforce singleton: `private init() {}`

**@MainActor Annotation:**
- Widely used (25 instances): `@MainActor final class PromptViewModel`
- Ensures UI updates happen on main thread
- Also used on individual functions: `@MainActor func selectPrompt()`

## Data Models

**SwiftData Usage:**
- All models marked `@Model final class`
- Relationships use `@Relationship` macro with delete rules: `@Relationship(deleteRule: .nullify, inverse: \Prompt.project)`
- Computed properties for derived data: `displayTitle`, `previewText`, `relativeUpdatedTime`
- Timestamps on all models: `createdAt`, `updatedAt`
- Methods modify state and update timestamps: `recordUsage()`, `updateContent()`, `toggleStarred()`

## SwiftUI Patterns

**State Management:**
- `@Published` properties for ViewModel reactive updates
- `@State` for local view state
- `@Environment` for model context: `@Environment(\.modelContext) private var modelContext`
- `@StateObject` for ViewModel lifecycle: `@StateObject private var promptVM = PromptViewModel()`

**Views:**
- Struct-based: `struct PromptListView: View`
- `body` computed property returns view hierarchy
- Private computed properties for subviews: `private var singleTerminalButton: some View`
- `@ViewBuilder` for conditional view composition

## Concurrency

**Async/Await:**
- New code uses async/await: `async throws` functions
- `Task { @MainActor in ... }` for main thread updates from background
- `MainActor.run { ... }` for explicit main dispatch
- Task cancellation checks: `guard !Task.isCancelled else { break }`

**Threading Model:**
- UI code: `@MainActor` or runs in UI update context
- Background work: Services use actors or dispatch queues
- FileLogDestination uses `DispatchQueue(label: "...", qos: .utility)`

---

*Convention analysis: 2026-02-03*

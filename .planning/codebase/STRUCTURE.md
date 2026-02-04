# Codebase Structure

**Analysis Date:** 2026-02-03

## Directory Layout

```
Dispatch/
├── Assets.xcassets/           # App icons and color sets
├── Models/                    # SwiftData models and domain entities
├── Services/                  # Business logic layer (Actors, HTTP, file I/O)
├── ViewModels/                # MVVM presentation layer (MainActor)
├── Views/                     # SwiftUI components organized by feature
├── Utilities/                 # Helper extensions and utilities
├── Resources/                 # Non-Swift resources (scripts, data)
└── DispatchApp.swift          # App entry point

Views/
├── Chains/                    # Chain creation and editing
├── ClaudeFiles/               # Claude file editing interface
├── Components/                # Reusable UI components (DispatchButton, SearchBar, etc.)
├── History/                   # Execution history display
├── MenuBar/                   # Menu bar extra UI
├── Prompts/                   # Prompt list, editor, row components
├── Queue/                     # Queue panel and execution UI
├── Settings/                  # App settings window
├── Sidebar/                   # Navigation sidebar
├── Simulator/                 # Screenshot simulation and annotation
├── Skills/                    # Skills panel, skill viewer, file browser
└── MainView.swift             # Root navigation and content routing
```

## Directory Purposes

**Models:**
- Purpose: Define persistent entities and business domain
- Contains: SwiftData @Model classes, enums, value types, and related utilities
- Key files: `Prompt.swift`, `Project.swift`, `PromptChain.swift`, `QueueItem.swift`, `AppSettings.swift`, `PromptHistory.swift`, `Skill.swift`, `SimulatorRun.swift`, `Screenshot.swift`, `ClaudeFile.swift`, `AnnotationTypes.swift`, `ChainItem.swift`

**Services:**
- Purpose: Handle external system interactions, concurrent operations, and core business logic
- Contains: Actor-based services, HTTP server, file system operations, integration layers
- Key files: `ExecutionStateMachine.swift`, `TerminalService.swift`, `HookServer.swift`, `PlaceholderResolver.swift`, `HotkeyManager.swift`, `LoggingService.swift`, `ScreenshotWatcherService.swift`, `ProjectDiscoveryService.swift`, `HookInstaller.swift`, `AnnotationRenderer.swift`

**ViewModels:**
- Purpose: Transform model data for UI presentation, handle user actions, manage state
- Contains: @MainActor ObservableObject classes with reactive properties
- Key files: `PromptViewModel.swift`, `ProjectViewModel.swift`, `QueueViewModel.swift`, `ChainViewModel.swift`, `HistoryViewModel.swift`, `SimulatorViewModel.swift`

**Views:**
- Purpose: Define SwiftUI UI hierarchy and user interactions
- Contains: View structs organized by feature area/responsibility
- Subdirectories: Chains, ClaudeFiles, Components, History, MenuBar, Prompts, Queue, Settings, Sidebar, Simulator, Skills

**Assets:**
- Purpose: App icon set and color definitions
- Contains: AppIcon.appiconset, AccentColor.colorset

**Resources:**
- Purpose: Non-Swift application resources
- Contains: Scripts subdirectory with shell scripts and templates

**Utilities:**
- Purpose: Shared helper functions, extensions, and constants (if present)

## Key File Locations

**Entry Points:**
- `Dispatch/DispatchApp.swift`: Main app struct with SwiftData container setup, singleton initialization, keyboard commands

**Configuration:**
- `Dispatch/Models/AppSettings.swift`: All app configuration (hotkey, ports, UI preferences, data retention)
- `Dispatch/Services/HookServer.swift`: Hook server configuration (port 19847)

**Core Logic:**
- `Dispatch/Services/ExecutionStateMachine.swift`: Prompt execution state management (IDLE → SENDING → EXECUTING → COMPLETED)
- `Dispatch/ViewModels/QueueViewModel.swift`: Queue management and execution orchestration
- `Dispatch/Services/TerminalService.swift`: Terminal.app integration via AppleScript

**Data Models:**
- `Dispatch/Models/Prompt.swift`: Core prompt entity with placeholders
- `Dispatch/Models/Project.swift`: Project organization with color coding
- `Dispatch/Models/PromptChain.swift`: Chain sequences with ordering and delays
- `Dispatch/Models/QueueItem.swift`: Queue execution units

**Testing:**
- `Dispatch/Views/MainView.swift`: Preview includes in-memory model container for SwiftUI previews

## Naming Conventions

**Files:**
- Models: PascalCase singular noun (`Prompt.swift`, `Project.swift`, `ChainItem.swift`)
- ViewModels: PascalCase with ViewModel suffix (`PromptViewModel.swift`, `QueueViewModel.swift`)
- Views: PascalCase with feature-specific naming (`PromptListView.swift`, `PromptEditorView.swift`, `QueuePanelView.swift`)
- Services: PascalCase with Service suffix (`TerminalService.swift`, `HookServer.swift`, `LoggingService.swift`)
- Utilities: PascalCase descriptive names (`PlaceholderResolver.swift`)

**Directories:**
- Feature areas: PascalCase plural or feature name (`Views/Prompts/`, `Views/Chains/`, `Views/Simulator/`)
- Models and Services: PascalCase descriptive (`Models/`, `Services/`)

**Code Identifiers:**
- Classes: PascalCase (`PromptViewModel`, `TerminalService`, `AppDelegate`)
- Structs: PascalCase (`Prompt`, `Project`, `NavigationSelection`)
- Enums: PascalCase (`ExecutionState`, `PromptFilterOption`, `SkillScope`)
- Properties: camelCase (`isStarred`, `targetWindowId`, `promptContent`)
- Functions/Methods: camelCase (`fetchPrompts()`, `addToQueue()`, `sendPrompt()`)
- Constants: camelCase with leading underscore for private module constants, or CONSTANT_CASE for public constants

## Where to Add New Code

**New Feature (Prompt Management Example):**
- Primary code: `Dispatch/Models/Prompt.swift` for model, `Dispatch/ViewModels/PromptViewModel.swift` for presentation logic
- UI implementation: `Dispatch/Views/Prompts/[FeatureName]View.swift`
- Services if needed: `Dispatch/Services/[NewService].swift`
- Tests: `.xcodeproj/Tests/[FeatureName]Tests.swift` (if test target added)

**New Component/Module:**
- Implementation: `Dispatch/Views/Components/[ComponentName].swift` for reusable UI
- Logic: Corresponding ViewModel in `Dispatch/ViewModels/`
- Data: Corresponding Model in `Dispatch/Models/`

**Utilities/Helpers:**
- Shared extensions: `Dispatch/Utilities/[Category]Extensions.swift` (e.g., ColorExtensions, StringExtensions)
- Shared functions: `Dispatch/Utilities/[FunctionCategory].swift` or module-level in existing files
- Logging: Use existing `LoggingService` - no need to create new logging utilities

**New Service Layer:**
- Create in: `Dispatch/Services/[NewService].swift`
- Pattern: Use actor for concurrent operations, singleton static property, @MainActor wrapper if UI state management needed
- Examples: `TerminalService`, `HookServer`, `SkillDiscoveryService`

**New ViewModel:**
- Create in: `Dispatch/ViewModels/[Feature]ViewModel.swift`
- Pattern: @MainActor final class extending ObservableObject, singleton via static let shared or per-instance
- Requirements: @Published properties for reactive UI, configure(with:) method accepting ModelContext, error handling with @Published error property

**New View:**
- Create in: `Dispatch/Views/[Feature]/[ViewName].swift`
- Pattern: struct View, use @StateObject for view model injection, @EnvironmentObject for shared view models
- Structure: MARK comments for logical sections (Environment, State, Body, Actions, Helpers)

## Special Directories

**Assets.xcassets:**
- Purpose: App icon, color set definitions for Xcode asset management
- Generated: Xcode-managed, auto-compiled
- Committed: Yes, checked into git

**Resources/Scripts:**
- Purpose: Shell scripts and templates for Claude Code hooks, utilities
- Generated: No, manually maintained
- Committed: Yes, checked into git

**Views/Simulator:**
- Purpose: Screenshot capture, annotation, and run management UI
- Special: Contains complex canvas rendering via AnnotationRenderer service
- Integration: Monitors ~/Claude\ Code\ Simulator directory via ScreenshotWatcherService

**Views/Skills:**
- Purpose: Claude Code skills (slash commands) discovery and execution
- Special: Integrates with SkillDiscoveryService and SkillManager
- Scope: System-wide (~/.claude/skills) and project-level (.claude/skills)

**Models - Data Relationships:**
- Project: Contains many Prompts (inverse) and PromptChains (inverse)
- Prompt: Belongs to Project (optional), referenced by ChainItems and QueueItems
- PromptChain: Belongs to Project (optional), contains many ChainItems (cascade delete)
- ChainItem: Belongs to PromptChain, references optional Prompt
- QueueItem: References optional Prompt, stores inline content alternative
- PromptHistory: Immutable snapshot of sent prompts (no inverse relationships)
- AppSettings: Singleton, no relationships to other models

---

*Structure analysis: 2026-02-03*

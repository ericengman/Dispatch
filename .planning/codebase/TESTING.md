# Testing Patterns

**Analysis Date:** 2026-02-03

## Test Framework

**Runner:**
- Swift Testing framework (XCTest available for legacy)
- XCTest used for UI tests
- Swift Testing used for unit tests (`@testable import Dispatch`)

**Config:**
- Xcode project: `Dispatch.xcodeproj`
- Two test targets: `DispatchTests` (unit), `DispatchUITests` (UI)
- No external test configuration files (pytest, vitest, etc.)

**Run Commands:**
```bash
# Build and run all tests
xcodebuild -project Dispatch.xcodeproj -scheme Dispatch -configuration Debug test

# Run only unit tests
xcodebuild -project Dispatch.xcodeproj -scheme DispatchTests test

# Run UI tests
xcodebuild -project Dispatch.xcodeproj -scheme DispatchUITests test

# Run specific test class
xcodebuild -project Dispatch.xcodeproj -scheme DispatchTests -only-testing:DispatchTests/TestClassName test

# Run specific test method
xcodebuild -project Dispatch.xcodeproj -scheme DispatchTests -only-testing:DispatchTests/TestClassName/testMethodName test

# Clean build
xcodebuild -project Dispatch.xcodeproj -scheme Dispatch clean
```

## Test File Organization

**Location:**
- Unit tests: `DispatchTests/DispatchTests.swift` (co-located at project level, not adjacent to source)
- UI tests: `DispatchUITests/` directory with separate target
- No tests currently adjacent to source files

**Naming:**
- Unit test file: `DispatchTests.swift` (mirrors project name)
- UI test file: `DispatchUITests.swift`
- Test structs/classes named same as target

**Structure:**
```
Dispatch.xcodeproj/
├── Dispatch/                 # Main app source
├── DispatchTests/            # Unit tests (separate directory)
│   └── DispatchTests.swift
└── DispatchUITests/          # UI tests (separate directory)
    ├── DispatchUITests.swift
    └── DispatchUITestsLaunchTests.swift
```

## Test Structure

**Unit Test Suite Organization:**

Current structure uses Swift Testing minimal approach:

```swift
import Testing
@testable import Dispatch

struct DispatchTests {
    @Test func example() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
    }
}
```

**Recommended Patterns (to implement):**

Unit tests should follow this structure:

```swift
import Testing
@testable import Dispatch

struct PromptViewModelTests {
    var viewModel: PromptViewModel
    var modelContext: ModelContext

    init() {
        // Setup shared state if needed
        self.viewModel = PromptViewModel()
        // Configure model context for testing
    }

    @Test func testFetchPromptsSucceeds() async throws {
        // Arrange
        let expectedCount = 3
        // Act
        viewModel.fetchPrompts()
        // Assert
        #expect(viewModel.prompts.count == expectedCount)
    }

    @Test("descriptive test name") func testSpecificBehavior() async throws {
        // Test implementation
    }
}
```

**Setup/Teardown:**

Currently minimal (not implemented in test files). Recommended patterns:

```swift
// Per-test setup
init() {
    // Runs before each test
}

// Per-suite setup (if needed)
static var setupOnce: Void = {
    // Runs once before all tests in suite
}()
```

**Async Testing Pattern:**

Tests are marked `async` and can use `await`:

```swift
@Test func testAsyncOperation() async throws {
    let result = try await someAsyncFunction()
    #expect(result != nil)
}
```

## Mocking

**Framework:** None detected currently

**Where Mocking is Needed:**
- External service calls (TerminalService, HookServer)
- SwiftData ModelContext interactions
- AppleScript execution results
- File I/O operations

**Recommended Patterns (to implement):**

For services, use dependency injection:

```swift
class PromptViewModel {
    let terminalService: TerminalService

    init(terminalService: TerminalService = .shared) {
        self.terminalService = terminalService
    }
}

// For testing: create mock
class MockTerminalService: TerminalService {
    var sendPromptCalled = false

    override func sendPrompt(_ content: String, toWindowId: String?) async throws {
        sendPromptCalled = true
    }
}

// Use in test
@Test func testSendPrompt() async throws {
    let mock = MockTerminalService()
    let viewModel = PromptViewModel(terminalService: mock)

    try await viewModel.sendPrompt(...)
    #expect(mock.sendPromptCalled)
}
```

**What to Mock:**
- External system calls (Terminal.app, AppleScript)
- Network requests (Hook server)
- File system operations
- Time-dependent operations

**What NOT to Mock:**
- Core data models (Prompt, Project, etc.)
- View logic (that should be integration tested)
- Internal service orchestration
- Logging calls (not worth mocking)

## Fixtures and Factories

**Test Data:**
No fixture files currently exist. Recommended pattern:

```swift
// Create in DispatchTests/Fixtures/ or inline
struct TestFixtures {
    static func makePrompt(
        title: String = "Test Prompt",
        content: String = "Test content",
        isStarred: Bool = false
    ) -> Prompt {
        Prompt(title: title, content: content, isStarred: isStarred)
    }

    static func makeProject(
        name: String = "Test Project",
        colorHex: String = "#4DABF7"
    ) -> Project {
        Project(name: name, colorHex: colorHex)
    }
}

// Use in tests
@Test func testPromptFiltering() async throws {
    let prompt1 = TestFixtures.makePrompt(isStarred: true)
    let prompt2 = TestFixtures.makePrompt(isStarred: false)
    // Test filtering logic
}
```

**Location:**
- Option 1: Inline helper functions in test files
- Option 2: Create `DispatchTests/Fixtures/` subdirectory
- Option 3: Create protocol extension for default test data

## Coverage

**Requirements:** Not enforced

**View Coverage:**
No coverage configuration detected. To enable:

```bash
# Run tests with coverage
xcodebuild \
  -project Dispatch.xcodeproj \
  -scheme Dispatch \
  -derivedDataPath ./build \
  -enableCodeCoverage YES \
  test
```

**View Coverage Report:**
```bash
# Generate Xcode coverage report (in Xcode UI)
# Product > Scheme > Edit Scheme > Test > Options > Code Coverage: Enabled
```

## Test Types

**Unit Tests:**
- Scope: Individual services, view models, models
- Approach: Test public methods and properties
- Location: `DispatchTests/DispatchTests.swift`
- Current coverage: Minimal (placeholder tests only)
- Should test:
  - `PromptViewModel`: fetch, create, update, delete operations
  - `ExecutionStateMachine`: state transitions, event handling
  - `PlaceholderResolver`: placeholder extraction and replacement
  - `Project`, `Prompt`: model methods and computed properties

**Integration Tests:**
- Not explicitly organized
- Could test: ViewModel + Model interactions, queue execution flow
- Example: Create prompt → Execute → Check history entry created
- Location: Could be in same `DispatchTests` with naming convention

**E2E Tests:**
- Framework: XCTest (UI tests in `DispatchUITests`)
- Current state: Placeholder tests only
- Approach: Use XCUIApplication to interact with app
- Would test: Full prompt dispatch flow, queue execution, settings

**Example E2E Test Structure:**
```swift
import XCTest

final class DispatchUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testSendPromptWorkflow() throws {
        let app = XCUIApplication()
        app.launch()

        // Create a prompt
        app.buttons["New Prompt"].tap()
        let titleField = app.textFields["Prompt Title"]
        titleField.typeText("Test Prompt")

        // Send it
        app.buttons["Send"].tap()

        // Verify success
        let successIndicator = app.staticTexts["Success"]
        XCTAssertTrue(successIndicator.exists)
    }
}
```

## Common Patterns

**Async Testing:**

Swift Testing handles async naturally:

```swift
@Test func testAsyncFetch() async throws {
    viewModel.fetchPrompts()
    try await Task.sleep(nanoseconds: 100_000_000) // Wait for async work
    #expect(viewModel.isLoading == false)
}
```

**Error Testing:**

Use `#expect(throws:)` for async throws:

```swift
@Test func testEmptyPromptThrows() async throws {
    let error = try #require(throws: PromptError.emptyContent) {
        try await viewModel.sendPrompt("")
    }
    #expect(error == .emptyContent)
}
```

Or simpler form:

```swift
@Test func testErrorHandling() async throws {
    let viewModel = PromptViewModel()
    await #expect(throws: PromptError.self) {
        try await viewModel.sendPrompt("")
    }
}
```

**Main Thread Testing:**

Use `@MainActor` on test methods that need main thread:

```swift
@MainActor
@Test func testUIStateUpdate() {
    viewModel.selectPrompt(testPrompt)
    #expect(viewModel.selectedPrompt == testPrompt)
}
```

**Testing State Machines:**

For ExecutionStateMachine:

```swift
@Test func testStateTransition() async {
    let machine = ExecutionStateMachine()

    let context = ExecutionContext(
        promptContent: "Test",
        promptTitle: "Test Prompt"
    )

    machine.beginSending(context: context)
    #expect(machine.state == .sending)

    machine.beginExecuting()
    #expect(machine.state == .executing)
}
```

**Testing Published Properties:**

For ViewModel assertions:

```swift
@Test func testPublishedPropertyUpdate() async throws {
    let viewModel = PromptViewModel()
    viewModel.isLoading = true

    #expect(viewModel.isLoading == true)
    #expect(viewModel.prompts.isEmpty) // Initial state
}
```

**Testing Logging:**

Generally don't mock logging, but can verify by checking:

```swift
@Test func testLoggingOnError() async throws {
    // Logging happens internally
    // Verify through observable side effects (state changes, error properties)
    let viewModel = PromptViewModel()

    // Trigger an error condition
    // Verify error state is set
    #expect(viewModel.error != nil)
}
```

## Test Environment Configuration

**Swift Version:** Swift 6 (from project)

**macOS Version:** 14.0 (Sonoma) minimum

**Frameworks Available:**
- Foundation
- SwiftUI
- SwiftData
- Combine
- AppKit (for Terminal integration testing)

**Dependencies:**
- HotKey package (for global hotkey - may need mocking)

## Current Test Status

**Coverage Gap Analysis:**
- `DispatchTests.swift`: Empty placeholder (example test only)
- `DispatchUITests.swift`: Minimal setup, no actual tests
- No actual test implementations exist
- All business logic untested (PromptViewModel, ExecutionStateMachine, Services)

**Priority Test Areas (in order):**
1. **PromptViewModel** (`PromptViewModel.swift`): CRUD operations, filtering, sorting
2. **ExecutionStateMachine** (`ExecutionStateMachine.swift`): State transitions, timeout logic
3. **PlaceholderResolver** (`PlaceholderResolver.swift`): Pattern matching, replacement
4. **TerminalService** (`TerminalService.swift`): Window detection (with mocks)
5. **Models** (`Prompt.swift`, `Project.swift`): Property updates, computed properties
6. **QueueViewModel** (`QueueViewModel.swift`): Queue item management
7. **ChainViewModel** (`ChainViewModel.swift`): Chain execution orchestration

---

*Testing analysis: 2026-02-03*

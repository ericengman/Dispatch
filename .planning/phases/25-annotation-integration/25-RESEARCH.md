# Phase 25: Annotation Integration - Research

**Researched:** 2026-02-09
**Domain:** SwiftUI Window Management & Screenshot Workflow Integration
**Confidence:** HIGH

## Summary

Phase 25 integrates the screenshot capture flow (Phases 23-24) with the existing annotation infrastructure. The core challenge is **automatic window opening** after capture and **session selection** before dispatch. Both are well-supported patterns in SwiftUI macOS development.

The architecture leverages existing components:
- **AnnotationWindow** - Already exists for Simulator screenshots, can be reused
- **AnnotationViewModel** - Already has queueing (sendQueue) and clipboard dispatch
- **ScreenshotCaptureService** - Returns `CaptureResult.success(URL)` after capture

The integration flow: Capture → Auto-open AnnotationWindow → Load screenshot → Queue multiple → Select session → Dispatch.

**Primary recommendation:** Use SwiftUI's `openWindow` environment action with value-based WindowGroup to open annotation UI automatically after capture. Add session picker to AnnotationWindow's dispatch section. Reuse existing queue infrastructure (already supports 5 images).

## Standard Stack

The established libraries/tools for this domain:

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| SwiftUI WindowGroup | macOS 13+ | Window management | Data-driven window lifecycle with automatic identity |
| openWindow environment | macOS 13+ | Programmatic window opening | Modern SwiftUI API for launching windows from events |
| @Observable | Swift 5.9+ | State management | Already used throughout Dispatch for ViewModels |
| NSPasteboard | macOS 10.0+ | Clipboard operations | Standard macOS clipboard API (already in use) |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| @Environment(\.openWindow) | macOS 13+ | Window opening action | Trigger from capture completion handler |
| Hashable + Codable | Swift stdlib | WindowGroup value identity | State restoration and window matching |
| TerminalSessionManager | Dispatch | Session listing | Enumerate Claude Code sessions for picker |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| openWindow | NSWindowController | Loses SwiftUI lifecycle, state restoration, window deduplication |
| Value-based WindowGroup | Single shared window | Cannot queue captures while annotating (violates ANNOT-02) |
| TerminalSessionManager | NSOpenPanel for path | No awareness of Claude sessions, wrong UX paradigm |

**Installation:**
Built-in SwiftUI and AppKit frameworks - no dependencies needed.

**Project-specific components:**
- `AnnotationWindow` - Already implemented in `Dispatch/Views/Simulator/AnnotationWindow.swift`
- `AnnotationViewModel` - Already implemented in `Dispatch/ViewModels/SimulatorViewModel.swift`
- `TerminalSessionManager` - Session enumeration in `Dispatch/Services/TerminalSessionManager.swift`

## Architecture Patterns

### Recommended Project Structure
```
Services/
├── ScreenshotCaptureService.swift    # ✓ Exists: returns CaptureResult.success(URL)
└── (No new services needed)

Views/Simulator/
├── AnnotationWindow.swift            # ✓ Exists: reuse for QuickCaptures
├── AnnotationCanvasView.swift        # ✓ Exists: already works
└── SessionPickerView.swift           # → New: session selection dropdown

Models/
├── Screenshot.swift                  # ✓ Exists: can load from file path
└── QuickCapture.swift                # → New: wrapper for non-Run screenshots
```

### Pattern 1: Auto-Opening Window After Async Event
**What:** Open a window programmatically after an async task completes (e.g., capture)
**When to use:** User triggers action (capture) that produces data (screenshot) to display in new window
**Example:**
```swift
// Source: https://www.hackingwithswift.com/quick-start/swiftui/how-to-open-a-new-window
// Source: https://nilcoalescing.com/blog/ProgrammaticallyOpenANewWindowInSwiftUIOnMacOS/

// 1. Define value-based WindowGroup in App
@main
struct DispatchApp: App {
    var body: some Scene {
        WindowGroup {
            MainView()
        }

        // Value-based WindowGroup for annotation
        WindowGroup(for: QuickCapture.self) { $capture in
            if let capture = capture {
                AnnotationWindowContent(capture: capture)
            }
        }
    }
}

// 2. Trigger window opening from async completion
struct MainView: View {
    @Environment(\.openWindow) private var openWindow

    func handleCaptureComplete(result: CaptureResult) async {
        switch result {
        case .success(let url):
            // Create QuickCapture model
            let capture = QuickCapture(fileURL: url)

            // Open annotation window with this capture
            openWindow(value: capture)

        case .cancelled, .error:
            // Handle cancellation/errors
            break
        }
    }
}
```

**Key insights:**
- `openWindow(value:)` requires `Hashable` + `Codable` conformance
- SwiftUI ensures one window per unique value (multiple captures = multiple windows)
- Windows persist until user closes them (supports queueing multiple captures)

### Pattern 2: Data-Driven WindowGroup with State Restoration
**What:** WindowGroup that opens windows based on model values, with automatic state restoration
**When to use:** When each window represents a distinct piece of data (e.g., each screenshot annotation session)
**Example:**
```swift
// Source: https://www.fline.dev/window-management-on-macos-with-swiftui-4/
// Source: https://www.createwithswift.com/understanding-scenes-for-your-macos-app/

// Model must conform to Hashable + Codable
struct QuickCapture: Hashable, Codable, Identifiable {
    let id: UUID
    let fileURL: URL  // Path to screenshot
    let timestamp: Date

    // Hashable for window identity
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    // Codable for state restoration
    enum CodingKeys: String, CodingKey {
        case id, fileURL, timestamp
    }
}

// WindowGroup automatically:
// - Creates new window for new QuickCapture values
// - Brings existing window to front if same QuickCapture
// - Restores windows on app relaunch (if not closed)
```

**Benefits:**
- Automatic window identity management
- Built-in state restoration
- No manual NSWindow management

### Pattern 3: Session Picker in Dispatch UI
**What:** Dropdown picker showing available Claude Code terminal sessions before dispatch
**When to use:** Multi-session scenarios where user chooses target for dispatch
**Example:**
```swift
// Source: https://developer.apple.com/documentation/SwiftUI/Picker
// Source: Project pattern from TerminalSessionManager

struct SessionPickerView: View {
    @ObservedObject var sessionManager = TerminalSessionManager.shared
    @Binding var selectedSessionId: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Target Session")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("", selection: $selectedSessionId) {
                Text("Select session...").tag(nil as UUID?)

                ForEach(sessionManager.sessions) { session in
                    HStack {
                        Text(session.name)
                        Spacer()
                        if session.claudeSessionId != nil {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                    }
                    .tag(session.id as UUID?)
                }
            }
            .pickerStyle(.menu)
        }
    }
}
```

**Integration with existing dispatch:**
```swift
// In AnnotationWindowContent (existing file)
private var dispatchSection: some View {
    VStack(spacing: 12) {
        // NEW: Session picker
        SessionPickerView(selectedSessionId: $selectedSessionId)

        // EXISTING: Integration status, keyboard hint, dispatch button
        integrationStatusView
        // ...
    }
}

private func dispatch() async {
    guard let sessionId = selectedSessionId else {
        // Show error: "Please select a target session"
        return
    }

    // Get terminal for session
    guard let terminal = TerminalSessionManager.shared.terminal(for: sessionId) else {
        // Show error: "Session not available"
        return
    }

    // Copy images to clipboard (existing)
    let success = await annotationVM.copyToClipboard()

    if success {
        // Dispatch to SELECTED session (not hardcoded embedded terminal)
        EmbeddedTerminalService.shared.dispatchPrompt(
            annotationVM.promptText,
            to: sessionId
        )

        // Clear state
        annotationVM.handleDispatchComplete()
    }
}
```

### Pattern 4: Non-Run Screenshot Model
**What:** Lightweight model for screenshots captured outside of Simulator Run context
**When to use:** Quick captures from region/window capture that aren't part of testing workflow
**Example:**
```swift
// Mirrors Screenshot but without SwiftData @Model
struct QuickCapture: Hashable, Codable, Identifiable {
    let id: UUID
    let filePath: String
    let timestamp: Date
    var label: String?

    var fileURL: URL {
        URL(fileURLWithPath: filePath)
    }

    var image: NSImage? {
        NSImage(contentsOfFile: filePath)
    }

    // Initialize from capture result
    init(fileURL: URL) {
        self.id = UUID()
        self.filePath = fileURL.path
        self.timestamp = Date()
        self.label = nil
    }
}

// Convert to Screenshot-compatible structure for AnnotationViewModel
extension QuickCapture {
    func toScreenshot() -> Screenshot {
        Screenshot(
            id: id,
            filePath: filePath,
            captureIndex: 0,  // N/A for quick captures
            createdAt: timestamp,
            label: label,
            run: nil  // No associated run
        )
    }
}
```

### Anti-Patterns to Avoid
- **Hardcoding session dispatch target:** Always use user-selected session from picker
- **Blocking capture UI during annotation:** Multiple captures must queue (ANNOT-02 requirement)
- **Creating new annotation infrastructure:** Reuse existing AnnotationWindow, AnnotationViewModel, AnnotationCanvasView
- **Manual NSWindow management:** Use SwiftUI's openWindow and value-based WindowGroup instead

## Don't Hand-Roll

Problems that look simple but have existing solutions:

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Window opening after capture | Custom NSWindowController subclass | openWindow environment action | SwiftUI handles lifecycle, state restoration, identity |
| Window identity management | UUID tracking dictionary | Value-based WindowGroup | Automatic deduplication, one window per value |
| Session selection UI | Custom popup/sheet | SwiftUI Picker with .menu style | Native macOS dropdown UX, keyboard navigation |
| Screenshot loading | Custom file watcher | Direct file URL to NSImage | Screenshot already saved to disk by capture service |
| Queue management | New queue system | AnnotationViewModel.sendQueue | Already supports 5 images, proven infrastructure |

**Key insight:** The annotation infrastructure already exists and works for Simulator screenshots. This phase is 90% wiring, not new UI development. The only new components are QuickCapture model and SessionPicker view.

## Common Pitfalls

### Pitfall 1: Opening Window Before File is Written
**What goes wrong:** Window opens with nil image because file hasn't finished writing to disk
**Why it happens:** Async race between screencapture process completion and file system persistence
**How to avoid:** Only call `openWindow` AFTER `CaptureResult.success(URL)` and verify file exists
**Warning signs:** Annotation window shows empty state despite successful capture

### Pitfall 2: Window Identity Conflicts
**What goes wrong:** Multiple captures open in same window instead of separate windows
**Why it happens:** QuickCapture uses non-unique hash (e.g., hashing only timestamp)
**How to avoid:** Hash on `id` (UUID) only, ensuring each capture gets unique window
**Warning signs:** Second capture replaces first capture's content in same window

### Pitfall 3: Forgetting Codable for State Restoration
**What goes wrong:** App crashes on launch when trying to restore windows
**Why it happens:** WindowGroup(for:) requires Codable conformance for state restoration
**How to avoid:** Implement Codable on QuickCapture, handle URL encoding/decoding properly
**Warning signs:** Crash on app relaunch with windows open, "Type does not conform to Codable" error

### Pitfall 4: Dispatch to Wrong Session
**What goes wrong:** Screenshot dispatched to inactive/wrong Claude Code session
**Why it happens:** Using EmbeddedTerminalService.shared without session ID parameter
**How to avoid:** Always pass user-selected sessionId to dispatch method
**Warning signs:** User reports "sent to wrong terminal", prompt appears in unexpected session

### Pitfall 5: Queue Not Clearing After Dispatch
**What goes wrong:** Dispatched screenshots remain in queue, get re-sent on next dispatch
**Why it happens:** Forgetting to call `annotationVM.handleDispatchComplete()` after successful dispatch
**How to avoid:** Follow existing pattern in AnnotationWindow.dispatch() - always clear on success
**Warning signs:** User dispatches once, gets duplicate images on second dispatch

### Pitfall 6: Session Picker Shows Closed Sessions
**What goes wrong:** Picker lists sessions that no longer exist (closed terminals)
**Why it happens:** Not filtering TerminalSessionManager.sessions for active/available
**How to avoid:** Only show sessions with non-nil terminal reference
**Warning signs:** User selects session, dispatch fails with "session not available"

## Code Examples

Verified patterns from official sources:

### Complete Auto-Open Flow
```swift
// Source: Synthesized from HackingWithSwift + Dispatch patterns

// 1. App Scene Definition
@main
struct DispatchApp: App {
    var body: some Scene {
        WindowGroup {
            MainView()
        }

        // Value-based window for QuickCapture annotation
        WindowGroup("Annotate Screenshot", for: QuickCapture.self) { $capture in
            if let capture = capture {
                QuickCaptureAnnotationView(capture: capture)
                    .frame(minWidth: 1000, minHeight: 700)
            }
        }
        .defaultSize(width: 1200, height: 800)
    }
}

// 2. QuickCapture Model
struct QuickCapture: Hashable, Codable, Identifiable {
    let id: UUID
    let filePath: String
    let timestamp: Date

    init(fileURL: URL) {
        self.id = UUID()
        self.filePath = fileURL.path
        self.timestamp = Date()
    }

    var fileURL: URL {
        URL(fileURLWithPath: filePath)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// 3. Capture Trigger with Auto-Open
struct MainView: View {
    @Environment(\.openWindow) private var openWindow

    func triggerRegionCapture() {
        Task {
            let result = await ScreenshotCaptureService.shared.captureRegion()
            await handleCaptureResult(result)
        }
    }

    func triggerWindowCapture() {
        Task {
            let result = await ScreenshotCaptureService.shared.captureWindow()
            await handleCaptureResult(result)
        }
    }

    @MainActor
    private func handleCaptureResult(_ result: CaptureResult) {
        switch result {
        case .success(let url):
            // Verify file exists before opening window
            guard FileManager.default.fileExists(atPath: url.path) else {
                logError("Capture file not found: \(url.path)", category: .capture)
                return
            }

            // Create QuickCapture and open annotation window
            let capture = QuickCapture(fileURL: url)
            openWindow(value: capture)
            logInfo("Opened annotation window for capture: \(url.lastPathComponent)", category: .capture)

        case .cancelled:
            logInfo("Capture cancelled by user", category: .capture)

        case .error(let error):
            logError("Capture failed: \(error)", category: .capture)
        }
    }
}
```

### Session Picker with Available Sessions Only
```swift
// Source: SwiftUI Picker docs + TerminalSessionManager pattern

struct SessionPickerView: View {
    @ObservedObject var sessionManager = TerminalSessionManager.shared
    @Binding var selectedSessionId: UUID?

    // Filter to only active sessions with terminals
    private var availableSessions: [TerminalSession] {
        sessionManager.sessions.filter { session in
            sessionManager.terminal(for: session.id) != nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Target Session", systemImage: "terminal")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("", selection: $selectedSessionId) {
                Text("Select Claude Code session...")
                    .tag(nil as UUID?)

                if availableSessions.isEmpty {
                    Text("No sessions available")
                        .foregroundStyle(.secondary)
                        .tag(nil as UUID?)
                } else {
                    ForEach(availableSessions) { session in
                        sessionLabel(for: session)
                            .tag(session.id as UUID?)
                    }
                }
            }
            .pickerStyle(.menu)
            .disabled(availableSessions.isEmpty)

            // Status indicator
            if let selectedId = selectedSessionId,
               let session = sessionManager.sessions.first(where: { $0.id == selectedId }) {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Ready: \(session.name)")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func sessionLabel(for session: TerminalSession) -> some View {
        HStack {
            Text(session.name)
            Spacer()

            // Visual indicator for Claude sessions
            if session.claudeSessionId != nil {
                Image(systemName: "sparkles")
                    .foregroundStyle(.blue)
                    .help("Claude Code session")
            }

            // Active session indicator
            if session.id == sessionManager.activeSessionId {
                Image(systemName: "circle.fill")
                    .foregroundStyle(.green)
                    .font(.system(size: 6))
                    .help("Active session")
            }
        }
    }
}
```

### QuickCapture Annotation View (Reusing Existing Components)
```swift
// Source: Existing AnnotationWindow pattern, adapted for QuickCapture

struct QuickCaptureAnnotationView: View {
    let capture: QuickCapture

    @StateObject private var annotationVM = AnnotationViewModel()
    @State private var selectedSessionId: UUID?
    @State private var showingError = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            // REUSE: Existing annotation canvas and toolbar
            HSplitView {
                // Left: Canvas
                VStack(spacing: 0) {
                    AnnotationCanvasView()
                        .environmentObject(annotationVM)

                    Divider()

                    AnnotationToolbar()
                        .environmentObject(annotationVM)
                }
                .frame(minWidth: 600)

                // Right: Queue + Prompt + Session Picker
                VStack(spacing: 0) {
                    // Queue (existing)
                    SendQueueView()
                        .environmentObject(annotationVM)
                        .frame(height: 120)

                    Divider()

                    // Prompt (existing)
                    promptSection

                    Spacer()

                    // NEW: Session picker
                    SessionPickerView(selectedSessionId: $selectedSessionId)
                        .padding()

                    Divider()

                    // Dispatch button
                    dispatchButton
                        .padding()
                }
                .frame(minWidth: 280, maxWidth: 350)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            }
        }
        .onAppear {
            loadCapture()
        }
        .alert("Dispatch Failed", isPresented: $showingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
    }

    private var promptSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Prompt")
                .font(.headline)

            TextEditor(text: $annotationVM.promptText)
                .font(.body)
                .frame(minHeight: 100)
                .scrollContentBackground(.hidden)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding()
    }

    private var dispatchButton: some View {
        Button {
            Task { await dispatch() }
        } label: {
            HStack {
                Image(systemName: "paperplane.fill")
                Text("Dispatch to Session")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.borderedProminent)
        .disabled(!canDispatch)
        .keyboardShortcut(.return, modifiers: .command)
    }

    private var canDispatch: Bool {
        annotationVM.hasQueuedImages &&
        !annotationVM.promptText.isEmpty &&
        selectedSessionId != nil
    }

    private func loadCapture() {
        // Convert QuickCapture to Screenshot for AnnotationViewModel
        let screenshot = Screenshot(
            id: capture.id,
            filePath: capture.filePath,
            captureIndex: 0,
            createdAt: capture.timestamp,
            run: nil
        )

        annotationVM.loadScreenshot(screenshot)
        logDebug("Loaded QuickCapture into annotation view", category: .capture)
    }

    private func dispatch() async {
        guard let sessionId = selectedSessionId else {
            errorMessage = "Please select a target Claude Code session"
            showingError = true
            return
        }

        // Copy images to clipboard
        let success = await annotationVM.copyToClipboard()

        guard success else {
            errorMessage = "Failed to copy images to clipboard"
            showingError = true
            return
        }

        // Dispatch to selected session's terminal
        guard let coordinator = TerminalSessionManager.shared.coordinator(for: sessionId) else {
            errorMessage = "Session not available. Please select an active session."
            showingError = true
            return
        }

        coordinator.sendText(annotationVM.promptText + "\n")

        // Clear state
        annotationVM.handleDispatchComplete()

        logInfo("Dispatched \(annotationVM.queueCount) images to session \(sessionId)", category: .capture)
    }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| NSWindowController | openWindow environment | macOS 13 (2022) | Declarative window management, automatic state restoration |
| Notification-based window opening | Environment action | macOS 13 (2022) | Type-safe, SwiftUI-native, better async/await integration |
| Manual window identity tracking | Value-based WindowGroup | macOS 13 (2022) | Automatic deduplication, one window per unique value |
| Hard-coded dispatch target | User session selection | N/A (project pattern) | Multi-session workflow support |

**Deprecated/outdated:**
- **NSWindowController for SwiftUI windows:** Use WindowGroup + openWindow instead
- **NotificationCenter for window events:** Use SwiftUI environment actions
- **Single shared annotation window:** Use value-based WindowGroup for parallel workflows

## Open Questions

Things that couldn't be fully resolved:

1. **QuickCapture persistence**
   - What we know: Current annotation window doesn't persist non-Run screenshots
   - What's unclear: Should QuickCaptures survive app relaunch, or be ephemeral?
   - Recommendation: Start ephemeral (no persistence). If users want to save, they add to Run manually. Keep QuickCapture simple for Phase 25.

2. **Multiple windows vs. single queue**
   - What we know: Value-based WindowGroup creates one window per QuickCapture
   - What's unclear: Should multiple capture windows share a queue, or independent queues?
   - Recommendation: Independent queues (each window = separate annotation session). Matches mental model: "I'm annotating this set of captures together."

3. **Session picker default selection**
   - What we know: User can select from available sessions
   - What's unclear: Should we auto-select active session, or require explicit choice?
   - Recommendation: Auto-select activeSessionId if available, but allow user to change. Reduces friction for single-session users.

## Sources

### Primary (HIGH confidence)
- [How to open a new window - SwiftUI by Example | HackingWithSwift](https://www.hackingwithswift.com/quick-start/swiftui/how-to-open-a-new-window)
- [Programmatically open a new window in SwiftUI on macOS | NilCoalescing](https://nilcoalescing.com/blog/ProgrammaticallyOpenANewWindowInSwiftUIOnMacOS/)
- [Window Management with SwiftUI 4 | fline.dev](https://www.fline.dev/window-management-on-macos-with-swiftui-4/)
- [Understanding scenes for your macOS app | Create with Swift](https://www.createwithswift.com/understanding-scenes-for-your-macos-app/)
- [Picker | Apple Developer Documentation](https://developer.apple.com/documentation/SwiftUI/Picker)

### Secondary (MEDIUM confidence)
- [SwiftUI Open and Save Panels | Swift Dev Journal](https://www.swiftdevjournal.com/swiftui-open-and-save-panels/)
- [Save And Open Panels In SwiftUI-Based macOS Apps | SerialCoder.dev](https://serialcoder.dev/text-tutorials/macos-tutorials/save-and-open-panels-in-swiftui-based-macos-apps/)
- [GitHub - sadopc/ScreenCapture](https://github.com/sadopc/ScreenCapture) - Reference macOS screenshot annotation app with SwiftUI

### Tertiary (LOW confidence)
- Apple Developer Forums - discussions on WindowGroup patterns
- Community examples - window lifecycle management

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - SwiftUI environment actions and WindowGroup are official Apple APIs
- Architecture: HIGH - Existing annotation infrastructure verified in codebase, window patterns from official docs
- Pitfalls: MEDIUM - Based on SwiftUI window management experience and codebase patterns, not exhaustive testing
- Session selection: HIGH - TerminalSessionManager pattern already established in codebase

**Research date:** 2026-02-09
**Valid until:** 2026-03-09 (30 days - stable API, established patterns)
**SwiftUI openWindow introduced:** macOS 13.0 (September 2022)
**Value-based WindowGroup introduced:** macOS 13.0 (September 2022)

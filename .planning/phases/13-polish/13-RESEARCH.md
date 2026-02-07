# Phase 13: Polish - Research

**Researched:** 2026-02-07
**Domain:** SwiftUI UI/UX refinement for screenshot feature
**Confidence:** HIGH

## Summary

Phase 13 adds UI polish to the screenshot feature: Settings UI for configuration, tooltip hints for annotation tools, user-visible error messages, and integration status indicators. Research reveals the app follows established SwiftUI patterns: Form with `.formStyle(.grouped)` for settings, `.help()` modifier for tooltips, `.alert()` for error dialogs, and Label-based status badges with SF Symbols.

The existing codebase provides clear patterns: `SettingsView.swift` uses TabView with Form sections, `AppSettings.swift` model already has `screenshotDirectory` and `maxRunsPerProject` properties, `AnnotationToolbar.swift` already uses `.help()` on some buttons, and `HookSettingsView` demonstrates status badges with colored Labels. The annotation tools use SF Symbol icons with keyboard shortcuts displayed in UI.

**Primary recommendation:** Follow existing app patterns exactly - add new "Screenshots" tab to SettingsView with Form sections, add `.help()` to all annotation tool buttons with descriptive text, wrap dispatch errors in alert state, and add status indicator to AnnotationWindow dispatch section using Label with system colors (green/orange/red).

## Standard Stack

The established libraries/tools for this domain:

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| SwiftUI | macOS 14+ | UI framework | Native to app, all views use it |
| SF Symbols | System | Icons | Native icon system, used throughout app |
| SwiftData | Latest | Settings persistence | App uses for AppSettings model |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| Form | SwiftUI | Settings layout | Standard for settings/preferences UI |
| .help() | SwiftUI | Tooltips | Native tooltip modifier for macOS |
| .alert() | SwiftUI | Error dialogs | Standard error presentation |
| Label | SwiftUI | Status indicators | Icon + text combinations |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Form | Custom VStack | Form provides platform-native styling |
| .help() | Custom tooltip view | Native modifier is simpler, system-styled |
| .alert() | Custom sheet | Alert is standard for simple error messages |
| Label | HStack with Image + Text | Label is semantic, more accessible |

**Installation:**
```swift
// No installation needed - all SwiftUI native components
// Already imported in existing views
```

## Architecture Patterns

### Recommended Settings Structure

**Standard settings tab pattern (from SettingsView.swift):**
```swift
// In SettingsView.swift, add new tab:
struct SettingsView: View {
    var body: some View {
        TabView(selection: $selectedTab) {
            // ... existing tabs ...

            ScreenshotSettingsView()
                .tabItem {
                    Label("Screenshots", systemImage: "camera.viewfinder")
                }
                .tag(SettingsTab.screenshots)
        }
        .frame(width: 550, height: 450)
    }
}

// Add new case to enum:
enum SettingsTab: String {
    // ... existing cases ...
    case screenshots
}
```

**Settings section pattern (following GeneralSettingsView):**
```swift
struct ScreenshotSettingsView: View {
    @ObservedObject private var settingsManager = SettingsManager.shared

    var body: some View {
        Form {
            Section("Screenshot Storage") {
                HStack {
                    Text("Directory:")
                    Spacer()
                    Text(displayPath)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button("Choose...") {
                        selectDirectory()
                    }
                }

                Text("Screenshots are saved here. Default: ~/Library/Application Support/Dispatch/Screenshots")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Run Management") {
                Picker("Max runs per project", selection: maxRunsBinding) {
                    Text("5 runs").tag(5)
                    Text("10 runs").tag(10)
                    Text("20 runs").tag(20)
                    Text("50 runs").tag(50)
                }

                Text("Older runs are automatically deleted when this limit is reached.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
```

### Pattern 1: Tooltip Hints with .help()

**What:** Native macOS tooltip that appears on hover
**When to use:** Any button, tool, or control that benefits from explanation
**Example (from AnnotationToolbar.swift, line 168):**
```swift
// Already implemented pattern:
Button(action: action) {
    VStack(spacing: 2) {
        Image(systemName: tool.iconName)
        Text(String(tool.shortcutKey).uppercased())
    }
}
.help("\(tool.displayName) (\(String(tool.shortcutKey).uppercased()))")

// Add to color buttons:
Button(action: action) {
    Circle().fill(color.color)
}
.help("\(color.rawValue.capitalized) (\(color.shortcutNumber))")
```

**Best practices:**
- Keep help text concise (one sentence)
- Include keyboard shortcut if applicable
- Use sentence case for readability
- Add to all interactive elements that aren't obviously labeled

### Pattern 2: User-Visible Error Messages

**What:** Alert dialog for dispatch failures
**When to use:** When operation fails and user needs to know
**Example (from AnnotationWindow.swift dispatch section):**
```swift
struct AnnotationWindowContent: View {
    @State private var dispatchError: String?
    @State private var showingDispatchError = false

    var body: some View {
        VStack {
            // ... existing content ...
            dispatchSection
        }
        .alert("Dispatch Failed", isPresented: $showingDispatchError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(dispatchError ?? "Unknown error")
        }
    }

    private func dispatch() async {
        guard canDispatch else { return }

        let success = await annotationVM.copyToClipboard()

        if success {
            do {
                try await TerminalService.shared.pasteFromClipboard()
                try await Task.sleep(nanoseconds: 200_000_000)
                try await TerminalService.shared.sendTextToActiveWindow(prompt)
                annotationVM.handleDispatchComplete()
                logInfo("Dispatched successfully", category: .simulator)
            } catch {
                // Show user-visible error instead of just logging
                dispatchError = error.localizedDescription
                showingDispatchError = true
                error.log(category: .simulator, context: "Failed to dispatch images")
            }
        } else {
            // Clipboard copy failed
            dispatchError = "Failed to copy images to clipboard"
            showingDispatchError = true
        }
    }
}
```

### Pattern 3: Integration Status Indicator

**What:** Visual indicator showing library and hook status
**When to use:** In UI sections that depend on external integration
**Example (following HookSettingsView statusBadge, line 398):**
```swift
// Add to AnnotationWindow dispatch section:
private var dispatchSection: some View {
    VStack(spacing: 12) {
        // Add status indicator at top
        integrationStatusView

        // Existing keyboard shortcut hint
        HStack {
            Text("Press")
            Text("⌘⏎")
            Text("to dispatch")
        }

        // Existing dispatch button
        Button { /* ... */ }
    }
}

@ViewBuilder
private var integrationStatusView: some View {
    HStack(spacing: 4) {
        Image(systemName: statusIcon)
            .font(.caption2)
            .foregroundStyle(statusColor)

        Text(statusText)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

private var statusIcon: String {
    if libraryInstalled && hookActive {
        return "checkmark.circle.fill"
    } else if libraryInstalled {
        return "exclamationmark.circle"
    } else {
        return "xmark.circle"
    }
}

private var statusColor: Color {
    if libraryInstalled && hookActive {
        return .green
    } else if libraryInstalled {
        return .orange
    } else {
        return .red
    }
}

private var statusText: String {
    if libraryInstalled && hookActive {
        return "Integration ready"
    } else if libraryInstalled {
        return "Library installed, hook inactive"
    } else {
        return "Library not installed"
    }
}
```

**Status check logic:**
- Check if `~/.claude/lib/dispatch.sh` exists and is executable
- Check if hook installed via `HookInstallerManager.shared.status`
- Update status on window appear and when dispatch completes

### Anti-Patterns to Avoid

- **Custom tooltip views:** Don't build custom popover tooltips when `.help()` works
- **Toast notifications:** Don't use transient toast messages for errors - use alerts
- **Inline error text:** Don't show error text directly in UI - use alert dialogs
- **Text-only status:** Don't rely on text alone - use colored icons for visual scanning

## Don't Hand-Roll

Problems that look simple but have existing solutions:

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| macOS tooltips | Custom popover view | `.help()` modifier | Native, automatic positioning, system-styled |
| Error dialogs | Custom modal sheet | `.alert()` modifier | Standard pattern, accessibility built-in |
| Settings layout | Custom VStack/HStack | Form with sections | Platform-native styling, automatic adaptation |
| Directory picker | Custom file browser | NSOpenPanel via Button | System file picker, sandboxing-aware |
| Status badges | Custom view builder | Label with SF Symbols | Semantic markup, VoiceOver friendly |

**Key insight:** SwiftUI provides high-quality native components for all common UI patterns. Custom implementations add complexity without benefit and miss platform updates.

## Common Pitfalls

### Pitfall 1: Form Padding Issues

**What goes wrong:** Extra unwanted padding at top of Form in settings windows
**Why it happens:** Default Form styling includes top padding on macOS
**How to avoid:** Use `.formStyle(.grouped)` instead of default, add `.padding()` to entire Form
**Warning signs:** Large empty space above first section in settings view

**Solution:**
```swift
Form {
    // sections
}
.formStyle(.grouped)  // Required
.padding()            // Apply to entire form, not individual sections
```

### Pitfall 2: Help Text on Non-Interactive Views

**What goes wrong:** `.help()` modifier added to Text or Image that isn't in a Button
**Why it happens:** Assuming .help() works on any view
**How to avoid:** Only apply `.help()` to interactive views (Button, Toggle, Picker, etc.)
**Warning signs:** Tooltip doesn't appear on hover

**Solution:**
```swift
// Wrong:
Image(systemName: "star")
    .help("This is a star")  // Won't work - Image isn't interactive

// Right:
Button(action: {}) {
    Image(systemName: "star")
}
.help("This is a star")  // Works - Button is interactive
```

### Pitfall 3: Alert State Management

**What goes wrong:** Alert shown multiple times or doesn't dismiss properly
**Why it happens:** Incorrect binding between error state and alert presentation
**How to avoid:** Use separate `@State` for error message and boolean flag
**Warning signs:** Alert appears twice, or stays visible after dismissing

**Solution:**
```swift
// Correct pattern:
@State private var errorMessage: String?
@State private var showingError = false

// Set both when error occurs:
errorMessage = error.localizedDescription
showingError = true

// Alert binding:
.alert("Error", isPresented: $showingError) {
    Button("OK", role: .cancel) {}
} message: {
    Text(errorMessage ?? "Unknown error")
}
```

### Pitfall 4: Status Indicator Not Updating

**What goes wrong:** Integration status shows stale information
**Why it happens:** Not refreshing status when window appears or after operations
**How to avoid:** Check status in `.onAppear` and after relevant operations
**Warning signs:** Status says "not installed" when library exists

**Solution:**
```swift
.onAppear {
    refreshIntegrationStatus()
}

private func refreshIntegrationStatus() {
    Task {
        // Check library file exists
        let libraryPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/lib/dispatch.sh")
        libraryInstalled = FileManager.default.fileExists(atPath: libraryPath.path)

        // Check hook status
        hookActive = await HookInstallerManager.shared.status.isInstalled
    }
}
```

## Code Examples

Verified patterns from official sources and existing app code:

### Settings Tab Implementation

```swift
// Source: Existing SettingsView.swift pattern
struct ScreenshotSettingsView: View {
    @ObservedObject private var settingsManager = SettingsManager.shared
    @State private var selectedDirectory: URL?

    var body: some View {
        Form {
            Section("Screenshot Storage") {
                HStack {
                    Text("Directory:")
                    Spacer()
                    Text(displayPath)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button("Choose...") {
                        selectDirectory()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                if settingsManager.settings?.screenshotDirectory != nil {
                    Button("Reset to Default") {
                        settingsManager.settings?.screenshotDirectory = nil
                        settingsManager.save()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Text("Default location: ~/Library/Application Support/Dispatch/Screenshots")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Run Management") {
                Picker("Max runs per project", selection: maxRunsBinding) {
                    Text("5 runs").tag(5)
                    Text("10 runs").tag(10)
                    Text("20 runs").tag(20)
                    Text("50 runs").tag(50)
                    Text("Unlimited").tag(0)
                }

                Text("Older runs are automatically deleted when limit is reached. Set to Unlimited to keep all runs.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var displayPath: String {
        if let customPath = settingsManager.settings?.screenshotDirectory {
            return customPath
        }
        return "~/Library/Application Support/Dispatch/Screenshots"
    }

    private var maxRunsBinding: Binding<Int> {
        Binding(
            get: { settingsManager.settings?.maxRunsPerProject ?? 10 },
            set: {
                settingsManager.settings?.maxRunsPerProject = $0
                settingsManager.save()
            }
        )
    }

    private func selectDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Select"

        if panel.runModal() == .OK, let url = panel.url {
            settingsManager.settings?.screenshotDirectory = url.path
            settingsManager.save()
        }
    }
}
```

### Annotation Tool Tooltips

```swift
// Source: Existing AnnotationToolbar.swift pattern, enhanced
struct ToolButton: View {
    let tool: AnnotationTool
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: tool.iconName)
                Text(String(tool.shortcutKey).uppercased())
            }
        }
        .help(tooltipText)  // Enhanced with detailed text
    }

    private var tooltipText: String {
        switch tool {
        case .crop:
            return "Crop image to selected region (C)"
        case .freehand:
            return "Draw freehand annotations (D)"
        case .arrow:
            return "Draw arrow to point at specific area (A)"
        case .rectangle:
            return "Draw rectangle to highlight region (R)"
        case .text:
            return "Add text annotation (T)"
        }
    }
}

struct ColorButton: View {
    let color: AnnotationColor
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(color.color)
                if isSelected {
                    Circle().strokeBorder(Color.primary, lineWidth: 2)
                }
            }
        }
        .help("\(color.rawValue.capitalized) color (\(color.shortcutNumber))")
    }
}
```

### Dispatch Error Handling

```swift
// Source: Existing alert pattern from ClaudeFileEditor.swift
struct AnnotationWindowContent: View {
    @State private var dispatchError: String?
    @State private var showingDispatchError = false

    var body: some View {
        VStack {
            // ... content ...
        }
        .alert("Dispatch Failed", isPresented: $showingDispatchError) {
            Button("OK", role: .cancel) {
                dispatchError = nil
            }
            Button("Open Settings") {
                openTerminalSettings()
            }
        } message: {
            if let error = dispatchError {
                Text(error)
            } else {
                Text("Failed to send screenshots to Terminal. Check that Terminal.app automation is enabled in System Settings.")
            }
        }
    }

    private func dispatch() async {
        guard canDispatch else { return }

        let success = await annotationVM.copyToClipboard()

        if success {
            do {
                try await TerminalService.shared.pasteFromClipboard()
                try await Task.sleep(nanoseconds: 200_000_000)
                try await TerminalService.shared.sendTextToActiveWindow(annotationVM.promptText)
                annotationVM.handleDispatchComplete()
                logInfo("Dispatched \(annotationVM.queueCount) images", category: .simulator)
            } catch TerminalServiceError.permissionDenied {
                dispatchError = "Terminal automation permission denied. Grant access in System Settings > Privacy & Security > Automation."
                showingDispatchError = true
            } catch TerminalServiceError.accessibilityPermissionDenied {
                dispatchError = "Accessibility permission denied. Grant access in System Settings > Privacy & Security > Accessibility."
                showingDispatchError = true
            } catch {
                dispatchError = "Failed to send to Terminal: \(error.localizedDescription)"
                showingDispatchError = true
            }
        } else {
            dispatchError = "Failed to copy images to clipboard. Check available memory."
            showingDispatchError = true
        }
    }

    private func openTerminalSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }
}
```

### Integration Status Indicator

```swift
// Source: HookSettingsView statusBadge pattern
struct AnnotationWindowContent: View {
    @State private var libraryInstalled = false
    @State private var hookInstalled = false

    var body: some View {
        VStack(spacing: 0) {
            // ... content ...

            // In dispatch section:
            VStack(spacing: 12) {
                integrationStatusView

                // Keyboard shortcut hint
                HStack { /* ... */ }

                // Dispatch button
                Button { /* ... */ }
            }
        }
        .onAppear {
            checkIntegrationStatus()
        }
    }

    @ViewBuilder
    private var integrationStatusView: some View {
        HStack(spacing: 4) {
            Image(systemName: statusIcon)
                .font(.caption2)
                .foregroundStyle(statusColor)

            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var statusIcon: String {
        switch (libraryInstalled, hookInstalled) {
        case (true, true): return "checkmark.circle.fill"
        case (true, false): return "exclamationmark.circle"
        case (false, _): return "xmark.circle"
        }
    }

    private var statusColor: Color {
        switch (libraryInstalled, hookInstalled) {
        case (true, true): return .green
        case (true, false): return .orange
        case (false, _): return .red
        }
    }

    private var statusText: String {
        switch (libraryInstalled, hookInstalled) {
        case (true, true): return "Integration ready"
        case (true, false): return "Library ready, hook inactive"
        case (false, _): return "Library not installed"
        }
    }

    private func checkIntegrationStatus() {
        Task {
            // Check library
            let libraryPath = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".claude/lib/dispatch.sh")

            let attributes = try? FileManager.default.attributesOfItem(atPath: libraryPath.path)
            let permissions = attributes?[.posixPermissions] as? Int ?? 0
            let isExecutable = (permissions & 0o111) != 0

            libraryInstalled = FileManager.default.fileExists(atPath: libraryPath.path) && isExecutable

            // Check hook
            hookInstalled = await HookInstallerManager.shared.status.isInstalled
        }
    }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Custom tooltip views | `.help()` modifier | SwiftUI 1.0 (2019) | Simplified, native styling |
| Separate settings window | TabView in Settings | SwiftUI 2.0 (2020) | Standard macOS pattern |
| Toast notifications | `.alert()` for errors | SwiftUI convention | More reliable, accessible |
| Manual SF Symbol + Text | Label view | SwiftUI 2.0 (2020) | Semantic, VoiceOver support |

**Deprecated/outdated:**
- Custom popover-based tooltips: Use `.help()` modifier instead
- Notification banners for errors: Use `.alert()` for critical failures
- `.columns` form style for settings: Use `.grouped` for preference panes

## Open Questions

None - all requirements have clear implementation patterns in existing codebase.

## Sources

### Primary (HIGH confidence)
- Existing app codebase:
  - `SettingsView.swift` - Settings tab pattern, Form usage
  - `AppSettings.swift` - Already has `screenshotDirectory` and `maxRunsPerProject` properties
  - `AnnotationToolbar.swift` - Already uses `.help()` on some buttons (lines 80, 90, 102, 116, 129, 137, 168)
  - `HookSettingsView.swift` - Status badge pattern with colored Labels (lines 398-413)
  - `ClaudeFileEditor.swift` - Alert pattern for errors (lines 74-89)
- Apple SwiftUI documentation - Form, .help(), .alert(), Label modifiers

### Secondary (MEDIUM confidence)
- [Adding Tooltips to SwiftUI Views on macOS](https://blog.rampatra.com/adding-tooltips-to-swiftui-views-on-macos)
- [How to use TipKit to create tool tips in SwiftUI](https://tanaschita.com/20240304-tipkit-feature-hints/)
- [Customizing SwiftUI Settings Window on macOS](https://medium.com/@clyapp/customizing-swiftui-settings-window-on-macos-4c47d0060ee4)
- [Mastering Forms in SwiftUI: Creating and Styling](https://www.createwithswift.com/mastering-forms-in-swiftui-creating-and-styling/)

### Tertiary (LOW confidence)
None - all findings verified with existing code patterns.

## Metadata

**Confidence breakdown:**
- Settings UI: HIGH - Exact pattern exists in app, properties already in model
- Tooltips: HIGH - `.help()` already used in app, just needs expansion
- Error handling: HIGH - Alert pattern exists in app, just needs application to dispatch
- Status indicators: HIGH - Exact status badge pattern exists in HookSettingsView

**Research date:** 2026-02-07
**Valid until:** 30 days (stable SwiftUI APIs, minor updates expected)

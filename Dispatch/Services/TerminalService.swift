//
//  TerminalService.swift
//  Dispatch
//
//  Service for Terminal.app integration via AppleScript
//

import AppKit
import Foundation

// MARK: - Terminal Window Info

/// Represents a Terminal.app window
struct TerminalWindow: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let tabTitle: String?
    let isActive: Bool

    var displayName: String {
        if let tabTitle = tabTitle, !tabTitle.isEmpty && tabTitle != name {
            return "\(name) — \(tabTitle)"
        }
        return name
    }
}

// MARK: - Terminal Service Errors

enum TerminalServiceError: Error, LocalizedError {
    case terminalNotRunning
    case noWindowsOpen
    case windowNotFound(id: String)
    case scriptExecutionFailed(String)
    case permissionDenied
    case accessibilityPermissionDenied
    case invalidPromptContent
    case timeout

    var errorDescription: String? {
        switch self {
        case .terminalNotRunning:
            return "Terminal.app is not running"
        case .noWindowsOpen:
            return "No Terminal windows are open"
        case let .windowNotFound(id):
            return "Terminal window with ID '\(id)' not found"
        case let .scriptExecutionFailed(message):
            return "AppleScript execution failed: \(message)"
        case .permissionDenied:
            return "Automation permission denied for Terminal.app"
        case .accessibilityPermissionDenied:
            return "Accessibility permission denied - cannot send keystrokes"
        case .invalidPromptContent:
            return "Prompt content is empty or invalid"
        case .timeout:
            return "Terminal operation timed out"
        }
    }
}

// MARK: - Terminal Service

/// Actor-based service for interacting with Terminal.app
actor TerminalService {
    static let shared = TerminalService()

    // MARK: - Private Properties

    private var cachedWindows: [TerminalWindow] = []
    private var lastWindowFetchTime: Date?
    private let windowCacheDuration: TimeInterval = 2.0 // Cache windows for 2 seconds

    private init() {}

    // MARK: - Public Methods

    /// Checks if Terminal.app is running
    func isTerminalRunning() -> Bool {
        let running = NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == "com.apple.Terminal"
        }
        logDebug("Terminal running: \(running)", category: .terminal)
        return running
    }

    /// Checks if we have automation permission for Terminal.app
    /// Returns true if permission is granted, false if denied or unknown
    func checkAutomationPermission() async -> Bool {
        logDebug("Checking automation permission for Terminal.app", category: .terminal)

        // Try a simple, harmless AppleScript to test permission
        let testScript = """
        tell application "Terminal"
            return name
        end tell
        """

        do {
            _ = try await executeAppleScript(testScript)
            logInfo("Automation permission for Terminal.app: GRANTED", category: .terminal)
            return true
        } catch TerminalServiceError.permissionDenied {
            logWarning("Automation permission for Terminal.app: DENIED", category: .terminal)
            return false
        } catch {
            logWarning("Automation permission check failed: \(error)", category: .terminal)
            return false
        }
    }

    /// Triggers the automation permission prompt by attempting to use Terminal
    /// This will cause macOS to show the permission dialog if not already granted/denied
    func requestAutomationPermission() async {
        logInfo("Requesting automation permission for Terminal.app", category: .terminal)

        let script = """
        tell application "Terminal"
            return name
        end tell
        """

        // This will trigger the permission prompt
        _ = try? await executeAppleScript(script)
    }

    /// Opens System Preferences to the Automation privacy settings
    func openAutomationSettings() {
        logInfo("Opening System Preferences > Privacy > Automation", category: .terminal)

        // Open Privacy & Security > Automation
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Opens System Preferences to the Accessibility privacy settings
    func openAccessibilitySettings() {
        logInfo("Opening System Preferences > Privacy > Accessibility", category: .terminal)

        // Open Privacy & Security > Accessibility
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Launches Terminal.app if not running
    func launchTerminal() async throws {
        guard !isTerminalRunning() else {
            logDebug("Terminal already running", category: .terminal)
            return
        }

        logInfo("Launching Terminal.app", category: .terminal)

        let success = NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"))

        guard success else {
            logError("Failed to launch Terminal.app", category: .terminal)
            throw TerminalServiceError.scriptExecutionFailed("Could not launch Terminal.app")
        }

        // Wait for Terminal to start
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

        if !isTerminalRunning() {
            throw TerminalServiceError.terminalNotRunning
        }

        logInfo("Terminal.app launched successfully", category: .terminal)
    }

    /// Gets all open Terminal windows
    func getWindows(forceRefresh: Bool = false) async throws -> [TerminalWindow] {
        // Check cache
        if !forceRefresh,
           let lastFetch = lastWindowFetchTime,
           Date().timeIntervalSince(lastFetch) < windowCacheDuration,
           !cachedWindows.isEmpty {
            logDebug("Returning cached windows (\(cachedWindows.count))", category: .terminal)
            return cachedWindows
        }

        guard isTerminalRunning() else {
            throw TerminalServiceError.terminalNotRunning
        }

        let script = """
        tell application "Terminal"
            set windowList to {}
            set frontWindowId to ""
            try
                set frontWindowId to id of front window as string
            end try
            repeat with w in windows
                set windowId to id of w as string
                set windowName to name of w
                set isActive to (windowId = frontWindowId)
                set tabTitle to ""
                try
                    set tabTitle to name of selected tab of w
                on error
                    set tabTitle to ""
                end try
                set end of windowList to windowId & "|||" & windowName & "|||" & tabTitle & "|||" & (isActive as string)
            end repeat
            -- Convert list to text string (NSAppleScript doesn't handle lists well)
            set AppleScript's text item delimiters to ";;;"
            set windowText to windowList as text
            set AppleScript's text item delimiters to ""
            return windowText
        end tell
        """

        let result = try await executeAppleScript(script)
        var windows: [TerminalWindow] = []

        // Parse result - list items separated by ;;;
        let items = result.components(separatedBy: ";;;")

        for item in items {
            let parts = item.components(separatedBy: "|||")
            guard parts.count >= 4 else { continue }

            let window = TerminalWindow(
                id: parts[0].trimmingCharacters(in: .whitespaces),
                name: parts[1].trimmingCharacters(in: .whitespaces),
                tabTitle: parts[2].trimmingCharacters(in: .whitespaces),
                isActive: parts[3].lowercased().contains("true")
            )
            windows.append(window)
        }

        cachedWindows = windows
        lastWindowFetchTime = Date()
        return windows
    }

    /// Gets the active (frontmost) Terminal window
    func getActiveWindow() async throws -> TerminalWindow? {
        guard isTerminalRunning() else {
            throw TerminalServiceError.terminalNotRunning
        }

        let script = """
        tell application "Terminal"
            if (count of windows) = 0 then
                return ""
            end if
            set w to front window
            set windowId to id of w as string
            set windowName to name of w
            set tabTitle to ""
            try
                set tabTitle to name of selected tab of w
            end try
            return windowId & "|||" & windowName & "|||" & tabTitle
        end tell
        """

        let result = try await executeAppleScript(script)

        guard !result.isEmpty else {
            logDebug("No active Terminal window found", category: .terminal)
            return nil
        }

        let parts = result.components(separatedBy: "|||")
        guard parts.count >= 3 else {
            logWarning("Unexpected active window result format: \(result)", category: .terminal)
            return nil
        }

        let window = TerminalWindow(
            id: parts[0].trimmingCharacters(in: .whitespaces),
            name: parts[1].trimmingCharacters(in: .whitespaces),
            tabTitle: parts[2].trimmingCharacters(in: .whitespaces),
            isActive: true
        )

        logDebug("Active window: \(window.displayName) (ID: \(window.id))", category: .terminal)
        return window
    }

    /// Sends a prompt to a specific Terminal window or the active window
    func sendPrompt(
        _ content: String,
        toWindowId windowId: String? = nil,
        activateTerminal: Bool = true,
        delay: TimeInterval = 0.1
    ) async throws {
        guard !content.isEmpty else {
            throw TerminalServiceError.invalidPromptContent
        }

        guard isTerminalRunning() else {
            throw TerminalServiceError.terminalNotRunning
        }

        let perf = PerformanceLogger("sendPrompt", category: .terminal)
        defer { perf.end() }

        // Escape the content for AppleScript
        let escapedContent = escapeForAppleScript(content)

        logDebug("Sending prompt (\(content.count) chars) to window: \(windowId ?? "active")", category: .terminal)

        var script: String

        if let windowId = windowId {
            // Send to specific window
            script = """
            tell application "Terminal"
                \(activateTerminal ? "activate" : "")
                try
                    set targetWindow to window id \(windowId)
                    do script "\(escapedContent)" in targetWindow
                on error errMsg
                    error "Window not found: " & errMsg
                end try
            end tell
            """
        } else {
            // Send to frontmost window
            script = """
            tell application "Terminal"
                \(activateTerminal ? "activate" : "")
                if (count of windows) = 0 then
                    error "No Terminal windows open"
                end if
                do script "\(escapedContent)" in front window
            end tell
            """
        }

        // Add delay if specified
        if delay > 0 {
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }

        do {
            _ = try await executeAppleScript(script)
            logInfo("Prompt sent successfully", category: .terminal)
        } catch {
            logError("Failed to send prompt: \(error)", category: .terminal)
            throw error
        }
    }

    /// Gets the content of a Terminal window (for completion detection fallback)
    func getWindowContent(windowId: String? = nil, lastNCharacters: Int = 500) async throws -> String {
        guard isTerminalRunning() else {
            throw TerminalServiceError.terminalNotRunning
        }

        let windowSelector = windowId != nil ? "window id \(windowId!)" : "front window"

        let script = """
        tell application "Terminal"
            if (count of windows) = 0 then
                return ""
            end if
            set windowContent to contents of \(windowSelector)
            if length of windowContent > \(lastNCharacters) then
                return text ((length of windowContent) - \(lastNCharacters)) thru -1 of windowContent
            else
                return windowContent
            end if
        end tell
        """

        let result = try await executeAppleScript(script)
        logDebug("Got window content (\(result.count) chars)", category: .terminal)
        return result
    }

    /// Opens a new Terminal window
    func openNewWindow() async throws -> TerminalWindow {
        logInfo("Opening new Terminal window", category: .terminal)

        let script = """
        tell application "Terminal"
            activate
            do script ""
            delay 0.5
            set newWindow to front window
            set windowId to id of newWindow as string
            set windowName to name of newWindow
            return windowId & "|||" & windowName
        end tell
        """

        let result = try await executeAppleScript(script)
        let parts = result.components(separatedBy: "|||")

        guard parts.count >= 2 else {
            throw TerminalServiceError.scriptExecutionFailed("Failed to create new window")
        }

        let window = TerminalWindow(
            id: parts[0].trimmingCharacters(in: .whitespaces),
            name: parts[1].trimmingCharacters(in: .whitespaces),
            tabTitle: nil,
            isActive: true
        )

        // Invalidate cache
        cachedWindows = []
        lastWindowFetchTime = nil

        logInfo("Created new Terminal window: \(window.displayName)", category: .terminal)
        return window
    }

    /// Opens a new Terminal window at a specific directory path
    func openNewWindow(at path: String) async throws -> TerminalWindow {
        logInfo("Opening new Terminal window at: \(path)", category: .terminal)

        let escapedPath = path.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let script = """
        tell application "Terminal"
            activate
            do script "cd \\"\(escapedPath)\\""
            delay 0.5
            set newWindow to front window
            set windowId to id of newWindow as string
            set windowName to name of newWindow
            return windowId & "|||" & windowName
        end tell
        """

        let result = try await executeAppleScript(script)
        let parts = result.components(separatedBy: "|||")

        guard parts.count >= 2 else {
            throw TerminalServiceError.scriptExecutionFailed("Failed to create new window")
        }

        let window = TerminalWindow(
            id: parts[0].trimmingCharacters(in: .whitespaces),
            name: parts[1].trimmingCharacters(in: .whitespaces),
            tabTitle: nil,
            isActive: true
        )

        // Invalidate cache
        cachedWindows = []
        lastWindowFetchTime = nil

        logInfo("Created new Terminal window at path: \(window.displayName)", category: .terminal)
        return window
    }

    /// Brings Terminal to front
    func activateTerminal() async throws {
        guard isTerminalRunning() else {
            throw TerminalServiceError.terminalNotRunning
        }

        let script = """
        tell application "Terminal"
            activate
        end tell
        """

        _ = try await executeAppleScript(script)
        logDebug("Terminal activated", category: .terminal)
    }

    /// Types text into Terminal using clipboard paste (most reliable for multiline text)
    /// Uses System Events to paste from clipboard, then optionally press Enter
    func typeText(_ text: String, pressEnter: Bool = false) async throws {
        guard isTerminalRunning() else {
            throw TerminalServiceError.terminalNotRunning
        }

        // Save current clipboard contents
        let pasteboard = NSPasteboard.general
        let previousContents = pasteboard.string(forType: .string)

        // Put our text on the clipboard
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Small delay to ensure clipboard is ready
        try await Task.sleep(nanoseconds: 50_000_000) // 50ms

        // Activate Terminal and paste using Cmd+V
        let pasteScript = """
        tell application "Terminal"
            activate
        end tell
        delay 0.1
        tell application "System Events"
            tell process "Terminal"
                keystroke "v" using command down
            end tell
        end tell
        """

        do {
            _ = try await executeAppleScript(pasteScript)

            // If we need to press Enter, do it with a delay to ensure paste completed
            if pressEnter {
                try await Task.sleep(nanoseconds: 150_000_000) // 150ms delay

                let enterScript = """
                tell application "System Events"
                    tell process "Terminal"
                        key code 36
                    end tell
                end tell
                """
                _ = try await executeAppleScript(enterScript)
            }

            logInfo("Text pasted successfully (\(text.count) chars, pressEnter: \(pressEnter))", category: .terminal)
        } catch {
            logError("Failed to paste text: \(error)", category: .terminal)
            // Restore clipboard before throwing
            if let previous = previousContents {
                pasteboard.clearContents()
                pasteboard.setString(previous, forType: .string)
            }
            throw error
        }

        // Restore previous clipboard contents after a delay
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
            if let previous = previousContents {
                pasteboard.clearContents()
                pasteboard.setString(previous, forType: .string)
            }
        }
    }

    // MARK: - AppleScript Execution

    /// Executes an AppleScript and returns the result
    func executeAppleScript(_ source: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var error: NSDictionary?
                let script = NSAppleScript(source: source)
                let result = script?.executeAndReturnError(&error)

                if let error = error {
                    let errorMessage = error[NSAppleScript.errorMessage] as? String ?? "Unknown error"
                    let errorNumber = error[NSAppleScript.errorNumber] as? Int ?? -1

                    logError("AppleScript error (\(errorNumber)): \(errorMessage)", category: .terminal)

                    // Check for specific permission errors
                    let lowerMessage = errorMessage.lowercased()
                    if lowerMessage.contains("not allowed to send keystrokes") || lowerMessage.contains("accessibility") {
                        // Accessibility permission needed for System Events keystrokes
                        continuation.resume(throwing: TerminalServiceError.accessibilityPermissionDenied)
                    } else if errorNumber == -1743 || lowerMessage.contains("not allowed") || lowerMessage.contains("not authorized") {
                        // Automation permission denied
                        continuation.resume(throwing: TerminalServiceError.permissionDenied)
                    } else {
                        continuation.resume(throwing: TerminalServiceError.scriptExecutionFailed(errorMessage))
                    }
                    return
                }

                let stringResult = result?.stringValue ?? ""
                continuation.resume(returning: stringResult)
            }
        }
    }

    /// Escapes special characters for AppleScript string literals
    private func escapeForAppleScript(_ string: String) -> String {
        var escaped = string

        // Escape backslashes first
        escaped = escaped.replacingOccurrences(of: "\\", with: "\\\\")

        // Escape double quotes
        escaped = escaped.replacingOccurrences(of: "\"", with: "\\\"")

        // Handle newlines - convert to AppleScript line continuation
        escaped = escaped.replacingOccurrences(of: "\n", with: "\" & return & \"")

        // Handle tabs
        escaped = escaped.replacingOccurrences(of: "\t", with: "\" & tab & \"")

        return escaped
    }

    /// Parses an AppleScript list result (comma-separated with possible quotes)
    private func parseAppleScriptList(_ result: String) -> [String] {
        // AppleScript returns lists like: item1, item2, item3
        // Handle potential quoting and whitespace

        var items: [String] = []
        var current = ""
        var inQuotes = false

        for char in result {
            switch char {
            case "\"":
                inQuotes.toggle()
            case ",":
                if !inQuotes {
                    let trimmed = current.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty {
                        items.append(trimmed)
                    }
                    current = ""
                } else {
                    current.append(char)
                }
            default:
                current.append(char)
            }
        }

        // Don't forget the last item
        let trimmed = current.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            items.append(trimmed)
        }

        return items
    }

    /// Invalidates the window cache
    func invalidateCache() {
        cachedWindows = []
        lastWindowFetchTime = nil
        logDebug("Window cache invalidated", category: .terminal)
    }
}

// MARK: - Terminal Dispatch Service

extension TerminalService {
    /// Finds terminal windows that match a project name
    /// Matches against window name and tab title (case insensitive)
    func findTerminalsForProject(named projectName: String) async throws -> [TerminalWindow] {
        guard !projectName.isEmpty else { return [] }

        let allTerminals = try await getWindows(forceRefresh: true)
        let projectLower = projectName.lowercased()

        let matching = allTerminals.filter { terminal in
            let name = terminal.name.lowercased()
            let tabTitle = terminal.tabTitle?.lowercased() ?? ""
            return name.contains(projectLower) || tabTitle.contains(projectLower)
        }

        logDebug("Found \(matching.count) terminals matching project '\(projectName)'", category: .terminal)
        return matching
    }

    /// Unified dispatch method - sends content to a terminal matching the project
    /// If no matching terminal exists, creates a new one, starts Claude Code, and sends the content
    ///
    /// - Parameters:
    ///   - content: The prompt content to send
    ///   - projectPath: The file system path of the project
    ///   - projectName: The display name of the project (used for terminal matching)
    ///   - pressEnter: Whether to press enter after typing (default: true)
    /// - Returns: The terminal window that was used
    @discardableResult
    func dispatchPrompt(
        content: String,
        projectPath: String?,
        projectName: String?,
        pressEnter: Bool = true
    ) async throws -> TerminalWindow {
        guard !content.isEmpty else {
            throw TerminalServiceError.invalidPromptContent
        }

        logInfo("Dispatching prompt to project: '\(projectName ?? "none")' at path: '\(projectPath ?? "none")'", category: .terminal)

        // Try to find a matching terminal if we have a project name
        var targetTerminal: TerminalWindow?

        if let projectName = projectName, !projectName.isEmpty {
            let matchingTerminals = try await findTerminalsForProject(named: projectName)

            if let firstMatch = matchingTerminals.first {
                logInfo("Found matching terminal: \(firstMatch.displayName)", category: .terminal)
                targetTerminal = firstMatch
            }
        }

        if let terminal = targetTerminal {
            // Dispatch to existing terminal
            // First activate the specific window
            let script = """
            tell application "Terminal"
                activate
                set frontmost of window id \(terminal.id) to true
            end tell
            """
            _ = try? await executeAppleScript(script)

            // Small delay for window focus
            try await Task.sleep(nanoseconds: 100_000_000)

            // Type the content
            try await typeText(content, pressEnter: pressEnter)

            logInfo("Prompt dispatched to existing terminal: \(terminal.displayName)", category: .terminal)
            return terminal

        } else {
            // No matching terminal - create new one
            logInfo("No matching terminal found, creating new one", category: .terminal)

            // Determine working directory
            let workingDir = projectPath ?? FileManager.default.homeDirectoryForCurrentUser.path

            // Open new terminal at project path
            let newWindow = try await openNewWindow(at: workingDir)

            // Wait for terminal to initialize
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5s

            // Start Claude Code using typeText (sendPrompt would create a new tab)
            try await typeText("claude --dangerously-skip-permissions", pressEnter: true)

            // Wait for Claude to start up
            try await Task.sleep(nanoseconds: 2_000_000_000) // 2s

            // Type the content
            try await typeText(content, pressEnter: pressEnter)

            logInfo("Prompt dispatched to new terminal: \(newWindow.displayName)", category: .terminal)
            return newWindow
        }
    }
}

// MARK: - Terminal Window Display Names

extension TerminalWindow {
    /// Parses the Claude Code session description from the terminal window title
    /// Terminal titles typically look like: "ProjectName — ✳ Session Description — sourcekit-lsp ◂ claude ..."
    /// Returns the session description or a cleaned up version of the window name
    var claudeSessionName: String {
        let title = tabTitle?.isEmpty == false ? tabTitle! : name

        // Try em-dash format first (Claude Code uses: "Project — ✳ Description — sourcekit-lsp ◂ ...")
        if let starRange = title.range(of: " — ✳ ") ?? title.range(of: " — ✳") {
            let afterStar = title[starRange.upperBound...]

            // Look for next em-dash separator
            if let nextDash = afterStar.range(of: " — ") {
                let sessionPart = afterStar[..<nextDash.lowerBound]
                let cleaned = sessionPart.trimmingCharacters(in: .whitespaces)
                if !cleaned.isEmpty && cleaned.count < 60 {
                    return cleaned
                }
            } else {
                // No ending separator, use the rest (but stop at common suffixes)
                var remaining = String(afterStar)
                if let dashIndex = remaining.range(of: " ◂ ") {
                    remaining = String(remaining[..<dashIndex.lowerBound])
                }
                let cleaned = remaining.trimmingCharacters(in: .whitespaces)
                if !cleaned.isEmpty && cleaned.count < 60 {
                    return cleaned
                }
            }
        }

        // Try double-hyphen format as fallback ("Project -- * Description -- ...")
        if let starRange = title.range(of: "-- *") ?? title.range(of: "-- ") {
            let afterStar = title[starRange.upperBound...]
            if let nextDash = afterStar.range(of: " --") {
                let sessionPart = afterStar[..<nextDash.lowerBound]
                let cleaned = sessionPart.trimmingCharacters(in: .whitespaces)
                if !cleaned.isEmpty && cleaned.count < 60 {
                    return cleaned
                }
            } else {
                let cleaned = afterStar.trimmingCharacters(in: .whitespaces)
                if !cleaned.isEmpty && cleaned.count < 60 {
                    return cleaned
                }
            }
        }

        // Try to extract from between em-dashes ("ProjectName — Description — more")
        if let firstDash = title.range(of: " — ") {
            let afterFirst = title[firstDash.upperBound...]
            if let secondDash = afterFirst.range(of: " — ") {
                let sessionPart = afterFirst[..<secondDash.lowerBound]
                let cleaned = sessionPart.trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: "✳ ", with: "")
                    .replacingOccurrences(of: "✳", with: "")
                if !cleaned.isEmpty && cleaned.count < 60 {
                    return cleaned
                }
            }
        }

        // Fallback: clean up the title
        var displayName = title

        // Remove common prefixes like "user@hostname: "
        if let colonIndex = displayName.lastIndex(of: ":") {
            let afterColon = displayName[displayName.index(after: colonIndex)...].trimmingCharacters(in: .whitespaces)
            if !afterColon.isEmpty {
                displayName = afterColon
            }
        }

        // Extract last path component if it looks like a path
        if displayName.contains("/") {
            if let lastComponent = displayName.components(separatedBy: "/").last, !lastComponent.isEmpty {
                displayName = lastComponent
            }
        }

        // Truncate if too long
        if displayName.count > 40 {
            displayName = String(displayName.prefix(37)) + "..."
        }

        return displayName
    }

    /// Display name with active indicator
    var displayNameWithStatus: String {
        var name = claudeSessionName
        if isActive {
            name = "● " + name
        }
        return name
    }
}

// MARK: - Terminal Service Convenience Extensions

extension TerminalService {
    /// Checks if a specific window still exists
    func windowExists(_ windowId: String) async throws -> Bool {
        let windows = try await getWindows(forceRefresh: true)
        return windows.contains { $0.id == windowId }
    }

    /// Gets window by ID
    func getWindow(byId id: String) async throws -> TerminalWindow? {
        let windows = try await getWindows()
        return windows.first { $0.id == id }
    }

    /// Detects if Claude Code prompt is visible in window (for polling fallback)
    func isClaudeCodePromptVisible(windowId: String? = nil) async throws -> Bool {
        let content = try await getWindowContent(windowId: windowId, lastNCharacters: 200)

        // Check for Claude Code prompt patterns
        let promptPatterns = ["╭─", "│", "╰─", ">", "claude>"]

        for pattern in promptPatterns {
            if content.contains(pattern) {
                // Look for pattern near the end (within last 50 chars)
                if let range = content.range(of: pattern, options: .backwards) {
                    let distance = content.distance(from: range.lowerBound, to: content.endIndex)
                    if distance < 100 {
                        logDebug("Claude Code prompt detected (pattern: \(pattern))", category: .terminal)
                        return true
                    }
                }
            }
        }

        return false
    }

    /// Pastes from clipboard to Terminal using Cmd+V
    /// Assumes clipboard already contains the content to paste
    func pasteFromClipboard() async throws {
        guard isTerminalRunning() else {
            throw TerminalServiceError.terminalNotRunning
        }

        logDebug("Pasting from clipboard to Terminal", category: .terminal)

        let pasteScript = """
        tell application "Terminal"
            activate
        end tell
        delay 0.1
        tell application "System Events"
            tell process "Terminal"
                keystroke "v" using command down
            end tell
        end tell
        """

        _ = try await executeAppleScript(pasteScript)
        logInfo("Pasted from clipboard to Terminal", category: .terminal)
    }

    /// Types text into the active Terminal window without using clipboard
    /// More reliable for simple text dispatch after image paste
    func sendTextToActiveWindow(_ text: String, pressEnter: Bool = true) async throws {
        guard !text.isEmpty else {
            throw TerminalServiceError.invalidPromptContent
        }

        guard isTerminalRunning() else {
            throw TerminalServiceError.terminalNotRunning
        }

        logDebug("Sending text to active Terminal window (\(text.count) chars)", category: .terminal)

        // Use typeText which handles clipboard properly
        try await typeText(text, pressEnter: pressEnter)
    }
}

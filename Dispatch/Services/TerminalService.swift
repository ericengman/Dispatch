//
//  TerminalService.swift
//  Dispatch
//
//  Service for Terminal.app integration via AppleScript
//

import Foundation
import AppKit

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
        case .windowNotFound(let id):
            return "Terminal window with ID '\(id)' not found"
        case .scriptExecutionFailed(let message):
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
    private let windowCacheDuration: TimeInterval = 2.0  // Cache windows for 2 seconds

    private init() {
        logDebug("TerminalService initialized", category: .terminal)
    }

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
        try await Task.sleep(nanoseconds: 500_000_000)  // 0.5 seconds

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

        let perf = PerformanceLogger("getWindows", category: .terminal)
        defer { perf.end() }

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
        logDebug("Raw getWindows result: \(result.prefix(200))...", category: .terminal)

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

        logDebug("Fetched \(windows.count) Terminal windows", category: .terminal)
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

    /// Types text into Terminal without pressing enter
    /// Uses System Events to simulate keystrokes
    func typeText(_ text: String, pressEnter: Bool = false) async throws {
        guard isTerminalRunning() else {
            throw TerminalServiceError.terminalNotRunning
        }

        let escapedText = text.replacingOccurrences(of: "\\", with: "\\\\")
                              .replacingOccurrences(of: "\"", with: "\\\"")

        var script = """
        tell application "Terminal"
            activate
        end tell
        tell application "System Events"
            tell process "Terminal"
                keystroke "\(escapedText)"
        """

        if pressEnter {
            // Use key code 36 for Return key (more reliable than keystroke return)
            script += """

                key code 36
        """
        }

        script += """

            end tell
        end tell
        """

        logDebug("Typing text (\(text.count) chars, pressEnter: \(pressEnter)): '\(text)'", category: .terminal)
        logDebug("AppleScript:\n\(script)", category: .terminal)

        do {
            _ = try await executeAppleScript(script)
            logInfo("Text typed successfully", category: .terminal)
        } catch {
            logError("Failed to type text: \(error)", category: .terminal)
            throw error
        }
    }

    // MARK: - Private Methods

    /// Executes an AppleScript and returns the result
    private func executeAppleScript(_ source: String) async throws -> String {
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
}

//
//  AppSettings.swift
//  Dispatch
//
//  Application settings model with singleton pattern
//

import Carbon.HIToolbox
import Combine
import Foundation
import SwiftData

// MARK: - Default Values

enum AppSettingsDefaults {
    static let globalHotkeyKeyCode: Int = .init(kVK_ANSI_D) // 'D' key
    static let globalHotkeyModifiers: Int = .init(cmdKey | shiftKey) // ⌘⇧
    static let regionCaptureKeyCode: Int = .init(kVK_ANSI_1) // '1' key
    static let regionCaptureModifiers: Int = .init(cmdKey | controlKey) // ⌘⌃
    static let windowCaptureKeyCode: Int = .init(kVK_ANSI_2) // '2' key
    static let windowCaptureModifiers: Int = .init(cmdKey | controlKey) // ⌘⌃
    static let showInMenuBar: Bool = false
    static let showDockIcon: Bool = true
    static let autoDetectActiveTerminal: Bool = true
    static let sendDelayMs: Double = 100.0
    static let enableClaudeHooks: Bool = true
    static let hookServerPort: Int = 19847
    static let historyRetentionDays: Int = 30
    static let usePollingFallback: Bool = true
    static let pollingIntervalSeconds: Double = 2.0
    static let compactRowHeight: Bool = false
    static let editorFontSize: Int = 14
    static let launchAtLogin: Bool = false
    static let autoRefreshTerminalList: Bool = true
    static let defaultAnnotationColor: String = "red"
    static let maxRunsPerProject: Int = 10
}

@Model
final class AppSettings {
    // MARK: - Properties

    var id: UUID

    // MARK: - Hotkey Settings

    /// Key code for global hotkey (Carbon key codes)
    var globalHotkeyKeyCode: Int?

    /// Modifier flags for global hotkey
    var globalHotkeyModifiers: Int?

    /// Whether to send clipboard as prompt when hotkey triggered with additional modifier
    var sendClipboardOnHotkey: Bool

    /// Key code for region capture hotkey
    var regionCaptureKeyCode: Int?

    /// Modifier flags for region capture hotkey
    var regionCaptureModifiers: Int?

    /// Key code for window capture hotkey
    var windowCaptureKeyCode: Int?

    /// Modifier flags for window capture hotkey
    var windowCaptureModifiers: Int?

    // MARK: - Window & Display

    /// Show app icon in menu bar
    var showInMenuBar: Bool

    /// Show dock icon (if menu bar enabled, can hide dock icon)
    var showDockIcon: Bool

    /// Launch application at login
    var launchAtLogin: Bool

    /// Use compact row height in lists
    var compactRowHeight: Bool

    /// Editor font size (12-18pt)
    var editorFontSize: Int

    // MARK: - Terminal Settings

    /// Auto-detect active terminal window
    var autoDetectActiveTerminal: Bool

    /// Delay in milliseconds after focusing terminal before sending
    var sendDelayMs: Double

    /// Auto-refresh terminal window list
    var autoRefreshTerminalList: Bool

    /// Default terminal target ID (nil = active window)
    var defaultTerminalId: String?

    // MARK: - Hook Settings

    /// Enable Claude Code hooks for completion detection
    var enableClaudeHooks: Bool

    /// Port for local hook server
    var hookServerPort: Int

    /// Use polling fallback when hooks unavailable
    var usePollingFallback: Bool

    /// Polling interval in seconds
    var pollingIntervalSeconds: Double

    // MARK: - Data Settings

    /// Default project ID for new prompts
    var defaultProjectId: UUID?

    /// Number of days to retain history
    var historyRetentionDays: Int

    // MARK: - Screenshot Settings

    /// Custom screenshot directory path (nil = use default)
    var screenshotDirectory: String?

    /// Default annotation color for new annotations
    var defaultAnnotationColor: String

    /// Maximum runs to keep per project
    var maxRunsPerProject: Int

    // MARK: - Internal

    /// Last modified timestamp
    var updatedAt: Date

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        globalHotkeyKeyCode: Int? = AppSettingsDefaults.globalHotkeyKeyCode,
        globalHotkeyModifiers: Int? = AppSettingsDefaults.globalHotkeyModifiers,
        sendClipboardOnHotkey: Bool = false,
        regionCaptureKeyCode: Int? = AppSettingsDefaults.regionCaptureKeyCode,
        regionCaptureModifiers: Int? = AppSettingsDefaults.regionCaptureModifiers,
        windowCaptureKeyCode: Int? = AppSettingsDefaults.windowCaptureKeyCode,
        windowCaptureModifiers: Int? = AppSettingsDefaults.windowCaptureModifiers,
        showInMenuBar: Bool = AppSettingsDefaults.showInMenuBar,
        showDockIcon: Bool = AppSettingsDefaults.showDockIcon,
        launchAtLogin: Bool = AppSettingsDefaults.launchAtLogin,
        compactRowHeight: Bool = AppSettingsDefaults.compactRowHeight,
        editorFontSize: Int = AppSettingsDefaults.editorFontSize,
        autoDetectActiveTerminal: Bool = AppSettingsDefaults.autoDetectActiveTerminal,
        sendDelayMs: Double = AppSettingsDefaults.sendDelayMs,
        autoRefreshTerminalList: Bool = AppSettingsDefaults.autoRefreshTerminalList,
        defaultTerminalId: String? = nil,
        enableClaudeHooks: Bool = AppSettingsDefaults.enableClaudeHooks,
        hookServerPort: Int = AppSettingsDefaults.hookServerPort,
        usePollingFallback: Bool = AppSettingsDefaults.usePollingFallback,
        pollingIntervalSeconds: Double = AppSettingsDefaults.pollingIntervalSeconds,
        defaultProjectId: UUID? = nil,
        historyRetentionDays: Int = AppSettingsDefaults.historyRetentionDays,
        screenshotDirectory: String? = nil,
        defaultAnnotationColor: String = AppSettingsDefaults.defaultAnnotationColor,
        maxRunsPerProject: Int = AppSettingsDefaults.maxRunsPerProject
    ) {
        self.id = id
        self.globalHotkeyKeyCode = globalHotkeyKeyCode
        self.globalHotkeyModifiers = globalHotkeyModifiers
        self.sendClipboardOnHotkey = sendClipboardOnHotkey
        self.regionCaptureKeyCode = regionCaptureKeyCode
        self.regionCaptureModifiers = regionCaptureModifiers
        self.windowCaptureKeyCode = windowCaptureKeyCode
        self.windowCaptureModifiers = windowCaptureModifiers
        self.showInMenuBar = showInMenuBar
        self.showDockIcon = showDockIcon
        self.launchAtLogin = launchAtLogin
        self.compactRowHeight = compactRowHeight
        self.editorFontSize = editorFontSize
        self.autoDetectActiveTerminal = autoDetectActiveTerminal
        self.sendDelayMs = sendDelayMs
        self.autoRefreshTerminalList = autoRefreshTerminalList
        self.defaultTerminalId = defaultTerminalId
        self.enableClaudeHooks = enableClaudeHooks
        self.hookServerPort = hookServerPort
        self.usePollingFallback = usePollingFallback
        self.pollingIntervalSeconds = pollingIntervalSeconds
        self.defaultProjectId = defaultProjectId
        self.historyRetentionDays = historyRetentionDays
        self.screenshotDirectory = screenshotDirectory
        self.defaultAnnotationColor = defaultAnnotationColor
        self.maxRunsPerProject = maxRunsPerProject
        updatedAt = Date()

        logDebug("Created AppSettings instance", category: .settings)
    }

    // MARK: - Computed Properties

    /// Returns hotkey description for display (e.g., "⌘⇧D")
    var hotkeyDescription: String {
        guard let keyCode = globalHotkeyKeyCode,
              let modifiers = globalHotkeyModifiers
        else {
            return "Not Set"
        }

        var parts: [String] = []

        if modifiers & Int(controlKey) != 0 { parts.append("⌃") }
        if modifiers & Int(optionKey) != 0 { parts.append("⌥") }
        if modifiers & Int(shiftKey) != 0 { parts.append("⇧") }
        if modifiers & Int(cmdKey) != 0 { parts.append("⌘") }

        if let keyName = Self.keyCodeToString(keyCode) {
            parts.append(keyName)
        }

        return parts.joined()
    }

    /// Whether a hotkey is configured
    var hasHotkey: Bool {
        globalHotkeyKeyCode != nil && globalHotkeyModifiers != nil
    }

    /// Send delay in seconds
    var sendDelaySeconds: Double {
        sendDelayMs / 1000.0
    }

    /// Returns region capture hotkey description for display
    var regionCaptureDescription: String {
        guard let keyCode = regionCaptureKeyCode,
              let modifiers = regionCaptureModifiers
        else {
            return "Not Set"
        }

        var parts: [String] = []

        if modifiers & Int(controlKey) != 0 { parts.append("⌃") }
        if modifiers & Int(optionKey) != 0 { parts.append("⌥") }
        if modifiers & Int(shiftKey) != 0 { parts.append("⇧") }
        if modifiers & Int(cmdKey) != 0 { parts.append("⌘") }

        if let keyName = Self.keyCodeToString(keyCode) {
            parts.append(keyName)
        }

        return parts.joined()
    }

    /// Returns window capture hotkey description for display
    var windowCaptureDescription: String {
        guard let keyCode = windowCaptureKeyCode,
              let modifiers = windowCaptureModifiers
        else {
            return "Not Set"
        }

        var parts: [String] = []

        if modifiers & Int(controlKey) != 0 { parts.append("⌃") }
        if modifiers & Int(optionKey) != 0 { parts.append("⌥") }
        if modifiers & Int(shiftKey) != 0 { parts.append("⇧") }
        if modifiers & Int(cmdKey) != 0 { parts.append("⌘") }

        if let keyName = Self.keyCodeToString(keyCode) {
            parts.append(keyName)
        }

        return parts.joined()
    }

    /// Whether capture shortcuts are configured
    var hasCaptureShortcuts: Bool {
        (regionCaptureKeyCode != nil && regionCaptureModifiers != nil) ||
            (windowCaptureKeyCode != nil && windowCaptureModifiers != nil)
    }

    // MARK: - Methods

    /// Updates the global hotkey
    func setHotkey(keyCode: Int, modifiers: Int) {
        globalHotkeyKeyCode = keyCode
        globalHotkeyModifiers = modifiers
        updatedAt = Date()
        logInfo("Updated hotkey to: \(hotkeyDescription)", category: .settings)
    }

    /// Clears the global hotkey
    func clearHotkey() {
        globalHotkeyKeyCode = nil
        globalHotkeyModifiers = nil
        updatedAt = Date()
        logInfo("Cleared global hotkey", category: .settings)
    }

    /// Updates hook server port
    func setHookServerPort(_ port: Int) {
        guard port >= 1024, port <= 65535 else {
            logWarning("Invalid port number: \(port)", category: .settings)
            return
        }
        hookServerPort = port
        updatedAt = Date()
        logInfo("Updated hook server port to: \(port)", category: .settings)
    }

    /// Updates editor font size
    func setEditorFontSize(_ size: Int) {
        guard size >= 12, size <= 18 else {
            logWarning("Invalid font size: \(size)", category: .settings)
            return
        }
        editorFontSize = size
        updatedAt = Date()
        logDebug("Updated editor font size to: \(size)", category: .settings)
    }

    /// Updates history retention
    func setHistoryRetention(days: Int) {
        guard days >= 1, days <= 365 else {
            logWarning("Invalid retention period: \(days)", category: .settings)
            return
        }
        historyRetentionDays = days
        updatedAt = Date()
        logDebug("Updated history retention to: \(days) days", category: .settings)
    }

    /// Resets all settings to defaults
    func resetToDefaults() {
        globalHotkeyKeyCode = AppSettingsDefaults.globalHotkeyKeyCode
        globalHotkeyModifiers = AppSettingsDefaults.globalHotkeyModifiers
        sendClipboardOnHotkey = false
        regionCaptureKeyCode = AppSettingsDefaults.regionCaptureKeyCode
        regionCaptureModifiers = AppSettingsDefaults.regionCaptureModifiers
        windowCaptureKeyCode = AppSettingsDefaults.windowCaptureKeyCode
        windowCaptureModifiers = AppSettingsDefaults.windowCaptureModifiers
        showInMenuBar = AppSettingsDefaults.showInMenuBar
        showDockIcon = AppSettingsDefaults.showDockIcon
        launchAtLogin = AppSettingsDefaults.launchAtLogin
        compactRowHeight = AppSettingsDefaults.compactRowHeight
        editorFontSize = AppSettingsDefaults.editorFontSize
        autoDetectActiveTerminal = AppSettingsDefaults.autoDetectActiveTerminal
        sendDelayMs = AppSettingsDefaults.sendDelayMs
        autoRefreshTerminalList = AppSettingsDefaults.autoRefreshTerminalList
        defaultTerminalId = nil
        enableClaudeHooks = AppSettingsDefaults.enableClaudeHooks
        hookServerPort = AppSettingsDefaults.hookServerPort
        usePollingFallback = AppSettingsDefaults.usePollingFallback
        pollingIntervalSeconds = AppSettingsDefaults.pollingIntervalSeconds
        defaultProjectId = nil
        historyRetentionDays = AppSettingsDefaults.historyRetentionDays
        screenshotDirectory = nil
        defaultAnnotationColor = AppSettingsDefaults.defaultAnnotationColor
        maxRunsPerProject = AppSettingsDefaults.maxRunsPerProject
        updatedAt = Date()

        logInfo("Reset all settings to defaults", category: .settings)
    }

    // MARK: - Key Code Mapping

    private static func keyCodeToString(_ keyCode: Int) -> String? {
        let keyMap: [Int: String] = [
            kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D",
            kVK_ANSI_E: "E", kVK_ANSI_F: "F", kVK_ANSI_G: "G", kVK_ANSI_H: "H",
            kVK_ANSI_I: "I", kVK_ANSI_J: "J", kVK_ANSI_K: "K", kVK_ANSI_L: "L",
            kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O", kVK_ANSI_P: "P",
            kVK_ANSI_Q: "Q", kVK_ANSI_R: "R", kVK_ANSI_S: "S", kVK_ANSI_T: "T",
            kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X",
            kVK_ANSI_Y: "Y", kVK_ANSI_Z: "Z",
            kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3",
            kVK_ANSI_4: "4", kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7",
            kVK_ANSI_8: "8", kVK_ANSI_9: "9",
            kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥",
            kVK_Delete: "⌫", kVK_Escape: "⎋",
            kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4",
            kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8",
            kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
            kVK_LeftArrow: "←", kVK_RightArrow: "→",
            kVK_UpArrow: "↑", kVK_DownArrow: "↓"
        ]
        return keyMap[keyCode]
    }
}

// MARK: - Settings Manager

/// Manager for accessing and modifying app settings with singleton pattern
@MainActor
final class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

    @Published private(set) var settings: AppSettings?
    private var modelContext: ModelContext?

    private init() {}

    /// Configure with model context (call from app startup)
    func configure(with context: ModelContext) {
        modelContext = context
        loadOrCreateSettings()
    }

    /// Loads existing settings or creates defaults
    private func loadOrCreateSettings() {
        guard let context = modelContext else {
            logError("ModelContext not configured", category: .settings)
            return
        }

        let descriptor = FetchDescriptor<AppSettings>()

        do {
            let existing = try context.fetch(descriptor)
            if let first = existing.first {
                settings = first
                logInfo("Loaded existing settings", category: .settings)

                // Clean up duplicates if any
                if existing.count > 1 {
                    logWarning("Found \(existing.count) settings records, cleaning up", category: .settings)
                    for extra in existing.dropFirst() {
                        context.delete(extra)
                    }
                    try context.save()
                }
            } else {
                // Create default settings
                let newSettings = AppSettings()
                context.insert(newSettings)
                try context.save()
                settings = newSettings
                logInfo("Created default settings", category: .settings)
            }
        } catch {
            error.log(category: .settings, context: "Failed to load/create settings")
        }
    }

    /// Saves current settings
    func save() {
        guard let context = modelContext else {
            logError("ModelContext not configured", category: .settings)
            return
        }

        do {
            try context.save()
            logDebug("Settings saved", category: .settings)
        } catch {
            error.log(category: .settings, context: "Failed to save settings")
        }
    }
}

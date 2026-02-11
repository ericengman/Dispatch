//
//  BrewModeController.swift
//  Dispatch
//
//  State machine for auto-condensing terminal sessions while Claude Code is working.
//  Condenses sessions to compact "brew strips" during thinking/executing states,
//  and auto-expands when idle or waiting for user input.
//

import Foundation
import SwiftTerm
import SwiftUI

// MARK: - Brew State

enum BrewState: Equatable {
    case expanded // Normal terminal view
    case condensing // In 3s debounce before condensing
    case condensed // Showing brew strip
    case peeking // Temporarily expanded (5s timeout)
    case manuallyExpanded // User clicked Expand, stays until idle
}

// MARK: - BrewModeController

@Observable
@MainActor
final class BrewModeController {
    static let shared = BrewModeController()

    // MARK: - Public State

    /// Global toggle for brew mode, persisted in UserDefaults
    var isBrewModeEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isBrewModeEnabled, forKey: "brewModeEnabled")
            if !isBrewModeEnabled {
                expandAllSessions()
            }
            logInfo("Brew mode \(isBrewModeEnabled ? "enabled" : "disabled")", category: .terminal)
        }
    }

    /// Per-session brew state
    var brewStates: [UUID: BrewState] = [:]

    /// ANSI-stripped terminal buffer excerpts for condensed sessions
    var previewTexts: [UUID: String] = [:]

    /// When each session entered the condensed state
    var brewStartTimes: [UUID: Date] = [:]

    /// Red flash flag for sessions that expanded due to .waiting state
    var expandedWithAlert: [UUID: Bool] = [:]

    /// Current title prefix per session — tracks working/finished state from terminal title.
    var titlePrefixes: [UUID: EmbeddedTerminalView.Coordinator.ClaudeTitlePrefix] = [:]

    // MARK: - Private State

    /// Debounce timers for condensing (3s delay)
    private var condenseTimers: [UUID: Task<Void, Never>] = [:]

    /// Auto-revert timers for peeking (5s)
    private var peekTimers: [UUID: Task<Void, Never>] = [:]

    /// Hover-to-peek timers (1s delay before peeking)
    private var hoverTimers: [UUID: Task<Void, Never>] = [:]

    /// Alert flash auto-clear timers (2s)
    private var alertTimers: [UUID: Task<Void, Never>] = [:]

    /// Background task for preview text refresh
    private var previewRefreshTask: Task<Void, Never>?

    /// Whether observation is already running
    private var isObserving = false

    // MARK: - Init

    private init() {
        isBrewModeEnabled = UserDefaults.standard.object(forKey: "brewModeEnabled") as? Bool ?? true
        logDebug("BrewModeController initialized, enabled: \(isBrewModeEnabled)", category: .terminal)
    }

    // MARK: - Public API

    /// Start preview text refresh loop. State detection is title-driven via handleTitleChange.
    /// Safe to call multiple times.
    func startObserving() {
        guard !isObserving else { return }
        isObserving = true
        logDebug("BrewModeController starting preview refresh loop", category: .terminal)

        previewRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000) // 3s
                guard let self else { return }
                await self.refreshPreviewTexts()
            }
        }
    }

    /// Stop observation
    func stopObserving() {
        previewRefreshTask?.cancel()
        previewRefreshTask = nil
        isObserving = false
        logDebug("BrewModeController stopped observation", category: .terminal)
    }

    /// Check if a session is currently in a condensed display state.
    /// Only `.condensed` triggers the brew strip — `.condensing` is the debounce period
    /// where the terminal remains visible.
    func isCondensed(_ sessionId: UUID) -> Bool {
        brewStates[sessionId] == .condensed
    }

    /// Hover started on brew strip — start 1s timer to peek
    func startHoverPeek(_ sessionId: UUID) {
        guard brewStates[sessionId] == .condensed else { return }

        hoverTimers[sessionId]?.cancel()
        hoverTimers[sessionId] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1s delay
            guard !Task.isCancelled, let self else { return }
            guard self.brewStates[sessionId] == .condensed else { return }

            logDebug("Hover peek triggered for session \(sessionId)", category: .terminal)
            withAnimation(.easeInOut(duration: 0.2)) {
                self.brewStates[sessionId] = .peeking
            }

            // Auto-revert after 5s if still peeking
            self.peekTimers[sessionId]?.cancel()
            self.peekTimers[sessionId] = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard !Task.isCancelled, let self else { return }
                if self.brewStates[sessionId] == .peeking {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        self.brewStates[sessionId] = .condensed
                    }
                    logDebug("Hover peek expired, re-condensing session \(sessionId)", category: .terminal)
                }
            }
        }
    }

    /// Hover ended on brew strip — cancel pending hover timer if still condensed
    func cancelHoverPeek(_ sessionId: UUID) {
        // Only cancel if still waiting to peek; don't cancel if already peeking
        if brewStates[sessionId] == .condensed {
            hoverTimers[sessionId]?.cancel()
            hoverTimers.removeValue(forKey: sessionId)
        }
    }

    /// User clicked brew strip — stays expanded until manually condensed or session goes idle
    func manualExpand(_ sessionId: UUID) {
        logDebug("Manual expand for session \(sessionId)", category: .terminal)
        hoverTimers[sessionId]?.cancel()
        cancelCondenseTimer(sessionId)
        peekTimers[sessionId]?.cancel()
        withAnimation(.easeInOut(duration: 0.2)) {
            brewStates[sessionId] = .manuallyExpanded
        }
    }

    /// User clicked condense button — force back to condensed state
    func manualCondense(_ sessionId: UUID) {
        logDebug("Manual condense for session \(sessionId)", category: .terminal)
        hoverTimers[sessionId]?.cancel()
        peekTimers[sessionId]?.cancel()
        withAnimation(.easeInOut(duration: 0.2)) {
            brewStates[sessionId] = .condensed
            if brewStartTimes[sessionId] == nil {
                brewStartTimes[sessionId] = Date()
            }
        }
        // Refresh preview text since terminal may have updated
        Task {
            await snapshotPreviewText(for: sessionId)
        }
    }

    /// Clean up state when a session is closed
    func cleanupSession(_ sessionId: UUID) {
        brewStates.removeValue(forKey: sessionId)
        previewTexts.removeValue(forKey: sessionId)
        brewStartTimes.removeValue(forKey: sessionId)
        expandedWithAlert.removeValue(forKey: sessionId)
        titlePrefixes.removeValue(forKey: sessionId)
        cancelCondenseTimer(sessionId)
        peekTimers[sessionId]?.cancel()
        peekTimers.removeValue(forKey: sessionId)
        hoverTimers[sessionId]?.cancel()
        hoverTimers.removeValue(forKey: sessionId)
        alertTimers[sessionId]?.cancel()
        alertTimers.removeValue(forKey: sessionId)
        logDebug("Cleaned up brew state for session \(sessionId.uuidString.prefix(8))", category: .terminal)
    }

    // MARK: - Title-Driven State Detection

    /// Called by EmbeddedTerminalView.setTerminalTitle when Claude Code changes its title.
    /// The title prefix indicates Claude's current state — no polling needed.
    func handleTitleChange(
        sessionId: UUID,
        prefix: EmbeddedTerminalView.Coordinator.ClaudeTitlePrefix
    ) {
        titlePrefixes[sessionId] = prefix

        guard isBrewModeEnabled else { return }
        let currentState = brewStates[sessionId] ?? .expanded

        switch prefix {
        case .working:
            handleActiveState(sessionId: sessionId, currentBrewState: currentState)
        case .finished:
            handleIdleState(sessionId: sessionId, currentBrewState: currentState, isWaiting: true)
        case .none:
            handleIdleState(sessionId: sessionId, currentBrewState: currentState, isWaiting: false)
        }
    }

    // MARK: - State Machine

    /// Handle thinking/executing: start condense timer if not already condensing
    private func handleActiveState(sessionId: UUID, currentBrewState: BrewState) {
        switch currentBrewState {
        case .expanded:
            startCondenseTimer(sessionId)
            brewStates[sessionId] = .condensing
        case .condensing, .condensed, .peeking, .manuallyExpanded:
            break // No-op: already condensing, condensed, or user-controlled
        }
    }

    /// Handle idle/waiting: immediately expand, cancel timers
    private func handleIdleState(sessionId: UUID, currentBrewState: BrewState, isWaiting: Bool) {
        cancelCondenseTimer(sessionId)
        peekTimers[sessionId]?.cancel()

        switch currentBrewState {
        case .expanded:
            break
        case .manuallyExpanded:
            brewStates[sessionId] = .expanded
        case .condensing, .condensed, .peeking:
            withAnimation(.easeInOut(duration: 0.2)) {
                brewStates[sessionId] = .expanded
                brewStartTimes.removeValue(forKey: sessionId)
            }
            if isWaiting {
                triggerAlertFlash(sessionId)
            }
        }
    }

    // MARK: - Timers

    private func startCondenseTimer(_ sessionId: UUID) {
        cancelCondenseTimer(sessionId)
        condenseTimers[sessionId] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000) // 3s debounce
            guard !Task.isCancelled, let self else { return }

            // Verify still in condensing state
            guard self.brewStates[sessionId] == .condensing else { return }

            // Snapshot preview BEFORE condensing (terminal is still full-size with all rows visible)
            await self.snapshotPreviewText(for: sessionId)

            withAnimation(.easeInOut(duration: 0.2)) {
                self.brewStates[sessionId] = .condensed
                self.brewStartTimes[sessionId] = Date()
            }
            logDebug("Session \(sessionId) condensed after 3s debounce", category: .terminal)
        }
    }

    private func cancelCondenseTimer(_ sessionId: UUID) {
        condenseTimers[sessionId]?.cancel()
        condenseTimers.removeValue(forKey: sessionId)
    }

    private func triggerAlertFlash(_ sessionId: UUID) {
        expandedWithAlert[sessionId] = true
        alertTimers[sessionId]?.cancel()
        alertTimers[sessionId] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2s
            guard !Task.isCancelled, let self else { return }
            withAnimation(.easeOut(duration: 0.3)) {
                self.expandedWithAlert[sessionId] = nil
            }
        }
    }

    // MARK: - Expand All

    private func expandAllSessions() {
        for (sessionId, state) in brewStates {
            if state != .expanded {
                cancelCondenseTimer(sessionId)
                peekTimers[sessionId]?.cancel()
                withAnimation(.easeInOut(duration: 0.2)) {
                    brewStates[sessionId] = .expanded
                    brewStartTimes.removeValue(forKey: sessionId)
                }
            }
        }
        logDebug("Expanded all sessions (brew mode toggled off)", category: .terminal)
    }

    // MARK: - Preview Text

    /// Refresh preview texts for all condensed sessions
    private func refreshPreviewTexts() async {
        let sessionManager = TerminalSessionManager.shared
        let condensedIds = brewStates.filter { $0.value == .condensed }.map(\.key)

        for sessionId in condensedIds {
            await refreshPreviewText(for: sessionId)
            // Small delay between reads to avoid hammering
            guard let _ = sessionManager.terminal(for: sessionId) else { continue }
        }
    }

    /// Snapshot preview text while the terminal is still full-size (before condensing shrinks it to ~3 rows).
    /// Called from startCondenseTimer right before transitioning to .condensed.
    func snapshotPreviewText(for sessionId: UUID) async {
        let sessionManager = TerminalSessionManager.shared
        guard let terminal = sessionManager.terminal(for: sessionId) else { return }

        let text: String? = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let term = terminal.getTerminal()
                let rowCount = term.rows

                var lines: [String] = []
                for row in 0 ..< rowCount {
                    if let bufferLine = term.getLine(row: row) {
                        // translateToString returns \0 for empty cells — replace with spaces
                        let raw = bufferLine.translateToString(trimRight: true)
                        lines.append(raw.replacingOccurrences(of: "\0", with: " "))
                    }
                }

                let preview = Self.extractPreviewFromLines(lines)
                logDebug("PREVIEW-DBG [\(sessionId.uuidString.prefix(8))] snapshot (\(rowCount) rows), preview: \"\(preview)\"", category: .terminal)
                continuation.resume(returning: preview)
            }
        }

        if let text, !text.isEmpty {
            previewTexts[sessionId] = text
        }
    }

    /// Refresh preview from raw buffer stream. Works even when terminal is condensed to tiny height
    /// because getBufferAsData() returns the full PTY history, not just visible rows.
    private func refreshPreviewText(for sessionId: UUID) async {
        let sessionManager = TerminalSessionManager.shared
        guard let terminal = sessionManager.terminal(for: sessionId) else { return }

        let text: String? = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let term = terminal.getTerminal()

                // Try line-by-line first (best quality — proper spacing from rendered grid)
                let rowCount = term.rows
                if rowCount >= 10 {
                    var lines: [String] = []
                    for row in 0 ..< rowCount {
                        if let bufferLine = term.getLine(row: row) {
                            let raw = bufferLine.translateToString(trimRight: true)
                            lines.append(raw.replacingOccurrences(of: "\0", with: " "))
                        }
                    }
                    let preview = Self.extractPreviewFromLines(lines)
                    if !preview.isEmpty {
                        logDebug("PREVIEW-DBG [\(sessionId.uuidString.prefix(8))] line-by-line (\(rowCount) rows): \"\(preview)\"", category: .terminal)
                        continuation.resume(returning: preview)
                        return
                    }
                }

                // Fallback: raw buffer stream (works when condensed to tiny height)
                let data = term.getBufferAsData()
                guard let fullText = String(data: data, encoding: .utf8) else {
                    continuation.resume(returning: nil)
                    return
                }
                let cleaned = String(fullText.suffix(2000))
                    .replacingOccurrences(of: "\0", with: " ")
                let stripped = Self.stripAnsi(cleaned)
                let lines = stripped.components(separatedBy: .newlines)
                let preview = Self.extractPreviewFromLines(lines)
                logDebug("PREVIEW-DBG [\(sessionId.uuidString.prefix(8))] raw-buffer fallback: \"\(preview)\"", category: .terminal)
                continuation.resume(returning: preview)
            }
        }

        if let text, !text.isEmpty {
            previewTexts[sessionId] = text
        }
    }

    // MARK: - Terminal Output Parsing

    /// Characters that indicate a Claude Code status line: ✢ ✳ ✱ ✻ ❋ ✽ *
    private static let statusStarChars: Set<Character> = ["✢", "✳", "✱", "✻", "❋", "✽", "*"]

    /// Characters that indicate a Claude Code action line: ⏺ (U+23FA) or ● (U+25CF)
    private static let actionDotChars: Set<Character> = ["⏺", "●"]

    /// Extract the two key lines from Claude Code's TUI:
    /// 1. Action line: starts with ●/⏺ — shows what Claude is actively doing
    /// 2. Status line: starts with ✢/✳/✱ — shows session name + "(time · tokens · state)"
    static func extractPreviewFromLines(_ lines: [String]) -> String {
        var statusLine: String?
        var actionLine: String?

        // Scan from bottom up to find the most recent status + action lines
        for line in lines.reversed() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            // Skip noise: tips, prompt area, bypass permissions, sub-items (⎿)
            if trimmed.contains("Tip:") || trimmed.contains("Tip :") { continue }
            if trimmed.hasPrefix("❯") { continue }
            if trimmed.contains("bypass") || trimmed.contains("shift+tab") { continue }
            if trimmed.hasPrefix("⎿") || trimmed.hasPrefix("⏵") || trimmed.hasPrefix("▸") { continue }

            if let first = trimmed.first {
                // Status line: ✱ Contemplating… (4m 12s · ↑ 16.9k tokens)
                if statusStarChars.contains(first) && statusLine == nil {
                    statusLine = trimmed
                    continue
                }

                // Action line: ● Reading 1 file… (ctrl+o to expand)
                if actionDotChars.contains(first) && actionLine == nil {
                    actionLine = trimmed
                    continue
                }
            }

            // Once we have both, stop scanning
            if statusLine != nil && actionLine != nil { break }
        }

        // Build preview: action line first (what it's doing), then status line (timing/state)
        var parts: [String] = []
        if let action = actionLine { parts.append(action) }
        if let status = statusLine { parts.append(status) }

        if parts.isEmpty {
            // Fallback: take the last non-empty, non-decorative line
            for line in lines.reversed() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty && !isDecorativeLine(trimmed) &&
                    !trimmed.hasPrefix("❯") && !trimmed.contains("bypass") &&
                    !trimmed.hasPrefix("⎿") && !trimmed.hasPrefix("⏵") && !trimmed.hasPrefix("▸") &&
                    !trimmed.contains("Tip:") && !trimmed.contains("shift+tab") {
                    return String(trimmed.prefix(200))
                }
            }
        }

        return parts.joined(separator: "\n")
    }

    /// Box-drawing and decorative Unicode characters used to detect decorative lines
    private static let decorativeCharSet: CharacterSet = {
        var set = CharacterSet()
        set.insert(charactersIn: Unicode.Scalar(0x2500)! ... Unicode.Scalar(0x257F)!) // Box Drawing
        set.insert(charactersIn: Unicode.Scalar(0x2580)! ... Unicode.Scalar(0x259F)!) // Block Elements
        set.insert(charactersIn: Unicode.Scalar(0x2800)! ... Unicode.Scalar(0x28FF)!) // Braille Patterns
        return set
    }()

    /// Check if a line is purely decorative (box drawing, dashes, etc.)
    private static func isDecorativeLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return true }

        var meaningfulCount = 0
        var totalCount = 0
        for scalar in trimmed.unicodeScalars {
            totalCount += 1
            if !decorativeCharSet.contains(scalar) &&
                scalar != "-" && scalar != "=" && scalar != "_" &&
                scalar != "·" && scalar != ">" && scalar != "<" &&
                scalar != " " {
                meaningfulCount += 1
            }
        }
        return totalCount > 0 && Double(meaningfulCount) / Double(totalCount) < 0.3
    }

    /// Strip ANSI escape codes from terminal output.
    /// CSI sequences replaced with space to preserve word boundaries from cursor movement.
    static func stripAnsi(_ text: String) -> String {
        var result = text

        // Replace CSI sequences with a space (preserves cursor-movement spacing)
        if let csiRegex = try? NSRegularExpression(pattern: #"\x1b\[[0-9;?]*[A-Za-z]"#) {
            result = csiRegex.stringByReplacingMatches(
                in: result, range: NSRange(result.startIndex..., in: result), withTemplate: " "
            )
        }

        // Remove OSC sequences, charset sequences, control chars, carriage returns
        if let otherRegex = try? NSRegularExpression(pattern: #"\x1b\][^\x07]*\x07|\x1b[()][A-Z0-9]|[\x00-\x08\x0b\x0c\x0e-\x1f]|\r"#) {
            result = otherRegex.stringByReplacingMatches(
                in: result, range: NSRange(result.startIndex..., in: result), withTemplate: ""
            )
        }

        // Collapse runs of spaces
        if let spacesRegex = try? NSRegularExpression(pattern: #" {2,}"#) {
            result = spacesRegex.stringByReplacingMatches(
                in: result, range: NSRange(result.startIndex..., in: result), withTemplate: " "
            )
        }

        return result
    }
}

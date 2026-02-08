// TerminalSessionManager.swift
// Manages collection of terminal sessions, active session, and layout mode

import Foundation
import SwiftData
import SwiftTerm

@Observable
@MainActor
final class TerminalSessionManager {
    static let shared = TerminalSessionManager()

    private(set) var sessions: [TerminalSession] = []
    var activeSessionId: UUID?
    var layoutMode: LayoutMode = .single
    let maxSessions: Int = 4 // SESS-06: limit to prevent resource exhaustion
    private var nextSessionNumber: Int = 1

    // Runtime references (cannot be persisted in @Model)
    private(set) var coordinators: [UUID: EmbeddedTerminalView.Coordinator] = [:]
    private(set) var terminals: [UUID: LocalProcessTerminalView] = [:]

    // SwiftData context for persistence
    private var modelContext: ModelContext?

    enum LayoutMode: String, CaseIterable {
        case single // Focus mode (one session fullscreen)
        case horizontalSplit // Side-by-side
        case verticalSplit // Above-and-below
    }

    private init() {}

    /// Configure manager with ModelContext for persistence
    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
        logInfo("TerminalSessionManager configured with ModelContext", category: .terminal)
    }

    var activeSession: TerminalSession? {
        sessions.first { $0.id == activeSessionId }
    }

    var canCreateSession: Bool {
        sessions.count < maxSessions
    }

    @discardableResult
    func createSession(name: String? = nil) -> TerminalSession? {
        guard canCreateSession else {
            logWarning("Cannot create session: max limit (\(maxSessions)) reached", category: .terminal)
            return nil
        }

        let sessionName = name ?? "Session \(nextSessionNumber)"
        nextSessionNumber += 1
        let session = TerminalSession(name: sessionName)
        session.lastActivity = Date()
        sessions.append(session)

        // Persist to database if context available
        if let context = modelContext {
            context.insert(session)
            logInfo("Created session: \(session.name) (\(session.id)) - persisted to database", category: .terminal)
        } else {
            logWarning("Created session: \(session.name) (\(session.id)) - in-memory only (no ModelContext)", category: .terminal)
        }

        // Auto-activate if first session
        if activeSessionId == nil {
            activeSessionId = session.id
        }

        return session
    }

    /// Create a session that resumes an existing Claude Code session
    /// - Parameter claudeSession: The Claude Code session to resume
    /// - Returns: The created terminal session, or nil if max sessions reached
    @discardableResult
    func createResumeSession(claudeSession: ClaudeCodeSession) -> TerminalSession? {
        guard canCreateSession else {
            logWarning("Cannot create session: max limit (\(maxSessions)) reached", category: .terminal)
            return nil
        }

        // Use truncated first prompt as session name, with fallback
        let sessionName: String
        let prompt = claudeSession.firstPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if prompt.isEmpty {
            sessionName = "Resumed \(nextSessionNumber)"
        } else if prompt.count <= 30 {
            sessionName = prompt
        } else {
            sessionName = String(prompt.prefix(27)) + "..."
        }
        nextSessionNumber += 1

        let session = TerminalSession(
            name: sessionName,
            claudeSessionId: claudeSession.sessionId,
            workingDirectory: claudeSession.projectPath
        )
        session.updateActivity()
        sessions.append(session)

        // Persist to database if context available
        if let context = modelContext {
            context.insert(session)
            logInfo("Created resume session: \(session.name) for Claude session \(claudeSession.sessionId) - persisted", category: .terminal)
        } else {
            logWarning("Created resume session: \(session.name) for Claude session \(claudeSession.sessionId) - in-memory only", category: .terminal)
        }

        // Auto-activate if first session
        if activeSessionId == nil {
            activeSessionId = session.id
        }

        return session
    }

    func closeSession(_ sessionId: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionId }) else {
            logWarning("Cannot close session: \(sessionId) not found", category: .terminal)
            return
        }

        let session = sessions[index]
        logInfo("Closing session: \(session.name)", category: .terminal)

        // Remove from runtime dictionaries
        coordinators.removeValue(forKey: sessionId)
        terminals.removeValue(forKey: sessionId)

        // Delete from database if context available
        if let context = modelContext {
            context.delete(session)
        }

        sessions.remove(at: index)

        // If active session closed, select another
        if activeSessionId == sessionId {
            activeSessionId = sessions.first?.id
            logDebug("Active session changed to: \(activeSessionId?.uuidString ?? "none")", category: .terminal)
        }
    }

    func setActiveSession(_ sessionId: UUID) {
        guard sessions.contains(where: { $0.id == sessionId }) else {
            logWarning("Cannot activate session: \(sessionId) not found", category: .terminal)
            return
        }
        activeSessionId = sessionId
        logDebug("Active session set to: \(sessionId)", category: .terminal)
    }

    func toggleLayoutMode() {
        switch layoutMode {
        case .single:
            layoutMode = .horizontalSplit
        case .horizontalSplit:
            layoutMode = .verticalSplit
        case .verticalSplit:
            layoutMode = .single
        }
        logDebug("Layout mode changed to: \(layoutMode.rawValue)", category: .terminal)
    }

    func setLayoutMode(_ mode: LayoutMode) {
        layoutMode = mode
        logDebug("Layout mode set to: \(mode.rawValue)", category: .terminal)
    }

    // MARK: - Runtime Reference Management

    func setCoordinator(_ coordinator: EmbeddedTerminalView.Coordinator, for sessionId: UUID) {
        coordinators[sessionId] = coordinator
        logDebug("Set coordinator for session: \(sessionId)", category: .terminal)
    }

    func setTerminal(_ terminal: LocalProcessTerminalView, for sessionId: UUID) {
        terminals[sessionId] = terminal
        logDebug("Set terminal for session: \(sessionId)", category: .terminal)
    }

    func coordinator(for sessionId: UUID) -> EmbeddedTerminalView.Coordinator? {
        coordinators[sessionId]
    }

    func terminal(for sessionId: UUID) -> LocalProcessTerminalView? {
        terminals[sessionId]
    }

    func updateSessionActivity(_ sessionId: UUID) {
        guard let session = sessions.first(where: { $0.id == sessionId }) else {
            logWarning("Cannot update activity: session \(sessionId) not found", category: .terminal)
            return
        }
        session.updateActivity()
        logDebug("Updated activity for session: \(sessionId)", category: .terminal)
    }
}

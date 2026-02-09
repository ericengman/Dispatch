// TerminalSessionManager.swift
// Manages collection of terminal sessions, active session, and layout mode

import AppKit
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
    private(set) var statusMonitors: [UUID: SessionStatusMonitor] = [:]

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
    func createSession(name: String? = nil, workingDirectory: String? = nil) -> TerminalSession? {
        guard canCreateSession else {
            logWarning("Cannot create session: max limit (\(maxSessions)) reached", category: .terminal)
            return nil
        }

        let sessionName = name ?? "Session \(nextSessionNumber)"
        nextSessionNumber += 1
        let session = TerminalSession(name: sessionName, workingDirectory: workingDirectory)
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

        // Start status monitoring for resumed sessions with Claude session ID
        startStatusMonitoring(for: session)

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

        // Stop status monitoring before cleanup
        stopStatusMonitoring(for: sessionId)

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

        // Focus the terminal for immediate keyboard input
        focusTerminal(sessionId)
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

        // Auto-focus the terminal if this is the active session
        if sessionId == activeSessionId {
            // Delay slightly to ensure view is in window hierarchy
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.focusTerminal(sessionId)
            }
        }
    }

    /// Focus the terminal for the given session, making it the first responder
    func focusTerminal(_ sessionId: UUID) {
        guard let terminal = terminals[sessionId] else {
            logDebug("Cannot focus terminal: not found for session \(sessionId)", category: .terminal)
            return
        }

        // Use SwiftTerm's makeFirstResponder method
        terminal.window?.makeFirstResponder(terminal)
        logDebug("Focused terminal for session: \(sessionId)", category: .terminal)
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

    // MARK: - Status Monitor Management

    /// Start JSONL status monitoring for a session with Claude session ID
    /// - Parameter session: The terminal session to monitor
    func startStatusMonitoring(for session: TerminalSession) {
        guard let claudeSessionId = session.claudeSessionId,
              let claudeUUID = UUID(uuidString: claudeSessionId),
              let workingDirectory = session.workingDirectory
        else {
            logDebug("Cannot start status monitoring: session missing claudeSessionId or workingDirectory", category: .status)
            return
        }

        let monitor = SessionStatusMonitor()
        monitor.startMonitoring(sessionId: claudeUUID, workingDirectory: workingDirectory)
        statusMonitors[session.id] = monitor
        logInfo("Started status monitoring for session: \(session.id)", category: .status)
    }

    /// Stop JSONL status monitoring for a session
    /// - Parameter sessionId: The terminal session ID to stop monitoring
    func stopStatusMonitoring(for sessionId: UUID) {
        guard let monitor = statusMonitors[sessionId] else { return }
        monitor.stopMonitoring()
        statusMonitors.removeValue(forKey: sessionId)
        logInfo("Stopped status monitoring for session: \(sessionId)", category: .status)
    }

    /// Get the status monitor for a session
    /// - Parameter sessionId: The terminal session ID
    /// - Returns: The SessionStatusMonitor if monitoring is active
    func statusMonitor(for sessionId: UUID) -> SessionStatusMonitor? {
        statusMonitors[sessionId]
    }

    // MARK: - Persistence Management

    /// Load persisted sessions from SwiftData on app launch
    /// Returns sessions sorted by lastActivity (most recent first)
    func loadPersistedSessions() -> [TerminalSession] {
        guard let modelContext = modelContext else {
            logWarning("Cannot load sessions: modelContext not configured", category: .terminal)
            return []
        }

        var descriptor = FetchDescriptor<TerminalSession>(
            sortBy: [SortDescriptor(\.lastActivity, order: .reverse)]
        )
        // Limit to sessions from last 7 days
        let cutoff = Date().addingTimeInterval(-7 * 24 * 3600)
        descriptor.predicate = #Predicate { $0.lastActivity > cutoff }

        do {
            let sessions = try modelContext.fetch(descriptor)
            logInfo("Loaded \(sessions.count) persisted sessions", category: .terminal)
            return sessions
        } catch {
            logError("Failed to load persisted sessions: \(error)", category: .terminal)
            return []
        }
    }

    /// Associate session with Project by matching workingDirectory to Project.path
    /// - Parameter session: The session to associate
    /// - Returns: The associated Project, if found
    @discardableResult
    func associateWithProject(_ session: TerminalSession) -> Project? {
        guard let workingDirectory = session.workingDirectory,
              let modelContext = modelContext
        else {
            return nil
        }

        // Fetch projects with matching path
        var descriptor = FetchDescriptor<Project>()
        descriptor.predicate = #Predicate { $0.path == workingDirectory }

        do {
            let projects = try modelContext.fetch(descriptor)
            if let project = projects.first {
                session.project = project
                logInfo("Associated session '\(session.name)' with project '\(project.name)'", category: .terminal)
                return project
            }
        } catch {
            logError("Failed to find project for path \(workingDirectory): \(error)", category: .terminal)
        }

        return nil
    }

    /// Resume a persisted session by adding it to active sessions
    /// - Parameter session: The persisted TerminalSession from SwiftData
    /// - Returns: true if resumed, false if max sessions reached
    @discardableResult
    func resumePersistedSession(_ session: TerminalSession) -> Bool {
        guard canCreateSession else {
            logWarning("Cannot resume session: max limit reached", category: .terminal)
            return false
        }

        // Add to active sessions array
        sessions.append(session)

        // Update activity timestamp
        session.updateActivity()

        // Auto-activate if first session
        if activeSessionId == nil {
            activeSessionId = session.id
        }

        logInfo("Resumed persisted session: \(session.name) (\(session.id))", category: .terminal)
        return true
    }

    /// Remove sessions older than specified days from SwiftData
    /// - Parameter olderThanDays: Delete sessions with lastActivity older than this many days
    func cleanupStaleSessions(olderThanDays: Int = 7) {
        guard let modelContext = modelContext else { return }

        let cutoff = Date().addingTimeInterval(-Double(olderThanDays) * 24 * 3600)
        var descriptor = FetchDescriptor<TerminalSession>()
        descriptor.predicate = #Predicate { $0.lastActivity < cutoff }

        do {
            let staleSessions = try modelContext.fetch(descriptor)
            for session in staleSessions {
                modelContext.delete(session)
                logDebug("Deleted stale session: \(session.name)", category: .terminal)
            }
            if !staleSessions.isEmpty {
                logInfo("Cleaned up \(staleSessions.count) stale sessions", category: .terminal)
            }
        } catch {
            logError("Failed to cleanup stale sessions: \(error)", category: .terminal)
        }
    }

    /// Check if a Claude Code session ID is still valid (file exists)
    /// - Parameter sessionId: The Claude session ID to verify
    /// - Parameter workingDirectory: The project path for the session
    /// - Returns: true if session file exists, false if stale/deleted
    func isClaudeSessionValid(sessionId: String, workingDirectory: String?) async -> Bool {
        guard let workingDirectory = workingDirectory else {
            // Can't verify without path - assume valid
            return true
        }

        // Use discovery service to check if session exists
        let sessions = await ClaudeSessionDiscoveryService.shared.discoverSessions(for: workingDirectory)
        return sessions.contains { $0.sessionId == sessionId }
    }

    /// Handle failed session resume by clearing stale Claude session ID
    /// Called when Claude Code reports session not found
    /// Note: User must close and reopen the terminal to launch fresh - clearing the ID
    /// just prevents future resume attempts with the invalid session
    func handleStaleSession(_ sessionId: UUID) {
        guard let session = sessions.first(where: { $0.id == sessionId }) else { return }

        logWarning("Session '\(session.name)' was stale, clearing Claude session ID", category: .terminal)

        // Clear the stale Claude session ID so it won't try to resume again
        session.claudeSessionId = nil
        session.updateActivity()

        // Note: The terminal will need to be recreated to launch fresh
        // User can close and reopen the terminal tab
    }
}

// TerminalSessionManager.swift
// Manages collection of terminal sessions and active session tracking

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

    let maxSessions: Int = 4 // SESS-06: limit to prevent resource exhaustion
    private var nextSessionNumber: Int = 1
    private(set) var hasRestoredSessions = false

    // Per-project active session tracking
    private var activeSessionPerProject: [String: UUID] = [:]

    // Per-session pane heights for stack layout
    var sessionHeights: [UUID: CGFloat] = [:]

    // Visible terminal area height (set by GeometryReader, read by tab bar presets)
    var terminalAreaHeight: CGFloat = 0

    // Runtime references (cannot be persisted in @Model)
    private(set) var coordinators: [UUID: EmbeddedTerminalView.Coordinator] = [:]
    private(set) var terminals: [UUID: LocalProcessTerminalView] = [:]
    private(set) var statusMonitors: [UUID: SessionStatusMonitor] = [:]

    // SwiftData context for persistence
    private var modelContext: ModelContext?

    private init() {
        // Load per-project active sessions from UserDefaults
        if let saved = UserDefaults.standard.dictionary(forKey: "activeSessionPerProject") as? [String: String] {
            activeSessionPerProject = saved.compactMapValues { UUID(uuidString: $0) }
            logDebug("Loaded \(activeSessionPerProject.count) per-project active session(s)", category: .terminal)
        }

        // Load per-session pane heights from UserDefaults
        if let saved = UserDefaults.standard.dictionary(forKey: "terminalSessionHeights") as? [String: Double] {
            sessionHeights = saved.compactMapValues { CGFloat($0) }
                .reduce(into: [UUID: CGFloat]()) { result, pair in
                    if let uuid = UUID(uuidString: pair.key) {
                        result[uuid] = pair.value
                    }
                }
            logDebug("Loaded \(sessionHeights.count) persisted pane height(s)", category: .terminal)
        }
    }

    /// Persist per-project active session map to UserDefaults
    private func saveActiveSessionPerProject() {
        let stringMap = activeSessionPerProject.mapValues { $0.uuidString }
        UserDefaults.standard.set(stringMap, forKey: "activeSessionPerProject")
    }

    /// Get height for a session, returning default if not set
    func heightForSession(_ id: UUID) -> CGFloat {
        sessionHeights[id] ?? 400
    }

    /// Set height for a session and persist
    func setSessionHeight(_ height: CGFloat, for id: UUID) {
        sessionHeights[id] = height
        saveSessionHeights()
    }

    /// Persist session heights to UserDefaults
    func saveSessionHeights() {
        let stringMap = sessionHeights.reduce(into: [String: Double]()) { result, pair in
            result[pair.key.uuidString] = Double(pair.value)
        }
        UserDefaults.standard.set(stringMap, forKey: "terminalSessionHeights")
    }

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
        // Note: Do NOT set session.lastActivity here - init already sets both createdAt
        // and lastActivity to Date(). Setting lastActivity again would make lastActivity > createdAt,
        // which causes launchMode to return .claudeCodeContinue instead of .claudeCode (fresh start).

        // Set initial height to the average of existing sessions in the same project
        if let workingDirectory {
            let projectSessions = sessionsForProject(id: nil, path: workingDirectory)
            if !projectSessions.isEmpty {
                let avgHeight = projectSessions.reduce(CGFloat(0)) { $0 + heightForSession($1.id) } / CGFloat(projectSessions.count)
                sessionHeights[session.id] = avgHeight
                saveSessionHeights()
                logDebug("Set new session height to average: \(avgHeight)", category: .terminal)
            }
        }

        sessions.append(session)

        // Persist to database if context available
        if let context = modelContext {
            context.insert(session)
            logInfo("Created session: \(session.name) (\(session.id)) - persisted to database", category: .terminal)
        } else {
            logWarning("Created session: \(session.name) (\(session.id)) - in-memory only (no ModelContext)", category: .terminal)
        }

        // Auto-associate with project if working directory provided
        if workingDirectory != nil {
            associateWithProject(session)
        }

        // Activate the new session
        setActiveSession(session.id)

        // Ensure periodic lsof refresh is running
        startSessionIdRefresh()

        return session
    }

    /// Create a session that resumes an existing Claude Code session
    /// - Parameter claudeSession: The Claude Code session to resume
    /// - Returns: The created terminal session, or nil if max sessions reached
    @discardableResult
    func createResumeSession(claudeSession: ClaudeCodeSession) -> TerminalSession? {
        logInfo("RESUME-DBG createResumeSession called with claudeSession.sessionId=\(claudeSession.sessionId), projectPath=\(claudeSession.projectPath)", category: .terminal)

        guard canCreateSession else {
            logWarning("RESUME-DBG createResumeSession BLOCKED: max limit (\(maxSessions)) reached, current=\(sessions.count)", category: .terminal)
            return nil
        }

        // Check if a session with this Claude session ID is already active
        if let existing = sessions.first(where: { $0.claudeSessionId == claudeSession.sessionId }) {
            logWarning("RESUME-DBG createResumeSession DUPLICATE: Claude session \(claudeSession.sessionId) already active as '\(existing.name)' (id=\(existing.id))", category: .terminal)
            activeSessionId = existing.id
            return existing
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
        logInfo("RESUME-DBG createResumeSession created TerminalSession name='\(sessionName)', claudeSessionId=\(session.claudeSessionId ?? "NIL!"), workingDir=\(session.workingDirectory ?? "nil")", category: .terminal)

        // Set initial height to the average of existing sessions in the same project
        let resumeProjectPath = claudeSession.projectPath
        let existingProjectSessions = sessionsForProject(id: nil, path: resumeProjectPath)
        if !existingProjectSessions.isEmpty {
            let avgHeight = existingProjectSessions.reduce(CGFloat(0)) { $0 + heightForSession($1.id) } / CGFloat(existingProjectSessions.count)
            sessionHeights[session.id] = avgHeight
            saveSessionHeights()
            logDebug("Set resumed session height to average: \(avgHeight)", category: .terminal)
        }

        sessions.append(session)

        // Persist to database if context available
        if let context = modelContext {
            context.insert(session)
            logInfo("Created resume session: \(session.name) for Claude session \(claudeSession.sessionId) - persisted", category: .terminal)
        } else {
            logWarning("Created resume session: \(session.name) for Claude session \(claudeSession.sessionId) - in-memory only", category: .terminal)
        }

        // Auto-associate with project if working directory provided
        if session.workingDirectory != nil {
            associateWithProject(session)
        }

        // Start status monitoring for resumed sessions with Claude session ID
        startStatusMonitoring(for: session)

        // Activate the new session
        setActiveSession(session.id)

        return session
    }

    func closeSession(_ sessionId: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionId }) else {
            logWarning("Cannot close session: \(sessionId) not found", category: .terminal)
            return
        }

        let session = sessions[index]
        let projectPath = session.workingDirectory
        logInfo("Closing session: \(session.name)", category: .terminal)

        // Stop status monitoring before cleanup
        stopStatusMonitoring(for: sessionId)

        // Clean up brew mode state
        BrewModeController.shared.cleanupSession(sessionId)

        // Remove from runtime dictionaries
        coordinators.removeValue(forKey: sessionId)
        terminals.removeValue(forKey: sessionId)
        if sessionHeights.removeValue(forKey: sessionId) != nil {
            saveSessionHeights()
        }

        // Delete from database if context available
        if let context = modelContext {
            context.delete(session)
        }

        sessions.remove(at: index)

        // If active session closed, select next session in the same project
        if activeSessionId == sessionId {
            if let path = projectPath {
                let projectSessions = sessionsForProject(id: nil, path: path)
                activeSessionId = projectSessions.first?.id
                activeSessionPerProject[path] = activeSessionId
                saveActiveSessionPerProject()
            } else {
                activeSessionId = sessions.first?.id
            }
            logDebug("Active session changed to: \(activeSessionId?.uuidString ?? "none")", category: .terminal)
        }
    }

    func setActiveSession(_ sessionId: UUID) {
        guard let session = sessions.first(where: { $0.id == sessionId }) else {
            logWarning("Cannot activate session: \(sessionId) not found", category: .terminal)
            return
        }
        activeSessionId = sessionId
        UserDefaults.standard.set(sessionId.uuidString, forKey: "activeTerminalSessionId")

        // Track per-project active session
        if let path = session.workingDirectory {
            activeSessionPerProject[path] = sessionId
            saveActiveSessionPerProject()
        }

        logDebug("Active session set to: \(sessionId)", category: .terminal)

        // Focus the terminal for immediate keyboard input
        focusTerminal(sessionId)
    }

    /// Cycle to the next or previous terminal session within the current project
    func cycleActiveSession(forward: Bool) {
        guard let active = activeSession, let path = active.workingDirectory else { return }
        let projectSessions = sessionsForProject(id: nil, path: path)
        guard projectSessions.count >= 2 else { return }
        guard let currentIndex = projectSessions.firstIndex(where: { $0.id == activeSessionId }) else { return }
        let nextIndex = forward
            ? (currentIndex + 1) % projectSessions.count
            : (currentIndex - 1 + projectSessions.count) % projectSessions.count
        setActiveSession(projectSessions[nextIndex].id)
        logDebug("Cycled to \(forward ? "next" : "previous") session: \(projectSessions[nextIndex].name)", category: .terminal)
    }

    // MARK: - Per-Project Session Management

    /// Switch to a project, restoring the last-active session for that project
    func switchToProject(path: String) {
        if let savedId = activeSessionPerProject[path],
           sessions.contains(where: { $0.id == savedId }) {
            activeSessionId = savedId
            logDebug("Restored active session \(savedId) for project: \(path)", category: .terminal)
        } else {
            // Fallback to first session in this project
            let projectSessions = sessionsForProject(id: nil, path: path)
            activeSessionId = projectSessions.first?.id
            logDebug("Set active session to first for project: \(path) (\(activeSessionId?.uuidString ?? "none"))", category: .terminal)
        }
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
            logInfo("RESUME-DBG loadPersistedSessions: fetched \(sessions.count) session(s) from SwiftData", category: .terminal)
            for (i, session) in sessions.enumerated() {
                logInfo("RESUME-DBG loadPersistedSessions [\(i)]: name='\(session.name)', id=\(session.id), claudeSessionId=\(session.claudeSessionId ?? "nil"), workingDir=\(session.workingDirectory ?? "nil"), lastActivity=\(session.lastActivity)", category: .terminal)
            }
            return sessions
        } catch {
            logError("RESUME-DBG loadPersistedSessions: FETCH FAILED: \(error)", category: .terminal)
            return []
        }
    }

    /// Find sessions matching a project by SwiftData relationship or working directory path fallback
    /// - Parameters:
    ///   - projectId: The Project's UUID
    ///   - projectPath: The project's filesystem path for fallback matching
    /// - Returns: Sessions matching the project
    func sessionsForProject(id projectId: UUID?, path projectPath: String?) -> [TerminalSession] {
        // Primary: match by SwiftData project relationship
        if let projectId {
            let byRelationship = sessions.filter { $0.project?.id == projectId }
            if !byRelationship.isEmpty {
                return byRelationship
            }
        }

        // Fallback: match by working directory path (normalized, no trailing slash)
        guard let projectPath, !projectPath.isEmpty else { return [] }
        let normalizedPath = projectPath.hasSuffix("/") ? String(projectPath.dropLast()) : projectPath
        return sessions.filter { session in
            guard let wd = session.workingDirectory else { return false }
            let normalizedWd = wd.hasSuffix("/") ? String(wd.dropLast()) : wd
            return normalizedWd == normalizedPath
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
        logInfo("RESUME-DBG resumePersistedSession: '\(session.name)' (id=\(session.id)), claudeSessionId=\(session.claudeSessionId ?? "nil"), wasRestored=\(session.wasRestoredFromPersistence)", category: .terminal)

        guard canCreateSession else {
            logWarning("RESUME-DBG resumePersistedSession BLOCKED: max limit reached (\(sessions.count)/\(maxSessions))", category: .terminal)
            return false
        }

        guard !sessions.contains(where: { $0.id == session.id }) else {
            logWarning("RESUME-DBG resumePersistedSession SKIPPED: already active '\(session.name)' (\(session.id))", category: .terminal)
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

        logInfo("RESUME-DBG resumePersistedSession SUCCESS: '\(session.name)' — claudeSessionId=\(session.claudeSessionId ?? "nil"), wasRestored=\(session.wasRestoredFromPersistence)", category: .terminal)
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

    /// Check if a Claude Code session ID is still valid (.jsonl file exists on disk)
    /// - Parameter sessionId: The Claude session ID to verify
    /// - Parameter workingDirectory: The project path for the session
    /// - Returns: true if session .jsonl file exists, false if stale/deleted
    func isClaudeSessionValid(sessionId: String, workingDirectory: String?) async -> Bool {
        guard let workingDirectory = workingDirectory else {
            return true
        }

        let escapedPath = workingDirectory.replacingOccurrences(of: "/", with: "-")
        let jsonlPath = NSHomeDirectory() + "/.claude/projects/" + escapedPath + "/" + sessionId + ".jsonl"
        return FileManager.default.fileExists(atPath: jsonlPath)
    }

    // MARK: - PID-based Session Detection (lsof)

    /// Find which .jsonl session file a process (or its descendants) has open.
    /// Uses `lsof` to create a deterministic PID → file mapping, eliminating race conditions
    /// when multiple terminals launch simultaneously.
    /// Nonisolated so it can run off the main actor via Task.detached.
    nonisolated static func findOpenJsonlSessionId(pid: pid_t, workingDirectory: String) -> String? {
        guard pid > 0 else { return nil }

        let escapedPath = workingDirectory.replacingOccurrences(of: "/", with: "-")
        let expectedDir = NSHomeDirectory() + "/.claude/projects/" + escapedPath + "/"

        // Collect PID and all descendant PIDs (Claude Code may fork child processes)
        var allPids = [pid]
        allPids.append(contentsOf: getDescendantPids(parentPid: pid))

        let pidList = allPids.map(String.init).joined(separator: ",")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-p", pidList, "-Fn"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        for line in output.components(separatedBy: "\n") {
            guard line.hasPrefix("n") else { continue }
            let path = String(line.dropFirst())
            guard path.hasPrefix(expectedDir), path.hasSuffix(".jsonl") else { continue }

            let filename = (path as NSString).lastPathComponent
            let sessionId = String(filename.dropLast(6)) // Remove ".jsonl"
            if UUID(uuidString: sessionId) != nil {
                return sessionId
            }
        }

        return nil
    }

    /// Get all descendant process IDs for a parent PID.
    /// Used to find child processes that may hold .jsonl files open.
    nonisolated static func getDescendantPids(parentPid: pid_t) -> [pid_t] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-P", "\(parentPid)"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return []
        }

        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return output.components(separatedBy: "\n").compactMap {
            pid_t($0.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    /// Periodically refresh session IDs by checking which .jsonl files are open.
    /// Catches cases where Claude Code creates a new session mid-conversation
    /// (e.g., context compaction, /clear, etc.)
    private var refreshTask: Task<Void, Never>?

    func startSessionIdRefresh() {
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000) // 30s
                guard !Task.isCancelled else { return }
                await self?.refreshSessionIdsFromProcesses()
            }
        }
        logDebug("Started periodic session ID refresh (every 30s)", category: .terminal)
    }

    func stopSessionIdRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
        logDebug("Stopped periodic session ID refresh", category: .terminal)
    }

    private func refreshSessionIdsFromProcesses() async {
        let processInfos: [(sessionId: UUID, pid: pid_t, workingDirectory: String)] = sessions.compactMap { session in
            guard let terminal = terminals[session.id],
                  let workDir = session.workingDirectory else { return nil }
            let pid = terminal.process.shellPid
            guard pid > 0 else { return nil }
            return (session.id, pid, workDir)
        }

        guard !processInfos.isEmpty else { return }

        // Run lsof off main actor
        let results: [(UUID, String)] = await Task.detached {
            processInfos.compactMap { info in
                if let detectedId = Self.findOpenJsonlSessionId(pid: info.pid, workingDirectory: info.workingDirectory) {
                    return (info.sessionId, detectedId)
                }
                return nil
            }
        }.value

        // Update changed IDs
        var updated = false
        for (sessionId, claudeSessionId) in results {
            if let session = sessions.first(where: { $0.id == sessionId }),
               session.claudeSessionId != claudeSessionId {
                logInfo("RESUME-DBG refresh: updating session '\(session.name)' claudeSessionId from \(session.claudeSessionId ?? "nil") to \(claudeSessionId)", category: .terminal)
                session.claudeSessionId = claudeSessionId
                updated = true
            }
        }

        if updated {
            do {
                try modelContext?.save()
                logDebug("Persisted refreshed session IDs", category: .terminal)
            } catch {
                logError("Failed to persist refreshed session IDs: \(error)", category: .terminal)
            }
        }
    }

    /// Detect and store the Claude session ID for a freshly launched session.
    /// Uses lsof to deterministically map the terminal's PID to its open .jsonl file.
    /// Falls back to filesystem scanning if lsof fails (e.g., file opened/closed quickly).
    /// - Parameters:
    ///   - sessionId: The TerminalSession UUID
    ///   - workingDirectory: The project path to search for Claude sessions
    func detectClaudeSessionId(for sessionId: UUID, workingDirectory: String) {
        Task {
            logInfo("RESUME-DBG detectClaudeSessionId: starting lsof-based detection for terminalSession=\(sessionId), workingDir=\(workingDirectory)", category: .terminal)

            // Phase 1: lsof-based detection (deterministic, PID-correlated)
            // Poll every 2s for up to 30s (15 attempts)
            for attempt in 1 ... 15 {
                try? await Task.sleep(nanoseconds: 2_000_000_000)

                let pid = terminals[sessionId]?.process.shellPid ?? 0
                guard pid > 0 else {
                    logInfo("RESUME-DBG detectClaudeSessionId: attempt \(attempt) — no PID yet for session \(sessionId)", category: .terminal)
                    continue
                }

                // Run lsof off main actor to avoid blocking UI
                let detectedId = await Task.detached {
                    Self.findOpenJsonlSessionId(pid: pid, workingDirectory: workingDirectory)
                }.value

                if let detectedId {
                    storeDetectedSessionId(detectedId, for: sessionId, method: "lsof PID \(pid) (attempt \(attempt))")
                    return
                }

                logInfo("RESUME-DBG detectClaudeSessionId: attempt \(attempt)/15 — lsof found no .jsonl for PID \(pid) + descendants", category: .terminal)
            }

            // Phase 2: Fallback to filesystem scanning (probabilistic, creation-time-based)
            logWarning("RESUME-DBG detectClaudeSessionId: lsof failed after 15 attempts, falling back to filesystem scan for session \(sessionId)", category: .terminal)
            let currentlyClaimed = Set(sessions.compactMap(\.claudeSessionId))
            let recentCutoff = Date().addingTimeInterval(-60) // Files created in the last minute

            if let fsSessionId = scanFileSystemForNewSession(workingDirectory: workingDirectory, after: recentCutoff, excluding: currentlyClaimed) {
                storeDetectedSessionId(fsSessionId, for: sessionId, method: "filesystem fallback")
                return
            }

            logWarning("RESUME-DBG detectClaudeSessionId: ALL detection methods failed for session \(sessionId)", category: .terminal)
        }
    }

    /// Store a detected Claude session ID on a terminal session and persist it
    private func storeDetectedSessionId(_ claudeSessionId: String, for terminalSessionId: UUID, method: String) {
        guard let session = sessions.first(where: { $0.id == terminalSessionId }) else {
            logWarning("RESUME-DBG storeDetectedSessionId: session \(terminalSessionId) no longer exists — skipping", category: .terminal)
            return
        }

        logInfo("RESUME-DBG storeDetectedSessionId: setting claudeSessionId=\(claudeSessionId) on session '\(session.name)' (id=\(terminalSessionId)) via \(method)", category: .terminal)
        session.claudeSessionId = claudeSessionId

        // Persist immediately so session ID survives unexpected quit
        do {
            try modelContext?.save()
            logInfo("RESUME-DBG storeDetectedSessionId: persisted to SwiftData successfully", category: .terminal)
        } catch {
            logError("RESUME-DBG storeDetectedSessionId: FAILED to persist: \(error)", category: .terminal)
        }

        // Start status monitoring now that we have the session ID
        startStatusMonitoring(for: session)
    }

    /// Mark session restoration as complete so views don't re-trigger it
    func markRestorationComplete() {
        hasRestoredSessions = true
        logDebug("Session restoration marked complete", category: .terminal)
    }

    /// Restore the previously active session from UserDefaults after loading persisted sessions
    func restoreActiveSession() {
        guard let savedIdString = UserDefaults.standard.string(forKey: "activeTerminalSessionId"),
              let savedId = UUID(uuidString: savedIdString),
              sessions.contains(where: { $0.id == savedId })
        else {
            logDebug("No saved active session to restore", category: .terminal)
            return
        }
        activeSessionId = savedId
        logInfo("Restored active session: \(savedId)", category: .terminal)
    }

    /// Restore all persisted sessions from SwiftData on app launch.
    /// Validates claudeSessionId for each, adds valid ones to the active array,
    /// and marks restoration complete. Does NOT set activeSessionId — that happens
    /// per-project via `switchToProject()`.
    func restoreAllPersistedSessions() {
        guard !hasRestoredSessions else {
            logInfo("RESUME-DBG restoreAllPersistedSessions SKIPPED: already restored", category: .terminal)
            return
        }
        markRestorationComplete()

        let persistedSessions = loadPersistedSessions()
        logInfo("RESUME-DBG restoreAllPersistedSessions: loaded \(persistedSessions.count) persisted session(s)", category: .terminal)
        guard !persistedSessions.isEmpty else {
            logInfo("RESUME-DBG restoreAllPersistedSessions: no persisted sessions to restore", category: .terminal)
            return
        }

        // Pre-validate each session's claudeSessionId
        for session in persistedSessions {
            logInfo("RESUME-DBG validating session '\(session.name)' (id=\(session.id)): claudeSessionId=\(session.claudeSessionId ?? "nil"), workingDir=\(session.workingDirectory ?? "nil")", category: .terminal)
            if !validateSessionId(session) {
                logWarning("RESUME-DBG VALIDATION FAILED for '\(session.name)': clearing claudeSessionId=\(session.claudeSessionId ?? "nil")", category: .terminal)
                session.claudeSessionId = nil
            } else {
                logInfo("RESUME-DBG VALIDATION PASSED for '\(session.name)': keeping claudeSessionId=\(session.claudeSessionId ?? "nil")", category: .terminal)
            }
        }

        // Recovery: for sessions with nil claudeSessionId, try to find recently modified
        // .jsonl files from the previous run and assign them. This handles the case where
        // detection failed in a prior run (e.g., after upgrading detection code).
        recoverMissingSessionIds(for: persistedSessions)

        // Mark as restored so launchMode returns fresh start when ID is gone
        for session in persistedSessions {
            session.wasRestoredFromPersistence = true
        }

        // Resume all persisted sessions (adds to active array)
        var restoredCount = 0
        for session in persistedSessions {
            logInfo("RESUME-DBG resuming persisted session '\(session.name)': claudeSessionId=\(session.claudeSessionId ?? "nil")", category: .terminal)
            if resumePersistedSession(session) {
                associateWithProject(session)
                restoredCount += 1
            }
        }

        logInfo("RESUME-DBG Restored \(restoredCount) persisted session(s) from SwiftData", category: .terminal)

        // Start periodic lsof-based session ID refresh
        if restoredCount > 0 {
            startSessionIdRefresh()
        }

        // Cleanup stale sessions in background
        Task.detached {
            await MainActor.run {
                self.cleanupStaleSessions(olderThanDays: 7)
            }
        }
    }

    /// Save all sessions to SwiftData before app quit.
    /// Performs a final lsof-based session ID check to ensure stored IDs are accurate.
    func saveAllSessions() {
        guard let modelContext = modelContext else {
            logWarning("RESUME-DBG saveAllSessions: no modelContext — cannot save!", category: .terminal)
            return
        }

        stopSessionIdRefresh()

        logInfo("RESUME-DBG saveAllSessions: saving \(sessions.count) session(s)", category: .terminal)

        // Final lsof-based session ID check for all sessions with live terminals
        for session in sessions {
            if let terminal = terminals[session.id],
               let workDir = session.workingDirectory {
                let pid = terminal.process.shellPid
                if pid > 0,
                   let detectedId = Self.findOpenJsonlSessionId(pid: pid, workingDirectory: workDir) {
                    if session.claudeSessionId != detectedId {
                        logInfo("RESUME-DBG saveAllSessions: lsof updated '\(session.name)' claudeSessionId from \(session.claudeSessionId ?? "nil") to \(detectedId)", category: .terminal)
                        session.claudeSessionId = detectedId
                    }
                }
            }

            logInfo("RESUME-DBG saveAllSessions: session '\(session.name)' (id=\(session.id)) claudeSessionId=\(session.claudeSessionId ?? "nil"), workingDir=\(session.workingDirectory ?? "nil")", category: .terminal)
            session.lastActivity = Date()
        }

        do {
            try modelContext.save()
            logInfo("RESUME-DBG saveAllSessions: successfully saved \(sessions.count) sessions to SwiftData", category: .terminal)
        } catch {
            logError("RESUME-DBG saveAllSessions: FAILED to save: \(error)", category: .terminal)
        }
    }

    /// Recover missing claudeSessionIds for restored sessions by matching them to
    /// recently modified .jsonl files from the previous run. Groups sessions by
    /// working directory and assigns the most recently modified unclaimed .jsonl files.
    private func recoverMissingSessionIds(for persistedSessions: [TerminalSession]) {
        // Group sessions needing IDs by working directory
        let needingIds = persistedSessions.filter { $0.claudeSessionId == nil && $0.workingDirectory != nil }
        guard !needingIds.isEmpty else {
            logInfo("RESUME-DBG recoverMissingSessionIds: no sessions need recovery", category: .terminal)
            return
        }

        logInfo("RESUME-DBG recoverMissingSessionIds: \(needingIds.count) session(s) need ID recovery", category: .terminal)

        // Collect already-claimed IDs
        var claimedIds = Set(persistedSessions.compactMap(\.claudeSessionId))

        // Group by working directory
        let grouped = Dictionary(grouping: needingIds, by: { $0.workingDirectory! })

        for (workingDir, sessionsInDir) in grouped {
            let escapedPath = workingDir.replacingOccurrences(of: "/", with: "-")
            let projectDir = NSHomeDirectory() + "/.claude/projects/" + escapedPath
            let fm = FileManager.default

            guard let contents = try? fm.contentsOfDirectory(atPath: projectDir) else { continue }

            // Find .jsonl files modified within the last 30 minutes, sorted by modification time (most recent first)
            let cutoff = Date().addingTimeInterval(-1800) // 30 minutes
            var recentFiles: [(sessionId: String, modified: Date)] = []

            for entry in contents where entry.hasSuffix(".jsonl") {
                let sessionId = String(entry.dropLast(6))
                guard UUID(uuidString: sessionId) != nil else { continue }
                guard !claimedIds.contains(sessionId) else { continue }

                let fullPath = projectDir + "/" + entry
                if let attrs = try? fm.attributesOfItem(atPath: fullPath),
                   let modified = attrs[.modificationDate] as? Date,
                   modified > cutoff {
                    recentFiles.append((sessionId: sessionId, modified: modified))
                }
            }

            // Sort by most recently modified first
            recentFiles.sort { $0.modified > $1.modified }

            // Assign the most recent unclaimed .jsonl files to sessions
            for (index, session) in sessionsInDir.enumerated() {
                guard index < recentFiles.count else {
                    logWarning("RESUME-DBG recoverMissingSessionIds: no more .jsonl files for '\(session.name)' — will start fresh", category: .terminal)
                    break
                }

                let recovered = recentFiles[index]
                session.claudeSessionId = recovered.sessionId
                claimedIds.insert(recovered.sessionId)
                logInfo("RESUME-DBG recoverMissingSessionIds: assigned \(recovered.sessionId) to '\(session.name)' (modified \(recovered.modified))", category: .terminal)
            }
        }

        // Persist recovered IDs
        do {
            try modelContext?.save()
            logInfo("RESUME-DBG recoverMissingSessionIds: persisted recovered IDs to SwiftData", category: .terminal)
        } catch {
            logError("RESUME-DBG recoverMissingSessionIds: failed to persist: \(error)", category: .terminal)
        }
    }

    /// Scan the Claude projects directory for session .jsonl files or folders created after the given date.
    /// Returns the most recently created session ID not in the exclusion set.
    private func scanFileSystemForNewSession(workingDirectory: String, after cutoff: Date, excluding existingIds: Set<String>) -> String? {
        let escapedPath = workingDirectory.replacingOccurrences(of: "/", with: "-")
        let projectDir = NSHomeDirectory() + "/.claude/projects/" + escapedPath
        let fm = FileManager.default

        guard let contents = try? fm.contentsOfDirectory(atPath: projectDir) else { return nil }

        var candidates: [(sessionId: String, created: Date)] = []
        for entry in contents {
            let fullPath = projectDir + "/" + entry

            // Check UUID-named .jsonl files (primary — this is how Claude Code stores sessions)
            if entry.hasSuffix(".jsonl") {
                let sessionId = String(entry.dropLast(6)) // Remove ".jsonl"
                guard UUID(uuidString: sessionId) != nil else { continue }
                guard !existingIds.contains(sessionId) else { continue }

                if let attrs = try? fm.attributesOfItem(atPath: fullPath),
                   let created = attrs[.creationDate] as? Date,
                   created > cutoff {
                    candidates.append((sessionId: sessionId, created: created))
                }
                continue
            }

            // Also check UUID-named directories (legacy session folders)
            guard UUID(uuidString: entry) != nil else { continue }
            guard !existingIds.contains(entry) else { continue }

            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: fullPath, isDirectory: &isDir), isDir.boolValue else { continue }

            if let attrs = try? fm.attributesOfItem(atPath: fullPath),
               let created = attrs[.creationDate] as? Date,
               created > cutoff {
                candidates.append((sessionId: entry, created: created))
            }
        }

        // Return most recently created
        return candidates.sorted(by: { $0.created > $1.created }).first?.sessionId
    }

    /// Validate a persisted session's claudeSessionId by checking if its .jsonl file exists.
    /// Returns true if the session file is found (valid), false if stale.
    /// Synchronous - safe to call during app launch.
    func validateSessionId(_ session: TerminalSession) -> Bool {
        guard let claudeSessionId = session.claudeSessionId,
              let workingDirectory = session.workingDirectory
        else {
            logInfo("RESUME-DBG validateSessionId: no claudeSessionId or workingDirectory for '\(session.name)' — returning true (nothing to validate)", category: .terminal)
            return true
        }

        let escapedPath = workingDirectory.replacingOccurrences(of: "/", with: "-")
        let projectDir = NSHomeDirectory() + "/.claude/projects/" + escapedPath
        let jsonlPath = projectDir + "/" + claudeSessionId + ".jsonl"

        logInfo("RESUME-DBG validateSessionId: checking jsonlPath=\(jsonlPath)", category: .terminal)

        let isValid = FileManager.default.fileExists(atPath: jsonlPath)
        if isValid {
            logInfo("RESUME-DBG validateSessionId: FOUND \(claudeSessionId).jsonl — VALID", category: .terminal)
        } else {
            logWarning("RESUME-DBG validateSessionId: \(claudeSessionId).jsonl NOT FOUND — INVALID", category: .terminal)
        }
        return isValid
    }

    /// Handle failed session resume by clearing stale Claude session ID
    /// Called when Claude Code reports session not found
    /// Note: User must close and reopen the terminal to launch fresh - clearing the ID
    /// just prevents future resume attempts with the invalid session
    func handleStaleSession(_ sessionId: UUID) {
        guard let session = sessions.first(where: { $0.id == sessionId }) else {
            logWarning("RESUME-DBG handleStaleSession: session \(sessionId) not found in active sessions", category: .terminal)
            return
        }

        logWarning("RESUME-DBG handleStaleSession: session '\(session.name)' (id=\(sessionId)) was STALE — clearing claudeSessionId=\(session.claudeSessionId ?? "nil")", category: .terminal)

        // Clear the stale Claude session ID so it won't try to resume again
        session.claudeSessionId = nil
        session.updateActivity()

        // Note: The terminal will need to be recreated to launch fresh
        // User can close and reopen the terminal tab
    }
}

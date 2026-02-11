//
//  ClaudeSessionDiscoveryService.swift
//  Dispatch
//
//  Discovers and loads Claude Code sessions from ~/.claude/projects/
//  Enables session resumption to save tokens
//

import Foundation

/// Actor that discovers Claude Code sessions from the filesystem
actor ClaudeSessionDiscoveryService {
    static let shared = ClaudeSessionDiscoveryService()

    private let claudeProjectsPath: String
    private let fileManager = FileManager.default

    private init() {
        claudeProjectsPath = NSHomeDirectory() + "/.claude/projects"
    }

    // MARK: - Public API

    /// Discover all sessions for a given project path
    /// - Parameter projectPath: The original project path (e.g., "/Users/eric/Dispatch")
    /// - Returns: Sessions sorted by modified date (most recent first)
    func discoverSessions(for projectPath: String) async -> [ClaudeCodeSession] {
        let escapedPath = escapePathForClaudeDirectory(projectPath)
        let projectDir = claudeProjectsPath + "/" + escapedPath
        let indexPath = projectDir + "/sessions-index.json"

        logInfo("RESUME-DBG discoverSessions: projectPath=\(projectPath), escapedPath=\(escapedPath), indexPath=\(indexPath)", category: .terminal)

        guard fileManager.fileExists(atPath: indexPath) else {
            logInfo("RESUME-DBG discoverSessions: sessions-index.json NOT FOUND at \(indexPath)", category: .terminal)
            return []
        }

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: indexPath))
            let index = try JSONDecoder().decode(ClaudeSessionsIndex.self, from: data)

            logInfo("RESUME-DBG discoverSessions: raw entries count=\(index.entries.count)", category: .terminal)
            for entry in index.entries {
                logInfo("RESUME-DBG discoverSessions:   entry sessionId=\(entry.sessionId), isSidechain=\(entry.isSidechain), modified=\(entry.modified), prompt='\(entry.firstPrompt.prefix(40))'", category: .terminal)
            }

            // Filter out sidechains and sort by modified (most recent first)
            let sessions = index.entries
                .filter { !$0.isSidechain }
                .sorted { $0.modified > $1.modified }

            logInfo("RESUME-DBG discoverSessions: after filtering sidechains: \(sessions.count) sessions for \(projectPath)", category: .terminal)
            return sessions

        } catch {
            logError("RESUME-DBG discoverSessions: FAILED to parse sessions-index.json: \(error)", category: .terminal)
            return []
        }
    }

    /// Get recent sessions for a project (within specified time window)
    /// - Parameters:
    ///   - projectPath: The project path to search
    ///   - maxCount: Maximum number of sessions to return
    ///   - withinHours: Only include sessions modified within this many hours (default 168 = 1 week)
    /// - Returns: Recent sessions sorted by modified date
    func getRecentSessions(
        for projectPath: String,
        maxCount: Int = 10,
        withinHours: Int = 168
    ) async -> [ClaudeCodeSession] {
        let allSessions = await discoverSessions(for: projectPath)
        let cutoffDate = Date().addingTimeInterval(-Double(withinHours) * 3600)

        let recentSessions = allSessions
            .filter { $0.modified > cutoffDate }
            .prefix(maxCount)

        logDebug("Found \(recentSessions.count) recent sessions (within \(withinHours)h)", category: .terminal)
        return Array(recentSessions)
    }

    /// Discover sessions across all known projects
    /// - Parameter maxPerProject: Maximum sessions per project
    /// - Returns: Dictionary of project path to sessions
    func discoverAllProjectSessions(maxPerProject: Int = 5) async -> [String: [ClaudeCodeSession]] {
        var results: [String: [ClaudeCodeSession]] = [:]

        guard fileManager.fileExists(atPath: claudeProjectsPath) else {
            logDebug("Claude projects directory not found: \(claudeProjectsPath)", category: .terminal)
            return results
        }

        do {
            let projectDirs = try fileManager.contentsOfDirectory(atPath: claudeProjectsPath)

            for dir in projectDirs {
                // Skip non-directory entries
                var isDir: ObjCBool = false
                let fullPath = claudeProjectsPath + "/" + dir
                guard fileManager.fileExists(atPath: fullPath, isDirectory: &isDir), isDir.boolValue else {
                    continue
                }

                // Unescape the directory name to get original project path
                let originalPath = unescapeClaudeDirectoryPath(dir)

                let sessions = await getRecentSessions(for: originalPath, maxCount: maxPerProject)
                if !sessions.isEmpty {
                    results[originalPath] = sessions
                }
            }

        } catch {
            logError("Failed to enumerate Claude projects: \(error)", category: .terminal)
        }

        return results
    }

    // MARK: - Path Escaping

    /// Escape a path for Claude's directory naming convention
    /// Replaces "/" with "-" (e.g., "/Users/eric/Dispatch" -> "-Users-eric-Dispatch")
    private func escapePathForClaudeDirectory(_ path: String) -> String {
        path.replacingOccurrences(of: "/", with: "-")
    }

    /// Unescape a Claude directory name back to original path
    /// Replaces leading "-" and all "-" with "/" (e.g., "-Users-eric-Dispatch" -> "/Users/eric/Dispatch")
    private func unescapeClaudeDirectoryPath(_ escapedPath: String) -> String {
        // The escaped path starts with "-" which represents the leading "/"
        // All other "-" also represent "/"
        escapedPath.replacingOccurrences(of: "-", with: "/")
    }
}

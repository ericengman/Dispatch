//
//  ClaudeFile.swift
//  Dispatch
//
//  Model for CLAUDE.md configuration files
//

import AppKit
import Combine
import Foundation

// MARK: - Claude File Scope

enum ClaudeFileScope: String, Sendable, Identifiable, CaseIterable {
    case system = "System"
    case project = "Project"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .system: return "globe"
        case .project: return "folder"
        }
    }

    var description: String {
        switch self {
        case .system: return "Global settings for all projects"
        case .project: return "Project-specific settings"
        }
    }
}

// MARK: - Claude File

nonisolated struct ClaudeFile: Identifiable, Hashable, Sendable {
    let id: UUID
    let scope: ClaudeFileScope
    let filePath: URL
    let projectPath: URL?

    init(
        id: UUID = UUID(),
        scope: ClaudeFileScope,
        filePath: URL,
        projectPath: URL? = nil
    ) {
        self.id = id
        self.scope = scope
        self.filePath = filePath
        self.projectPath = projectPath
    }

    /// Display name for the file
    var displayName: String {
        switch scope {
        case .system:
            return "System CLAUDE.md"
        case .project:
            return "Project CLAUDE.md"
        }
    }

    /// Short name for card display
    var shortName: String {
        switch scope {
        case .system:
            return "System"
        case .project:
            return "Project"
        }
    }

    /// Whether the file exists on disk
    var exists: Bool {
        FileManager.default.fileExists(atPath: filePath.path)
    }

    /// Read the file content
    func readContent() -> String? {
        guard exists else { return nil }
        return try? String(contentsOf: filePath, encoding: .utf8)
    }

    /// Write content to the file
    func writeContent(_ content: String) throws {
        // Create parent directory if needed
        let parentDir = filePath.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: parentDir.path) {
            try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
        }
        try content.write(to: filePath, atomically: true, encoding: .utf8)
    }

    /// Open the file in the default editor
    func openInEditor() {
        NSWorkspace.shared.open(filePath)
    }
}

// MARK: - Claude File Discovery Service

actor ClaudeFileDiscoveryService {
    static let shared = ClaudeFileDiscoveryService()

    private let fileManager = FileManager.default

    // System CLAUDE.md location - ~/.claude/CLAUDE.md
    private var systemClaudeFilePath: URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")
            .appendingPathComponent("CLAUDE.md")
    }

    private init() {}

    // MARK: - Discovery

    /// Gets the system CLAUDE.md file
    func getSystemClaudeFile() -> ClaudeFile {
        return ClaudeFile(
            scope: .system,
            filePath: systemClaudeFilePath,
            projectPath: nil
        )
    }

    /// Gets the project CLAUDE.md file for a given project path
    /// Checks both project/CLAUDE.md and project/.claude/CLAUDE.md
    func getProjectClaudeFile(at projectPath: URL) -> ClaudeFile? {
        // Check project root first
        let rootPath = projectPath.appendingPathComponent("CLAUDE.md")
        if fileManager.fileExists(atPath: rootPath.path) {
            return ClaudeFile(
                scope: .project,
                filePath: rootPath,
                projectPath: projectPath
            )
        }

        // Check .claude directory
        let dotClaudePath = projectPath
            .appendingPathComponent(".claude")
            .appendingPathComponent("CLAUDE.md")

        // Return the .claude path even if it doesn't exist (for creation)
        return ClaudeFile(
            scope: .project,
            filePath: dotClaudePath,
            projectPath: projectPath
        )
    }

    /// Gets all CLAUDE.md files (system + project if available)
    func getAllClaudeFiles(projectPath: URL?) async -> [ClaudeFile] {
        var files: [ClaudeFile] = []

        // Always include system file
        files.append(getSystemClaudeFile())

        // Include project file if project path is provided
        if let projectPath = projectPath,
           let projectFile = getProjectClaudeFile(at: projectPath) {
            files.append(projectFile)
        }

        return files
    }
}

// MARK: - Claude File Manager (MainActor)

@MainActor
final class ClaudeFileManager: ObservableObject {
    static let shared = ClaudeFileManager()

    // MARK: - Published Properties

    @Published private(set) var systemFile: ClaudeFile?
    @Published private(set) var projectFile: ClaudeFile?
    @Published private(set) var isLoading: Bool = false
    @Published var selectedProjectPath: URL?

    // MARK: - Initialization

    private init() {}

    // MARK: - Computed Properties

    var hasFiles: Bool {
        systemFile != nil || projectFile != nil
    }

    var allFiles: [ClaudeFile] {
        var files: [ClaudeFile] = []
        if let systemFile = systemFile {
            files.append(systemFile)
        }
        if let projectFile = projectFile {
            files.append(projectFile)
        }
        return files
    }

    // MARK: - Loading

    /// Loads CLAUDE.md files
    func loadFiles(for projectPath: URL? = nil) async {
        isLoading = true
        selectedProjectPath = projectPath

        // Load system file
        systemFile = await ClaudeFileDiscoveryService.shared.getSystemClaudeFile()

        // Load project file if path provided
        if let path = projectPath {
            projectFile = await ClaudeFileDiscoveryService.shared.getProjectClaudeFile(at: path)
        } else {
            projectFile = nil
        }

        isLoading = false
    }

    /// Refreshes files
    func refresh() async {
        await loadFiles(for: selectedProjectPath)
    }
}

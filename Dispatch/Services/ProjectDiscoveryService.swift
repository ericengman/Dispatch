//
//  ProjectDiscoveryService.swift
//  Dispatch
//
//  Service for discovering Claude Code projects by finding directories with CLAUDE.md files
//

import Foundation
import Combine

// MARK: - Discovered Project

struct DiscoveredProject: Identifiable, Hashable, Sendable {
    let id: UUID
    let name: String
    let path: URL
    let claudeFilePath: URL
    let lastModified: Date?

    init(path: URL, claudeFilePath: URL) {
        self.id = UUID()
        self.name = path.lastPathComponent
        self.path = path
        self.claudeFilePath = claudeFilePath

        // Get last modified date
        if let attrs = try? FileManager.default.attributesOfItem(atPath: claudeFilePath.path),
           let modDate = attrs[.modificationDate] as? Date {
            self.lastModified = modDate
        } else {
            self.lastModified = nil
        }
    }
}

// MARK: - Project Discovery Service

actor ProjectDiscoveryService {
    static let shared = ProjectDiscoveryService()

    // MARK: - Properties

    private let fileManager = FileManager.default
    private let claudeFileName = "CLAUDE.md"
    private let claudeFileNameLower = "claude.md"

    // Default search paths
    private var searchPaths: [URL] = []

    // MARK: - Initialization

    private init() {
        // Set up default search paths
        let home = fileManager.homeDirectoryForCurrentUser
        searchPaths = [
            home.appendingPathComponent("Developer"),
            home.appendingPathComponent("Projects"),
            home.appendingPathComponent("Code"),
            home.appendingPathComponent("Documents"),
            home.appendingPathComponent("Desktop"),
            home
        ]

    }

    // MARK: - Configuration

    /// Sets custom search paths
    func setSearchPaths(_ paths: [URL]) {
        searchPaths = paths
        logInfo("Updated search paths to \(paths.count) locations", category: .data)
    }

    /// Adds a search path
    func addSearchPath(_ path: URL) {
        if !searchPaths.contains(path) {
            searchPaths.append(path)
            logDebug("Added search path: \(path.path)", category: .data)
        }
    }

    // MARK: - Discovery

    /// Discovers all projects with CLAUDE.md files
    func discoverProjects(maxDepth: Int = 4) async -> [DiscoveredProject] {
        let perf = PerformanceLogger("discoverProjects", category: .data)
        defer { perf.end() }

        var discovered: [DiscoveredProject] = []
        var visitedPaths: Set<String> = []

        logInfo("Starting project discovery in \(searchPaths.count) locations", category: .data)

        for searchPath in searchPaths {
            guard fileManager.fileExists(atPath: searchPath.path) else {
                logDebug("Search path doesn't exist: \(searchPath.path)", category: .data)
                continue
            }

            let found = await scanDirectory(searchPath, currentDepth: 0, maxDepth: maxDepth, visited: &visitedPaths)
            discovered.append(contentsOf: found)
        }

        // Remove duplicates (same path)
        let uniqueProjects = Dictionary(grouping: discovered) { $0.path.path }
            .compactMapValues { $0.first }
            .values
            .sorted { ($0.lastModified ?? .distantPast) > ($1.lastModified ?? .distantPast) }

        logInfo("Discovered \(uniqueProjects.count) projects with CLAUDE.md files", category: .data)

        return Array(uniqueProjects)
    }

    /// Scans a specific directory for CLAUDE.md files
    func scanDirectory(_ url: URL, currentDepth: Int, maxDepth: Int, visited: inout Set<String>) async -> [DiscoveredProject] {
        // Check depth limit
        guard currentDepth < maxDepth else { return [] }

        // Avoid revisiting
        let canonicalPath = url.standardizedFileURL.path
        guard !visited.contains(canonicalPath) else { return [] }
        visited.insert(canonicalPath)

        // Skip hidden directories and common non-project directories
        let name = url.lastPathComponent
        if name.hasPrefix(".") ||
           name == "node_modules" ||
           name == "Pods" ||
           name == "Carthage" ||
           name == "build" ||
           name == "Build" ||
           name == "DerivedData" ||
           name == ".git" ||
           name == "vendor" ||
           name == "venv" ||
           name == "__pycache__" {
            return []
        }

        var results: [DiscoveredProject] = []

        // Check for CLAUDE.md in this directory
        let claudeFilePath = url.appendingPathComponent(claudeFileName)
        let claudeFilePathLower = url.appendingPathComponent(claudeFileNameLower)

        if fileManager.fileExists(atPath: claudeFilePath.path) {
            let project = DiscoveredProject(path: url, claudeFilePath: claudeFilePath)
            results.append(project)
            logDebug("Found project: \(project.name) at \(url.path)", category: .data)
            // Don't recurse into discovered projects
            return results
        } else if fileManager.fileExists(atPath: claudeFilePathLower.path) {
            let project = DiscoveredProject(path: url, claudeFilePath: claudeFilePathLower)
            results.append(project)
            logDebug("Found project: \(project.name) at \(url.path)", category: .data)
            return results
        }

        // Recursively scan subdirectories
        do {
            let contents = try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])

            for item in contents {
                var isDirectory: ObjCBool = false
                if fileManager.fileExists(atPath: item.path, isDirectory: &isDirectory), isDirectory.boolValue {
                    let subResults = await scanDirectory(item, currentDepth: currentDepth + 1, maxDepth: maxDepth, visited: &visited)
                    results.append(contentsOf: subResults)
                }
            }
        } catch {
            // Silently ignore permission errors and other issues
            logDebug("Cannot scan directory \(url.path): \(error.localizedDescription)", category: .data)
        }

        return results
    }

    /// Quickly checks if a specific path contains a CLAUDE.md file
    func hasClaudeFile(at path: URL) -> Bool {
        let claudeFilePath = path.appendingPathComponent(claudeFileName)
        let claudeFilePathLower = path.appendingPathComponent(claudeFileNameLower)
        return fileManager.fileExists(atPath: claudeFilePath.path) ||
               fileManager.fileExists(atPath: claudeFilePathLower.path)
    }

    /// Gets the CLAUDE.md content for a project
    func getClaudeFileContent(at path: URL) -> String? {
        let claudeFilePath = path.appendingPathComponent(claudeFileName)
        let claudeFilePathLower = path.appendingPathComponent(claudeFileNameLower)

        if let content = try? String(contentsOf: claudeFilePath, encoding: .utf8) {
            return content
        }
        if let content = try? String(contentsOf: claudeFilePathLower, encoding: .utf8) {
            return content
        }
        return nil
    }
}

// MARK: - Project Discovery Manager (MainActor)

/// MainActor wrapper for UI integration
@MainActor
final class ProjectDiscoveryManager: ObservableObject {
    static let shared = ProjectDiscoveryManager()

    // MARK: - Published Properties

    @Published private(set) var discoveredProjects: [DiscoveredProject] = []
    @Published private(set) var isScanning: Bool = false
    @Published private(set) var lastScanDate: Date?
    @Published var error: String?

    // MARK: - Initialization

    private init() {
    }

    // MARK: - Discovery

    /// Scans for projects with CLAUDE.md files
    func scanForProjects(maxDepth: Int = 4) async {
        guard !isScanning else {
            logWarning("Scan already in progress", category: .data)
            return
        }

        isScanning = true
        error = nil

        logInfo("Starting project scan", category: .data)

        let projects = await ProjectDiscoveryService.shared.discoverProjects(maxDepth: maxDepth)

        discoveredProjects = projects
        lastScanDate = Date()
        isScanning = false

        logInfo("Scan complete: found \(projects.count) projects", category: .data)
    }

    /// Syncs discovered projects to the app's project list
    func syncToAppProjects(context: ModelContext) async {
        logInfo("Syncing \(discoveredProjects.count) discovered projects to app", category: .data)

        // Get existing projects
        let descriptor = FetchDescriptor<Project>()
        let existingProjects = (try? context.fetch(descriptor)) ?? []
        let existingNames = Set(existingProjects.map { $0.name.lowercased() })

        var addedCount = 0

        for discovered in discoveredProjects {
            // Skip if project with same name already exists
            if existingNames.contains(discovered.name.lowercased()) {
                logDebug("Project '\(discovered.name)' already exists, skipping", category: .data)
                continue
            }

            // Create new project with the file system path
            let project = Project(
                name: discovered.name,
                colorHex: ProjectColor.allCases.randomElement()?.hex ?? ProjectColor.blue.hex,
                sortOrder: existingProjects.count + addedCount,
                path: discovered.path.path
            )

            context.insert(project)
            addedCount += 1

            logInfo("Added project: '\(discovered.name)'", category: .data)
        }

        if addedCount > 0 {
            do {
                try context.save()
                logInfo("Synced \(addedCount) new projects", category: .data)
            } catch {
                self.error = error.localizedDescription
                logError("Failed to save synced projects: \(error)", category: .data)
            }
        } else {
            logInfo("No new projects to sync", category: .data)
        }
    }

    /// Refreshes the discovered project for a specific path
    func refreshProject(at path: URL) async -> DiscoveredProject? {
        let hasClaudeFile = await ProjectDiscoveryService.shared.hasClaudeFile(at: path)
        guard hasClaudeFile else { return nil }

        let claudeFilePath = path.appendingPathComponent("CLAUDE.md")
        return DiscoveredProject(path: path, claudeFilePath: claudeFilePath)
    }
}

// MARK: - SwiftData Import

import SwiftData

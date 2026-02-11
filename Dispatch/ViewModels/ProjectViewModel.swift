//
//  ProjectViewModel.swift
//  Dispatch
//
//  ViewModel for managing projects
//

import AppKit
import Combine
import Foundation
import SwiftData
import UniformTypeIdentifiers

// MARK: - Project ViewModel

@MainActor
final class ProjectViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var projects: [Project] = []
    @Published var selectedProject: Project?
    @Published var isLoading: Bool = false
    @Published var error: String?

    // MARK: - Private Properties

    private var modelContext: ModelContext?

    // MARK: - Singleton

    static let shared = ProjectViewModel()

    private init() {}

    func configure(with context: ModelContext) {
        modelContext = context
        fetchProjects()

        // Automatically discover and sync Claude Code projects on startup
        Task {
            await discoverAndSyncProjects()
            await discoverProjectIcons()
        }
    }

    /// Discovers Claude Code projects and syncs them to the app
    func discoverAndSyncProjects() async {
        guard let context = modelContext else { return }

        logInfo("Starting automatic project discovery", category: .data)

        // Discover projects with CLAUDE.md files
        let discovered = await ProjectDiscoveryService.shared.discoverProjects(maxDepth: 4)

        guard !discovered.isEmpty else {
            logDebug("No Claude Code projects discovered", category: .data)
            return
        }

        logInfo("Discovered \(discovered.count) Claude Code projects", category: .data)

        // Get existing project paths to avoid duplicates
        let existingPaths = Set(projects.compactMap { $0.path })

        var addedCount = 0

        for discoveredProject in discovered {
            let projectPath = discoveredProject.path.path

            // Skip if we already have this path
            if existingPaths.contains(projectPath) {
                continue
            }

            // Skip if a project with the same name exists (but update its path)
            if let existingProject = projects.first(where: { $0.name.lowercased() == discoveredProject.name.lowercased() }) {
                if existingProject.path == nil {
                    existingProject.path = projectPath
                    logDebug("Updated path for existing project '\(existingProject.name)'", category: .data)
                }
                continue
            }

            // Create new project
            let sortOrder = (projects.map(\.sortOrder).max() ?? -1) + 1
            let project = Project(
                name: discoveredProject.name,
                colorHex: ProjectColor.allCases.randomElement()?.hex ?? ProjectColor.blue.hex,
                sortOrder: sortOrder,
                path: projectPath
            )

            context.insert(project)
            addedCount += 1

            logInfo("Added discovered project: '\(discoveredProject.name)'", category: .data)
        }

        if addedCount > 0 {
            do {
                try context.save()
                await MainActor.run {
                    self.fetchProjects()
                }
                logInfo("Synced \(addedCount) new projects from file system", category: .data)
            } catch {
                logError("Failed to save discovered projects: \(error)", category: .data)
            }
        }
    }

    // MARK: - Fetch

    func fetchProjects() {
        guard let context = modelContext else {
            logError("ModelContext not configured", category: .data)
            return
        }

        isLoading = true

        do {
            var descriptor = FetchDescriptor<Project>()
            descriptor.sortBy = [SortDescriptor(\.sortOrder), SortDescriptor(\.name)]

            projects = try context.fetch(descriptor)
            isLoading = false
            logDebug("Fetched \(projects.count) projects", category: .data)

        } catch {
            self.error = error.localizedDescription
            isLoading = false
            logError("Failed to fetch projects: \(error)", category: .data)
        }
    }

    // MARK: - CRUD Operations

    /// Creates a new project
    func createProject(name: String, color: ProjectColor = .blue) -> Project? {
        guard let context = modelContext else {
            logError("ModelContext not configured", category: .data)
            return nil
        }

        // Check for duplicate name
        if projects.contains(where: { $0.name.lowercased() == name.lowercased() }) {
            error = "A project with this name already exists"
            logWarning("Duplicate project name: \(name)", category: .data)
            return nil
        }

        let sortOrder = (projects.map(\.sortOrder).max() ?? -1) + 1

        let project = Project(
            name: name,
            colorHex: color.hex,
            sortOrder: sortOrder
        )

        context.insert(project)

        do {
            try context.save()
            fetchProjects()
            logInfo("Created project: '\(name)'", category: .data)
            return project
        } catch {
            self.error = error.localizedDescription
            logError("Failed to create project: \(error)", category: .data)
            return nil
        }
    }

    /// Updates a project
    func updateProject(_ project: Project, name: String? = nil, color: ProjectColor? = nil) {
        if let name = name {
            // Check for duplicate name
            if projects.contains(where: { $0.id != project.id && $0.name.lowercased() == name.lowercased() }) {
                error = "A project with this name already exists"
                return
            }
            project.name = name
        }

        if let color = color {
            project.updateColor(color)
        }

        saveContext()
        objectWillChange.send()
        logDebug("Updated project: '\(project.name)'", category: .data)
    }

    /// Deletes a project (prompts become unassigned)
    func deleteProject(_ project: Project) {
        guard let context = modelContext else { return }

        // Don't delete the "General" project if it's the last one
        if projects.count == 1, project.name == "General" {
            error = "Cannot delete the last project"
            return
        }

        context.delete(project)

        if selectedProject?.id == project.id {
            selectedProject = nil
        }

        saveContext()
        fetchProjects()

        logInfo("Deleted project: '\(project.name)'", category: .data)
    }

    /// Reorders projects
    func moveProject(from sourceIndex: Int, to destinationIndex: Int) {
        guard sourceIndex != destinationIndex else { return }
        guard sourceIndex < projects.count, destinationIndex < projects.count else { return }

        var reordered = projects
        let project = reordered.remove(at: sourceIndex)
        reordered.insert(project, at: destinationIndex)

        // Update sort orders
        for (index, proj) in reordered.enumerated() {
            proj.sortOrder = index
        }

        saveContext()
        fetchProjects()

        logDebug("Moved project from \(sourceIndex) to \(destinationIndex)", category: .data)
    }

    // MARK: - Selection

    func selectProject(_ project: Project?) {
        selectedProject = project
        if let project = project {
            logDebug("Selected project: '\(project.name)'", category: .ui)
        }
    }

    // MARK: - Default Project

    /// Gets the default project (first project)
    func getDefaultProject() -> Project? {
        projects.first
    }

    /// Refreshes projects by re-scanning the file system
    func refreshProjects() async {
        await discoverAndSyncProjects()
    }

    /// Opens a project's folder in Finder
    func openInFinder(_ project: Project) {
        guard let pathURL = project.pathURL else {
            logWarning("Project '\(project.name)' has no file path", category: .data)
            return
        }

        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: pathURL.path)
        logDebug("Opened project folder: \(pathURL.path)", category: .data)
    }

    /// Opens a project in a new embedded terminal session
    func openInTerminal(_ project: Project) {
        guard let pathURL = project.pathURL else {
            logWarning("Project '\(project.name)' has no file path", category: .data)
            return
        }

        let sessionManager = TerminalSessionManager.shared

        // Check session limit
        guard sessionManager.canCreateSession else {
            logWarning("Cannot create terminal session: max limit reached", category: .data)
            return
        }

        // Create session with project name
        if let session = sessionManager.createSession(name: project.name) {
            // Set working directory for the session
            session.workingDirectory = pathURL.path

            // Associate session with project
            session.project = project

            // Make it the active session
            sessionManager.setActiveSession(session.id)

            logInfo("Created embedded terminal for project: \(project.name)", category: .data)
        } else {
            logError("Failed to create terminal session for project: \(project.name)", category: .data)
        }
    }

    // MARK: - Icon Management

    /// Discovers app icons for all projects with file paths
    func discoverProjectIcons() async {
        let projectsToScan = projects.filter { $0.path != nil && !$0.isCustomIcon }

        guard !projectsToScan.isEmpty else { return }

        logInfo("Discovering icons for \(projectsToScan.count) projects", category: .data)

        for project in projectsToScan {
            guard let path = project.path else { continue }

            let iconData = await AppIconDiscoveryService.shared.discoverIcon(at: path)
            if let iconData {
                project.iconData = iconData
                logDebug("Set auto-discovered icon for '\(project.name)'", category: .data)
            }
        }

        saveContext()
        objectWillChange.send()
    }

    /// Opens a file picker to set a custom icon for a project
    func setCustomIcon(for project: Project) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .icns]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose an icon for \"\(project.name)\""

        guard panel.runModal() == .OK, let url = panel.url else { return }

        guard let image = NSImage(contentsOf: url) else {
            logWarning("Failed to load image from: \(url.path)", category: .data)
            return
        }

        guard let pngData = resizeImageToPNG(image, size: NSSize(width: 128, height: 128)) else {
            logWarning("Failed to resize image for project icon", category: .data)
            return
        }

        project.iconData = pngData
        project.isCustomIcon = true
        saveContext()
        objectWillChange.send()

        logInfo("Set custom icon for project '\(project.name)'", category: .data)
    }

    /// Clears a custom icon and re-runs auto-discovery
    func clearCustomIcon(for project: Project) {
        project.iconData = nil
        project.isCustomIcon = false
        saveContext()
        objectWillChange.send()

        logInfo("Cleared custom icon for project '\(project.name)'", category: .data)

        // Re-run discovery for this project
        Task {
            guard let path = project.path else { return }
            let iconData = await AppIconDiscoveryService.shared.discoverIcon(at: path)
            if let iconData {
                project.iconData = iconData
                saveContext()
                objectWillChange.send()
            }
        }
    }

    /// Resizes an image to the target size and returns PNG data
    private func resizeImageToPNG(_ image: NSImage, size: NSSize) -> Data? {
        let resized = NSImage(size: size)
        resized.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(
            in: NSRect(origin: .zero, size: size),
            from: NSRect(origin: .zero, size: image.size),
            operation: .copy,
            fraction: 1.0
        )
        resized.unlockFocus()

        guard let tiffData = resized.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:])
        else {
            return nil
        }

        return pngData
    }

    // MARK: - Computed Properties

    var count: Int {
        projects.count
    }

    var isEmpty: Bool {
        projects.isEmpty
    }

    // MARK: - Private

    private func saveContext() {
        guard let context = modelContext else { return }

        do {
            try context.save()
        } catch {
            self.error = error.localizedDescription
            logError("Failed to save context: \(error)", category: .data)
        }
    }
}

// MARK: - Project Extensions

extension ProjectViewModel {
    /// Gets a project by ID
    func project(withId id: UUID) -> Project? {
        projects.first { $0.id == id }
    }

    /// Gets prompts for a specific project
    func prompts(for project: Project) -> [Prompt] {
        project.prompts
    }

    /// Gets chains for a specific project
    func chains(for project: Project) -> [PromptChain] {
        project.chains
    }
}

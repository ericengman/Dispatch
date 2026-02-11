//
//  ScreenshotWatcherService.swift
//  Dispatch
//
//  Watches for new simulator screenshots and manages run records
//

import Combine
import Foundation
import SwiftData

// MARK: - Screenshot Directory Configuration

nonisolated struct ScreenshotDirectoryConfig: Sendable {
    /// Base directory for all screenshots
    let baseDirectory: URL

    /// Maximum runs to keep per project
    let maxRunsPerProject: Int

    init(
        baseDirectory: URL? = nil,
        maxRunsPerProject: Int = 10
    ) {
        self.baseDirectory = baseDirectory ?? Self.defaultBaseDirectory
        self.maxRunsPerProject = maxRunsPerProject
    }

    static var defaultBaseDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Dispatch/Screenshots", isDirectory: true)
    }

    /// Gets the directory for a specific project
    func projectDirectory(for projectName: String) -> URL {
        baseDirectory.appendingPathComponent(sanitizeDirectoryName(projectName), isDirectory: true)
    }

    /// Gets the directory for a specific run within a project
    func runDirectory(for runId: UUID, in projectName: String) -> URL {
        projectDirectory(for: projectName).appendingPathComponent(runId.uuidString, isDirectory: true)
    }

    /// Sanitizes a project name for use as a directory name
    private func sanitizeDirectoryName(_ name: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/\\:*?\"<>|")
        return name.components(separatedBy: invalidCharacters).joined(separator: "_")
    }
}

// MARK: - Run Manifest

/// Manifest file written by Claude Code skill to describe a run
nonisolated struct RunManifest: Codable, Sendable {
    let runId: UUID
    let projectName: String
    let runName: String
    let deviceInfo: String?
    let createdAt: Date
    let isComplete: Bool

    static let fileName = "manifest.json"
}

// MARK: - Screenshot Watcher Service

/// Watches for new screenshots and creates corresponding records
actor ScreenshotWatcherService {
    static let shared = ScreenshotWatcherService()

    // MARK: - Properties

    private var config: ScreenshotDirectoryConfig
    private var fileDescriptor: Int32 = -1
    private var dispatchSource: DispatchSourceFileSystemObject?
    private var isWatching: Bool = false
    private var knownRuns: Set<UUID> = []

    // MARK: - Initialization

    private init() {
        config = ScreenshotDirectoryConfig()
    }

    // MARK: - Configuration

    func configure(with config: ScreenshotDirectoryConfig) {
        self.config = config
        logInfo("ScreenshotWatcher configured with base directory: \(config.baseDirectory.path)", category: .simulator)
    }

    func getConfig() -> ScreenshotDirectoryConfig {
        config
    }

    // MARK: - Directory Management

    /// Ensures the base screenshot directory exists
    func ensureBaseDirectoryExists() throws {
        let path = config.baseDirectory.path
        if !FileManager.default.fileExists(atPath: path) {
            try FileManager.default.createDirectory(
                at: config.baseDirectory,
                withIntermediateDirectories: true,
                attributes: nil
            )
            logInfo("Created screenshot base directory: \(path)", category: .simulator)
        }
    }

    /// Creates a new run directory and returns its path
    func createRunDirectory(projectName: String, runId: UUID) throws -> URL {
        let runDir = config.runDirectory(for: runId, in: projectName)

        try FileManager.default.createDirectory(
            at: runDir,
            withIntermediateDirectories: true,
            attributes: nil
        )

        logInfo("Created run directory: \(runDir.path)", category: .simulator)
        return runDir
    }

    /// Writes a manifest file for a run
    func writeManifest(_ manifest: RunManifest, to runDirectory: URL) throws {
        let manifestURL = runDirectory.appendingPathComponent(RunManifest.fileName)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted

        let data = try encoder.encode(manifest)
        try data.write(to: manifestURL)

        logDebug("Wrote manifest for run: \(manifest.runName)", category: .simulator)
    }

    /// Reads a manifest file from a run directory
    func readManifest(from runDirectory: URL) throws -> RunManifest {
        let manifestURL = runDirectory.appendingPathComponent(RunManifest.fileName)
        let data = try Data(contentsOf: manifestURL)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return try decoder.decode(RunManifest.self, from: data)
    }

    // MARK: - Watching

    /// Starts watching for new screenshots
    func startWatching() throws {
        guard !isWatching else {
            logDebug("Already watching for screenshots", category: .simulator)
            return
        }

        try ensureBaseDirectoryExists()

        fileDescriptor = open(config.baseDirectory.path, O_EVTONLY)
        guard fileDescriptor >= 0 else {
            throw ScreenshotWatcherError.cannotOpenDirectory(config.baseDirectory.path)
        }

        dispatchSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .rename],
            queue: .global(qos: .utility)
        )

        dispatchSource?.setEventHandler { [weak self] in
            Task {
                await self?.handleDirectoryChange()
            }
        }

        dispatchSource?.setCancelHandler { [weak self] in
            Task {
                await self?.cleanupWatcher()
            }
        }

        dispatchSource?.resume()
        isWatching = true

        logInfo("Started watching for screenshots at: \(config.baseDirectory.path)", category: .simulator)

        // Initial scan
        Task {
            await scanForNewRuns()
        }
    }

    /// Stops watching for screenshots
    func stopWatching() {
        guard isWatching else { return }

        dispatchSource?.cancel()
        dispatchSource = nil
        isWatching = false

        logInfo("Stopped watching for screenshots", category: .simulator)
    }

    private func cleanupWatcher() {
        if fileDescriptor >= 0 {
            close(fileDescriptor)
            fileDescriptor = -1
        }
    }

    // MARK: - Scanning

    private func handleDirectoryChange() {
        logDebug("Directory change detected", category: .simulator)
        Task {
            await scanForNewRuns()
        }
    }

    /// Scans the base directory for new runs
    func scanForNewRuns() async {
        logDebug("Scanning for new runs", category: .simulator)

        let fileManager = FileManager.default
        let baseDir = config.baseDirectory

        guard let projectDirs = try? fileManager.contentsOfDirectory(
            at: baseDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            logWarning("Failed to list project directories", category: .simulator)
            return
        }

        for projectDir in projectDirs {
            guard isDirectory(at: projectDir) else { continue }

            let runDirs = (try? fileManager.contentsOfDirectory(
                at: projectDir,
                includingPropertiesForKeys: [.isDirectoryKey, .creationDateKey],
                options: [.skipsHiddenFiles]
            )) ?? []

            for runDir in runDirs {
                guard isDirectory(at: runDir) else { continue }
                guard let runId = UUID(uuidString: runDir.lastPathComponent) else { continue }

                if !knownRuns.contains(runId) {
                    knownRuns.insert(runId)
                    await processNewRun(at: runDir)
                }
            }
        }
    }

    private func isDirectory(at url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    /// Processes a newly discovered run directory
    private func processNewRun(at runDirectory: URL) async {
        logDebug("Processing new run at: \(runDirectory.path)", category: .simulator)

        do {
            let manifest = try readManifest(from: runDirectory)

            // Find screenshots in the directory
            let screenshots = try findScreenshots(in: runDirectory)

            // Notify the manager to create database records
            await MainActor.run {
                ScreenshotWatcherManager.shared.handleNewRun(
                    manifest: manifest,
                    screenshots: screenshots,
                    runDirectory: runDirectory
                )
            }

            logInfo("Processed run '\(manifest.runName)' with \(screenshots.count) screenshots", category: .simulator)

        } catch {
            error.log(category: .simulator, context: "Failed to process run at \(runDirectory.path)")
        }
    }

    /// Finds all screenshot files in a run directory
    private func findScreenshots(in runDirectory: URL) throws -> [URL] {
        let fileManager = FileManager.default
        let contents = try fileManager.contentsOfDirectory(
            at: runDirectory,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        )

        let imageExtensions = ["png", "jpg", "jpeg"]

        return contents
            .filter { url in
                imageExtensions.contains(url.pathExtension.lowercased())
            }
            .sorted { url1, url2 in
                // Sort by creation date or filename
                let date1 = (try? url1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                let date2 = (try? url2.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                return date1 < date2
            }
    }

    // MARK: - Cleanup

    /// Deletes a run directory and all its contents
    func deleteRunDirectory(runId: UUID, projectName: String) throws {
        let runDir = config.runDirectory(for: runId, in: projectName)

        if FileManager.default.fileExists(atPath: runDir.path) {
            try FileManager.default.removeItem(at: runDir)
            knownRuns.remove(runId)
            logInfo("Deleted run directory: \(runDir.path)", category: .simulator)
        }
    }

    /// Cleans up old runs, keeping only the most recent based on config
    func cleanupOldRuns(for projectName: String, context: ModelContext) async {
        let projectDir = config.projectDirectory(for: projectName)

        guard let runDirs = try? FileManager.default.contentsOfDirectory(
            at: projectDir,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        // Sort by creation date, newest first
        let sortedRuns = runDirs
            .filter { isDirectory(at: $0) }
            .sorted { url1, url2 in
                let date1 = (try? url1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                let date2 = (try? url2.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                return date1 > date2
            }

        // Delete runs beyond the limit
        if sortedRuns.count > config.maxRunsPerProject {
            let runsToDelete = sortedRuns.suffix(from: config.maxRunsPerProject)

            for runDir in runsToDelete {
                guard let runId = UUID(uuidString: runDir.lastPathComponent) else { continue }

                do {
                    try deleteRunDirectory(runId: runId, projectName: projectName)

                    // Also delete from database
                    await MainActor.run {
                        ScreenshotWatcherManager.shared.deleteRun(runId: runId, context: context)
                    }
                } catch {
                    error.log(category: .simulator, context: "Failed to delete old run")
                }
            }

            logInfo("Cleaned up \(runsToDelete.count) old runs for project: \(projectName)", category: .simulator)
        }
    }
}

// MARK: - Screenshot Watcher Errors

nonisolated enum ScreenshotWatcherError: Error, LocalizedError {
    case cannotOpenDirectory(String)
    case manifestNotFound
    case invalidManifest

    var errorDescription: String? {
        switch self {
        case let .cannotOpenDirectory(path):
            return "Cannot open directory for watching: \(path)"
        case .manifestNotFound:
            return "Run manifest not found"
        case .invalidManifest:
            return "Invalid or corrupt run manifest"
        }
    }
}

// MARK: - Screenshot Watcher Manager (MainActor)

/// MainActor wrapper for UI integration and database operations
@MainActor
final class ScreenshotWatcherManager: ObservableObject {
    static let shared = ScreenshotWatcherManager()

    // MARK: - Published Properties

    @Published private(set) var isWatching: Bool = false
    @Published private(set) var lastError: String?

    // MARK: - Private Properties

    private var modelContext: ModelContext?

    // MARK: - Initialization

    private init() {}

    // MARK: - Configuration

    func configure(with context: ModelContext) {
        modelContext = context
        logDebug("ScreenshotWatcherManager configured with ModelContext", category: .simulator)
    }

    // MARK: - Lifecycle

    func start() async {
        do {
            try await ScreenshotWatcherService.shared.startWatching()
            isWatching = true
            lastError = nil
        } catch {
            isWatching = false
            lastError = error.localizedDescription
            error.log(category: .simulator, context: "Failed to start screenshot watcher")
        }
    }

    func stop() async {
        await ScreenshotWatcherService.shared.stopWatching()
        isWatching = false
    }

    // MARK: - Run Management

    /// Creates a new run and returns its ID and directory path
    func createRun(
        projectName: String,
        runName: String,
        deviceInfo: String?
    ) async -> (runId: UUID, path: String)? {
        let runId = UUID()

        do {
            let runDir = try await ScreenshotWatcherService.shared.createRunDirectory(
                projectName: projectName,
                runId: runId
            )

            let manifest = RunManifest(
                runId: runId,
                projectName: projectName,
                runName: runName,
                deviceInfo: deviceInfo,
                createdAt: Date(),
                isComplete: false
            )

            try await ScreenshotWatcherService.shared.writeManifest(manifest, to: runDir)

            return (runId, runDir.path)

        } catch {
            error.log(category: .simulator, context: "Failed to create run")
            return nil
        }
    }

    /// Handles a newly discovered run from the watcher
    func handleNewRun(manifest: RunManifest, screenshots: [URL], runDirectory _: URL) {
        guard let context = modelContext else {
            logError("ModelContext not configured", category: .simulator)
            return
        }

        // Find or create project
        let project = findOrCreateProject(name: manifest.projectName, context: context)

        // Create SimulatorRun record
        let run = SimulatorRun(
            id: manifest.runId,
            name: manifest.runName,
            deviceInfo: manifest.deviceInfo,
            createdAt: manifest.createdAt,
            isComplete: manifest.isComplete,
            project: project
        )

        context.insert(run)

        // Create Screenshot records
        for (index, screenshotURL) in screenshots.enumerated() {
            let screenshot = Screenshot(
                filePath: screenshotURL.path,
                captureIndex: index,
                run: run
            )
            context.insert(screenshot)
        }

        do {
            try context.save()
            logInfo("Saved run '\(manifest.runName)' with \(screenshots.count) screenshots", category: .simulator)

            // Trigger cleanup if needed
            Task {
                await ScreenshotWatcherService.shared.cleanupOldRuns(
                    for: manifest.projectName,
                    context: context
                )
            }

        } catch {
            error.log(category: .simulator, context: "Failed to save run")
        }
    }

    /// Finds an existing project or creates a placeholder
    private func findOrCreateProject(name: String, context: ModelContext) -> Project? {
        var descriptor = FetchDescriptor<Project>()
        descriptor.predicate = #Predicate<Project> { project in
            project.name == name
        }
        descriptor.fetchLimit = 1

        if let existing = try? context.fetch(descriptor).first {
            return existing
        }

        // Project doesn't exist - return nil (screenshots can exist without a project)
        // The user can link them later through the UI
        logDebug("No project found for '\(name)', run will be unlinked", category: .simulator)
        return nil
    }

    /// Deletes a run from the database
    func deleteRun(runId: UUID, context: ModelContext) {
        var descriptor = FetchDescriptor<SimulatorRun>()
        descriptor.predicate = #Predicate<SimulatorRun> { run in
            run.id == runId
        }
        descriptor.fetchLimit = 1

        if let run = try? context.fetch(descriptor).first {
            // Delete associated screenshots
            for screenshot in run.screenshots {
                screenshot.deleteFile()
                context.delete(screenshot)
            }

            context.delete(run)

            do {
                try context.save()
                logInfo("Deleted run from database: \(runId)", category: .simulator)
            } catch {
                error.log(category: .simulator, context: "Failed to delete run from database")
            }
        }
    }

    // MARK: - Queries

    /// Fetches all runs for a project
    func fetchRuns(for project: Project?, context: ModelContext) -> [SimulatorRun] {
        var descriptor = FetchDescriptor<SimulatorRun>()

        if let project = project {
            let projectId = project.id
            descriptor.predicate = #Predicate<SimulatorRun> { run in
                run.project?.id == projectId
            }
        }

        descriptor.sortBy = [SortDescriptor(\.createdAt, order: .reverse)]

        return (try? context.fetch(descriptor)) ?? []
    }

    /// Gets the screenshot save location for a project
    func getScreenshotLocation(for projectName: String) async -> URL {
        let config = await ScreenshotWatcherService.shared.getConfig()
        return config.projectDirectory(for: projectName)
    }
}

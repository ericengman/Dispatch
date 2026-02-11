//
//  BuildRunController.swift
//  Dispatch
//
//  Central build orchestrator with brew-style strip state management
//

import Foundation
import SwiftUI

// MARK: - BuildRunController

@Observable
@MainActor
final class BuildRunController {
    static let shared = BuildRunController()

    // MARK: - Public State

    /// Active and completed builds keyed by UUID
    var activeBuilds: [UUID: BuildRun] = [:]

    /// Ordered list of build IDs for display (most recent first)
    var buildOrder: [UUID] = []

    /// Per-build brew-style strip state
    var stripStates: [UUID: BrewState] = [:]

    /// Red flash flag for builds that need attention
    var expandedWithAlert: [UUID: Bool] = [:]

    /// Cached project info per project path
    var projectInfoCache: [String: XcodeProjectInfo] = [:]

    /// Selected scheme per project path (persisted)
    var selectedSchemes: [String: String] = [:]

    /// Selected destinations per project path (persisted)
    var selectedDestinations: [String: [BuildDestination]] = [:]

    /// Recent destinations across all projects (persisted, max 5)
    var recentDestinations: [BuildDestination] = []

    /// Saved custom filter strings per destination ID (persisted)
    var savedFilters: [String: [String]] = [:]

    // MARK: - Private State

    private var condenseTimers: [UUID: Task<Void, Never>] = [:]
    private var peekTimers: [UUID: Task<Void, Never>] = [:]
    private var hoverTimers: [UUID: Task<Void, Never>] = [:]
    private var alertTimers: [UUID: Task<Void, Never>] = [:]

    // MARK: - Init

    private init() {
        loadPersistedState()
        logDebug("BuildRunController initialized", category: .build)
    }

    // MARK: - Project Info

    /// Get or detect project info for a path
    func projectInfo(for path: String) async -> XcodeProjectInfo? {
        if let cached = projectInfoCache[path] {
            return cached
        }

        let info = await XcodeProjectDetector.shared.detectProject(at: path)
        if let info {
            projectInfoCache[path] = info
        }
        return info
    }

    /// Get selected scheme for a project, defaulting to first available
    func selectedScheme(for projectPath: String) -> String? {
        if let selected = selectedSchemes[projectPath] {
            return selected
        }
        return projectInfoCache[projectPath]?.schemes.first
    }

    /// Set the selected scheme for a project
    func setSelectedScheme(_ scheme: String, for projectPath: String) {
        selectedSchemes[projectPath] = scheme
        persistState()
    }

    /// Get selected destinations for a project
    func destinations(for projectPath: String) -> [BuildDestination] {
        selectedDestinations[projectPath] ?? []
    }

    /// Add a destination for a project
    func addDestination(_ destination: BuildDestination, for projectPath: String) {
        var dests = selectedDestinations[projectPath] ?? []
        guard !dests.contains(where: { $0.id == destination.id }) else { return }
        dests.append(destination)
        selectedDestinations[projectPath] = dests

        // Track as recent
        addToRecent(destination)
        persistState()
        logInfo("Added destination \(destination.displayName) for \(projectPath)", category: .build)
    }

    /// Remove a destination for a project
    func removeDestination(_ destination: BuildDestination, for projectPath: String) {
        selectedDestinations[projectPath]?.removeAll { $0.id == destination.id }
        persistState()
        logInfo("Removed destination \(destination.displayName) for \(projectPath)", category: .build)
    }

    // MARK: - Saved Filters

    /// Add a saved filter for a destination
    func addSavedFilter(_ text: String, for destinationId: String) {
        var filters = savedFilters[destinationId] ?? []
        guard !filters.contains(text) else { return }
        filters.append(text)
        savedFilters[destinationId] = filters
        persistState()
        logDebug("Added saved filter '\(text)' for destination \(destinationId)", category: .build)
    }

    /// Remove a saved filter for a destination
    func removeSavedFilter(_ text: String, for destinationId: String) {
        savedFilters[destinationId]?.removeAll { $0 == text }
        if savedFilters[destinationId]?.isEmpty == true {
            savedFilters.removeValue(forKey: destinationId)
        }
        persistState()
        logDebug("Removed saved filter '\(text)' for destination \(destinationId)", category: .build)
    }

    /// Get saved filters for a destination
    func filtersForDestination(_ destinationId: String) -> [String] {
        savedFilters[destinationId] ?? []
    }

    // MARK: - Build Execution

    /// Start a build for the given project, scheme, and destinations
    func startBuild(projectPath _: String, projectInfo: XcodeProjectInfo, scheme: String, destinations: [BuildDestination]) async {
        logInfo("Starting build: \(scheme) for \(destinations.count) destination(s)", category: .build)

        // Create BuildRun for each destination
        var buildRuns: [BuildRun] = []
        for dest in destinations {
            let run = BuildRun(destination: dest, scheme: scheme)
            activeBuilds[run.id] = run
            buildOrder.insert(run.id, at: 0)
            stripStates[run.id] = .expanded
            buildRuns.append(run)
        }

        // Run builds sequentially
        for run in buildRuns {
            guard !Task.isCancelled else { break }
            guard run.status != .cancelled else { continue }

            await executeBuild(
                run: run,
                projectInfo: projectInfo
            )

            // On success: launch the app
            if run.status == .succeeded {
                if run.destination.platform == .iOSSimulator {
                    await launchInSimulator(run: run, projectInfo: projectInfo)
                } else if run.destination.platform == .macOS {
                    await launchOnMac(run: run, projectInfo: projectInfo)
                }
            }

            // Auto-condense successful builds after 3s
            if run.status == .succeeded {
                startAutoCondenseTimer(run.id)
            }
        }
    }

    /// Start build for the current project context
    func startBuildForProject(path: String) async {
        guard let info = await projectInfo(for: path) else {
            logError("No Xcode project found at \(path)", category: .build)
            return
        }

        guard let scheme = selectedScheme(for: path) else {
            logError("No scheme selected for \(path)", category: .build)
            return
        }

        var dests = destinations(for: path)

        // Auto-select Mac destination if none selected and project is macOS
        if dests.isEmpty {
            if info.platformHint == .macOS || info.platformHint == .multiplatform {
                dests = [.myMac]
                selectedDestinations[path] = dests
                persistState()
            } else {
                logWarning("No destinations selected for \(path)", category: .build)
                return
            }
        }

        await startBuild(projectPath: path, projectInfo: info, scheme: scheme, destinations: dests)
    }

    /// Cancel a specific build
    func cancelBuild(id: UUID) {
        guard let run = activeBuilds[id] else { return }
        run.process?.terminate()
        run.status = .cancelled
        run.endTime = Date()
        logInfo("Cancelled build \(id)", category: .build)
    }

    /// Cancel all active builds
    func cancelAllBuilds() {
        for (id, run) in activeBuilds where run.status.isActive {
            cancelBuild(id: id)
        }
    }

    /// Remove a completed build from the list
    func removeBuild(id: UUID) {
        activeBuilds.removeValue(forKey: id)
        buildOrder.removeAll { $0 == id }
        stripStates.removeValue(forKey: id)
        expandedWithAlert.removeValue(forKey: id)
        cleanupTimers(for: id)
    }

    /// Clear all completed builds
    func clearCompletedBuilds() {
        let completedIds = activeBuilds.filter { $0.value.status.isTerminal }.map(\.key)
        for id in completedIds {
            removeBuild(id: id)
        }
    }

    /// Whether any build is currently active
    var hasActiveBuilds: Bool {
        activeBuilds.values.contains { $0.status.isActive || $0.status == .queued }
    }

    /// Ordered builds for display
    var orderedBuilds: [BuildRun] {
        buildOrder.compactMap { activeBuilds[$0] }
    }

    // MARK: - Build Execution (Private)

    private func executeBuild(run: BuildRun, projectInfo: XcodeProjectInfo) async {
        run.status = .compiling("")
        run.startTime = Date()

        let flag = projectInfo.projectType == .xcworkspace ? "-workspace" : "-project"
        let args = [
            flag, projectInfo.projectFilePath,
            "-scheme", run.scheme,
            "-destination", run.destination.xcodebuildArg,
            "build"
        ]

        logInfo("xcodebuild \(args.joined(separator: " "))", category: .build)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcodebuild")
        process.arguments = args
        run.process = process

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
        } catch {
            run.status = .failed("Failed to launch xcodebuild: \(error.localizedDescription)")
            run.endTime = Date()
            logError("Failed to launch xcodebuild: \(error)", category: .build)
            return
        }

        // Read output line by line
        let fileHandle = pipe.fileHandleForReading

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                var buffer = Data()

                while true {
                    let chunk = fileHandle.availableData
                    if chunk.isEmpty { break }
                    buffer.append(chunk)

                    // Process complete lines
                    while let newlineRange = buffer.range(of: Data([0x0A])) {
                        let lineData = buffer.subdata(in: buffer.startIndex ..< newlineRange.lowerBound)
                        buffer.removeSubrange(buffer.startIndex ... newlineRange.lowerBound)

                        if let lineStr = String(data: lineData, encoding: .utf8) {
                            let parsed = Self.parseBuildLine(lineStr)
                            Task { @MainActor in
                                run.appendOutput(parsed.text, level: parsed.level)
                                // Update status based on content
                                Self.updateBuildStatus(run: run, line: parsed.text, level: parsed.level)
                            }
                        }
                    }
                }

                // Process remaining buffer
                if !buffer.isEmpty, let remaining = String(data: buffer, encoding: .utf8) {
                    let parsed = Self.parseBuildLine(remaining)
                    Task { @MainActor in
                        run.appendOutput(parsed.text, level: parsed.level)
                    }
                }

                process.waitUntilExit()
                continuation.resume()
            }
        }

        run.process = nil
        run.endTime = Date()

        if run.status == .cancelled { return }

        if process.terminationStatus == 0 {
            run.status = .succeeded
            logInfo("Build succeeded for \(run.destination.displayName)", category: .build)
        } else {
            let errorSummary = run.outputLines.last(where: { $0.level == .error })?.text ?? "Build failed"
            run.status = .failed(String(errorSummary.prefix(100)))
            logError("Build failed for \(run.destination.displayName): exit \(process.terminationStatus)", category: .build)
        }
    }

    // MARK: - Output Parsing

    private static func parseBuildLine(_ line: String) -> (text: String, level: BuildOutputLevel) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        if trimmed.contains(": error:") || trimmed.hasPrefix("error:") {
            return (trimmed, .error)
        }
        if trimmed.contains(": warning:") || trimmed.hasPrefix("warning:") {
            return (trimmed, .warning)
        }
        return (trimmed, .info)
    }

    private static func updateBuildStatus(run: BuildRun, line: String, level _: BuildOutputLevel) {
        if line.hasPrefix("CompileSwift") || line.hasPrefix("CompileC") {
            // Extract filename from compile command
            let parts = line.components(separatedBy: " ")
            if let filePart = parts.last(where: { $0.hasSuffix(".swift") || $0.hasSuffix(".m") || $0.hasSuffix(".c") }) {
                let fileName = (filePart as NSString).lastPathComponent
                run.status = .compiling(fileName)
            }
        } else if line.hasPrefix("Ld ") || line.contains("Linking") {
            run.status = .linking
        }
    }

    // MARK: - iOS Simulator Launch

    private func launchInSimulator(run: BuildRun, projectInfo: XcodeProjectInfo) async {
        guard let udid = run.destination.udid else {
            logError("No UDID for simulator destination", category: .build)
            return
        }

        run.status = .installing

        // Get build settings to find BUILT_PRODUCTS_DIR and PRODUCT_NAME
        let buildSettings = await getBuildSettings(
            projectInfo: projectInfo,
            scheme: run.scheme,
            destination: run.destination
        )

        guard let productsDir = buildSettings["BUILT_PRODUCTS_DIR"],
              let productName = buildSettings["PRODUCT_NAME"] ?? buildSettings["TARGET_NAME"]
        else {
            run.status = .failed("Could not determine build products directory")
            logError("Missing BUILT_PRODUCTS_DIR in build settings", category: .build)
            return
        }

        let appPath = "\(productsDir)/\(productName).app"
        let bundleId = buildSettings["PRODUCT_BUNDLE_IDENTIFIER"] ?? ""

        // Boot simulator
        logInfo("Booting simulator \(udid)", category: .build)
        await runShell("/usr/bin/xcrun", arguments: ["simctl", "boot", udid])

        // Open Simulator.app in background
        await runShell("/usr/bin/open", arguments: ["-g", "-a", "Simulator"])

        // Install app
        logInfo("Installing \(appPath) to \(udid)", category: .build)
        let installResult = await runShell("/usr/bin/xcrun", arguments: ["simctl", "install", udid, appPath])
        if !installResult.isEmpty, installResult.contains("error") {
            run.status = .failed("Install failed: \(installResult)")
            logError("Install failed: \(installResult)", category: .build)
            return
        }

        // Launch app
        run.status = .launching
        logInfo("Launching \(bundleId) on \(udid)", category: .build)
        let launchResult = await runShell("/usr/bin/xcrun", arguments: ["simctl", "launch", udid, bundleId])
        if launchResult.contains("error") {
            run.status = .failed("Launch failed: \(launchResult)")
            logError("Launch failed: \(launchResult)", category: .build)
            return
        }

        run.status = .succeeded
        logInfo("App launched successfully on \(run.destination.displayName)", category: .build)

        // Signal simulator attacher
        SimulatorWindowAttacher.shared.attachSimulator(udid: udid, deviceName: run.destination.name)
    }

    // MARK: - macOS Launch

    private func launchOnMac(run: BuildRun, projectInfo: XcodeProjectInfo) async {
        run.status = .launching

        // Get build settings to find BUILT_PRODUCTS_DIR and PRODUCT_NAME
        let buildSettings = await getBuildSettings(
            projectInfo: projectInfo,
            scheme: run.scheme,
            destination: run.destination
        )

        guard let productsDir = buildSettings["BUILT_PRODUCTS_DIR"],
              let productName = buildSettings["PRODUCT_NAME"] ?? buildSettings["TARGET_NAME"]
        else {
            run.appendOutput("Could not determine build products directory for macOS launch", level: .error)
            logError("Missing BUILT_PRODUCTS_DIR or PRODUCT_NAME in build settings for macOS launch", category: .build)
            return
        }

        let appPath = "\(productsDir)/\(productName).app"

        // Verify .app exists
        let appExists = FileManager.default.fileExists(atPath: appPath)
        guard appExists else {
            run.appendOutput("App not found at \(appPath)", level: .error)
            logError("macOS app not found at \(appPath)", category: .build)
            return
        }

        logInfo("Launching macOS app: \(appPath)", category: .build)
        run.appendOutput("Launching \(productName)...", level: .info)

        // Kill existing instance
        let killResult = await runShell("/usr/bin/pkill", arguments: ["-9", "-x", productName])
        if !killResult.isEmpty {
            logDebug("pkill result: \(killResult)", category: .build)
        }

        // Wait for process to fully exit
        try? await Task.sleep(nanoseconds: 500_000_000) // 500ms

        // Launch the app
        let launchResult = await runShell("/usr/bin/open", arguments: [appPath])
        if launchResult.contains("error") {
            run.appendOutput("Launch failed: \(launchResult)", level: .error)
            logError("macOS launch failed: \(launchResult)", category: .build)
            return
        }

        run.appendOutput("\(productName) launched successfully", level: .info)
        logInfo("macOS app launched successfully: \(productName)", category: .build)
    }

    private func getBuildSettings(projectInfo: XcodeProjectInfo, scheme: String, destination: BuildDestination) async -> [String: String] {
        let flag = projectInfo.projectType == .xcworkspace ? "-workspace" : "-project"
        let output = await runShellOutput(
            "/usr/bin/xcodebuild",
            arguments: [
                flag, projectInfo.projectFilePath,
                "-scheme", scheme,
                "-destination", destination.xcodebuildArg,
                "-showBuildSettings"
            ]
        )

        var settings: [String: String] = [:]
        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let equalsIndex = trimmed.firstIndex(of: "=") {
                let key = String(trimmed[trimmed.startIndex ..< equalsIndex]).trimmingCharacters(in: .whitespaces)
                let value = String(trimmed[trimmed.index(after: equalsIndex)...]).trimmingCharacters(in: .whitespaces)
                settings[key] = value
            }
        }
        return settings
    }

    // MARK: - Brew-Style Strip Mechanics

    func isCondensed(_ buildId: UUID) -> Bool {
        stripStates[buildId] == .condensed
    }

    func hoverActive(_ buildId: UUID) {
        peekTimers[buildId]?.cancel()

        guard stripStates[buildId] == .condensed else { return }

        hoverTimers[buildId]?.cancel()
        hoverTimers[buildId] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled, let self else { return }
            guard self.stripStates[buildId] == .condensed else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                self.stripStates[buildId] = .peeking
            }
        }
    }

    func hoverEnded(_ buildId: UUID) {
        hoverTimers[buildId]?.cancel()
        hoverTimers.removeValue(forKey: buildId)

        guard stripStates[buildId] == .peeking else { return }

        peekTimers[buildId]?.cancel()
        peekTimers[buildId] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled, let self else { return }
            if self.stripStates[buildId] == .peeking {
                withAnimation(.easeInOut(duration: 0.2)) {
                    self.stripStates[buildId] = .condensed
                }
            }
        }
    }

    func manualExpand(_ buildId: UUID) {
        hoverTimers[buildId]?.cancel()
        condenseTimers[buildId]?.cancel()
        peekTimers[buildId]?.cancel()
        withAnimation(.easeInOut(duration: 0.2)) {
            stripStates[buildId] = .manuallyExpanded
        }
    }

    func manualCondense(_ buildId: UUID) {
        hoverTimers[buildId]?.cancel()
        peekTimers[buildId]?.cancel()
        withAnimation(.easeInOut(duration: 0.2)) {
            stripStates[buildId] = .condensed
        }
    }

    // MARK: - Timers

    private func startAutoCondenseTimer(_ buildId: UUID) {
        condenseTimers[buildId]?.cancel()
        condenseTimers[buildId] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled, let self else { return }
            guard self.stripStates[buildId] == .expanded else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                self.stripStates[buildId] = .condensed
            }
            logDebug("Build \(buildId) auto-condensed after 3s", category: .build)
        }
    }

    private func cleanupTimers(for buildId: UUID) {
        condenseTimers[buildId]?.cancel()
        condenseTimers.removeValue(forKey: buildId)
        peekTimers[buildId]?.cancel()
        peekTimers.removeValue(forKey: buildId)
        hoverTimers[buildId]?.cancel()
        hoverTimers.removeValue(forKey: buildId)
        alertTimers[buildId]?.cancel()
        alertTimers.removeValue(forKey: buildId)
    }

    // MARK: - Persistence

    private func persistState() {
        // Schemes
        UserDefaults.standard.set(selectedSchemes, forKey: "buildController.selectedSchemes")

        // Destinations (encode as JSON)
        if let data = try? JSONEncoder().encode(selectedDestinations) {
            UserDefaults.standard.set(data, forKey: "buildController.selectedDestinations")
        }

        // Recent destinations
        if let data = try? JSONEncoder().encode(recentDestinations) {
            UserDefaults.standard.set(data, forKey: "buildController.recentDestinations")
        }

        // Saved filters
        if let data = try? JSONEncoder().encode(savedFilters) {
            UserDefaults.standard.set(data, forKey: "buildController.savedFilters")
        }
    }

    private func loadPersistedState() {
        selectedSchemes = UserDefaults.standard.dictionary(forKey: "buildController.selectedSchemes") as? [String: String] ?? [:]

        if let data = UserDefaults.standard.data(forKey: "buildController.selectedDestinations"),
           let decoded = try? JSONDecoder().decode([String: [BuildDestination]].self, from: data) {
            selectedDestinations = decoded
        }

        if let data = UserDefaults.standard.data(forKey: "buildController.recentDestinations"),
           let decoded = try? JSONDecoder().decode([BuildDestination].self, from: data) {
            recentDestinations = decoded
        }

        if let data = UserDefaults.standard.data(forKey: "buildController.savedFilters"),
           let decoded = try? JSONDecoder().decode([String: [String]].self, from: data) {
            savedFilters = decoded
        }
    }

    private func addToRecent(_ destination: BuildDestination) {
        recentDestinations.removeAll { $0.id == destination.id }
        recentDestinations.insert(destination, at: 0)
        if recentDestinations.count > 5 {
            recentDestinations = Array(recentDestinations.prefix(5))
        }
    }

    // MARK: - Shell Helpers

    @discardableResult
    private func runShell(_ path: String, arguments: [String]) async -> String {
        await runShellOutput(path, arguments: arguments)
    }

    private func runShellOutput(_ path: String, arguments: [String]) async -> String {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: path)
                process.arguments = arguments
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe

                do {
                    try process.run()
                    process.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    continuation.resume(returning: String(data: data, encoding: .utf8) ?? "")
                } catch {
                    continuation.resume(returning: "error: \(error.localizedDescription)")
                }
            }
        }
    }
}

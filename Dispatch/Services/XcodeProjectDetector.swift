//
//  XcodeProjectDetector.swift
//  Dispatch
//
//  Discovers Xcode projects and available simulators via xcodebuild/simctl
//

import Foundation

actor XcodeProjectDetector {
    static let shared = XcodeProjectDetector()

    // MARK: - Cache

    private var projectCache: [String: XcodeProjectInfo] = [:]
    private var simulatorCache: [BuildDestination]?
    private var simulatorCacheTime: Date?
    private let simulatorCacheTTL: TimeInterval = 30 // 30s TTL

    // MARK: - Project Detection

    /// Detect an Xcode project at the given directory path.
    /// Prefers .xcworkspace over .xcodeproj.
    func detectProject(at path: String) async -> XcodeProjectInfo? {
        if let cached = projectCache[path] {
            logDebug("Using cached project info for \(path)", category: .build)
            return cached
        }

        logInfo("Detecting Xcode project at \(path)", category: .build)

        let fm = FileManager.default

        // Look for .xcworkspace first, then .xcodeproj
        var projectFilePath: String?
        var projectType: XcodeProjectType?

        if let contents = try? fm.contentsOfDirectory(atPath: path) {
            // Prefer workspace
            if let workspace = contents.first(where: { $0.hasSuffix(".xcworkspace") && !$0.contains("project.xcworkspace") }) {
                projectFilePath = (path as NSString).appendingPathComponent(workspace)
                projectType = .xcworkspace
            }
            // Fallback to project
            if projectFilePath == nil, let project = contents.first(where: { $0.hasSuffix(".xcodeproj") }) {
                projectFilePath = (path as NSString).appendingPathComponent(project)
                projectType = .xcodeproj
            }
        }

        guard let filePath = projectFilePath, let type = projectType else {
            logDebug("No Xcode project found at \(path)", category: .build)
            return nil
        }

        // Get schemes via xcodebuild -list
        let schemes = await listSchemes(projectPath: filePath, projectType: type)

        // Determine platform hint from available destinations
        let platformHint = await detectPlatformHint(projectPath: filePath, projectType: type, schemes: schemes)

        let info = XcodeProjectInfo(
            projectFilePath: filePath,
            projectType: type,
            schemes: schemes,
            platformHint: platformHint
        )

        projectCache[path] = info
        logInfo("Detected \(type.rawValue) at \(filePath) with schemes: \(schemes)", category: .build)
        return info
    }

    /// Invalidate cache for a path
    func invalidateCache(for path: String) {
        projectCache.removeValue(forKey: path)
        logDebug("Invalidated project cache for \(path)", category: .build)
    }

    // MARK: - Simulator Discovery

    /// Get available iOS simulators from simctl
    func availableSimulators() async -> [BuildDestination] {
        // Check cache
        if let cached = simulatorCache,
           let cacheTime = simulatorCacheTime,
           Date().timeIntervalSince(cacheTime) < simulatorCacheTTL {
            return cached
        }

        logDebug("Fetching available simulators via simctl", category: .build)

        let output = await runProcess(
            "/usr/bin/xcrun",
            arguments: ["simctl", "list", "devices", "available", "-j"]
        )

        guard let data = output.data(using: .utf8) else {
            logError("Failed to get simctl output", category: .build)
            return []
        }

        do {
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let devices = json?["devices"] as? [String: [[String: Any]]] else {
                logError("Unexpected simctl JSON structure", category: .build)
                return []
            }

            var destinations: [BuildDestination] = []

            for (runtime, deviceList) in devices {
                // Extract OS version from runtime string like "com.apple.CoreSimulator.SimRuntime.iOS-17-5"
                let osVersion = extractOSVersion(from: runtime)

                for device in deviceList {
                    guard let name = device["name"] as? String,
                          let udid = device["udid"] as? String,
                          let isAvailable = device["isAvailable"] as? Bool,
                          isAvailable
                    else { continue }

                    // Skip Apple TV, Apple Watch, and Vision Pro simulators
                    let runtimeLower = runtime.lowercased()
                    if runtimeLower.contains("tvos") || runtimeLower.contains("watchos") || runtimeLower.contains("xros") {
                        continue
                    }

                    let destination = BuildDestination(
                        id: udid,
                        platform: .iOSSimulator,
                        name: name,
                        osVersion: osVersion,
                        udid: udid
                    )
                    destinations.append(destination)
                }
            }

            // Sort by name then OS version
            destinations.sort { a, b in
                if a.name == b.name {
                    return (a.osVersion ?? "") > (b.osVersion ?? "")
                }
                return a.name < b.name
            }

            simulatorCache = destinations
            simulatorCacheTime = Date()
            logInfo("Found \(destinations.count) available simulators", category: .build)
            return destinations
        } catch {
            logError("Failed to parse simctl JSON: \(error)", category: .build)
            return []
        }
    }

    // MARK: - Private Helpers

    private func listSchemes(projectPath: String, projectType: XcodeProjectType) async -> [String] {
        let flag = projectType == .xcworkspace ? "-workspace" : "-project"
        let output = await runProcess(
            "/usr/bin/xcodebuild",
            arguments: [flag, projectPath, "-list", "-json"]
        )

        guard let data = output.data(using: .utf8) else { return [] }

        do {
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

            // Structure: { "project": { "schemes": [...] } } or { "workspace": { "schemes": [...] } }
            let key = projectType == .xcworkspace ? "workspace" : "project"
            if let container = json?[key] as? [String: Any],
               let schemes = container["schemes"] as? [String] {
                return schemes
            }
            return []
        } catch {
            logError("Failed to parse xcodebuild -list JSON: \(error)", category: .build)
            return []
        }
    }

    private func detectPlatformHint(projectPath: String, projectType: XcodeProjectType, schemes: [String]) async -> PlatformHint {
        guard let firstScheme = schemes.first else { return .macOS }

        let flag = projectType == .xcworkspace ? "-workspace" : "-project"
        let output = await runProcess(
            "/usr/bin/xcodebuild",
            arguments: [flag, projectPath, "-scheme", firstScheme, "-showdestinations"],
            timeout: 15
        )

        let lower = output.lowercased()
        let hasIOS = lower.contains("ios simulator") || lower.contains("platform:ios")
        let hasMac = lower.contains("platform:macos") || lower.contains("os x")

        if hasIOS && hasMac { return .multiplatform }
        if hasIOS { return .iOS }
        return .macOS
    }

    private func extractOSVersion(from runtime: String) -> String? {
        // "com.apple.CoreSimulator.SimRuntime.iOS-17-5" -> "17.5"
        let parts = runtime.components(separatedBy: ".")
        guard let last = parts.last else { return nil }
        // "iOS-17-5" -> "17.5"
        let versionParts = last.components(separatedBy: "-")
        if versionParts.count >= 2 {
            let numericParts = versionParts.dropFirst() // Drop "iOS"
            return numericParts.joined(separator: ".")
        }
        return nil
    }

    /// Run a process and return stdout as string
    private func runProcess(_ path: String, arguments: [String], timeout: TimeInterval = 30) async -> String {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: path)
                process.arguments = arguments

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = Pipe() // Suppress stderr

                do {
                    try process.run()

                    // Timeout handling
                    let timeoutItem = DispatchWorkItem {
                        if process.isRunning {
                            process.terminate()
                            logWarning("Process timed out: \(path) \(arguments.joined(separator: " "))", category: .build)
                        }
                    }
                    DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timeoutItem)

                    process.waitUntilExit()
                    timeoutItem.cancel()

                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? ""
                    continuation.resume(returning: output)
                } catch {
                    logError("Failed to run \(path): \(error)", category: .build)
                    continuation.resume(returning: "")
                }
            }
        }
    }
}

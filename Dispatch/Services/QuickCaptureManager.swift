//
//  QuickCaptureManager.swift
//  Dispatch
//
//  Manages capture targets (previously captured apps) for quick re-capture.
//

import AppKit
import Combine
import Foundation

// MARK: - Capture Target

/// A previously captured application that can be re-captured with one click.
struct CaptureTarget: Hashable, Codable, Identifiable {
    var id: String { appName }
    let appName: String
    var lastWindowTitle: String
    var lastCaptured: Date
    var thumbnailPath: String?
    var projectId: UUID?

    /// Thumbnail image loaded from the last capture
    var thumbnail: NSImage? {
        guard let path = thumbnailPath else { return nil }
        return NSImage(contentsOfFile: path)
    }

    /// Application icon from running apps or /Applications
    var appIcon: NSImage? {
        if let runningApp = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == appName }) {
            return runningApp.icon
        }
        let appPath = "/Applications/\(appName).app"
        if FileManager.default.fileExists(atPath: appPath) {
            return NSWorkspace.shared.icon(forFile: appPath)
        }
        return nil
    }

    /// Relative time since last capture (e.g., "5m ago")
    var timeAgo: String {
        let interval = Date().timeIntervalSince(lastCaptured)
        if interval < 60 { return "just now" }
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        if interval < 86400 { return "\(Int(interval / 3600))h ago" }
        return "\(Int(interval / 86400))d ago"
    }
}

// MARK: - Quick Capture Manager

/// Manages capture targets (apps you've previously captured) for quick re-capture.
/// Persists to UserDefaults and provides reactive updates via @Published.
@MainActor
final class QuickCaptureManager: ObservableObject {
    // MARK: - Singleton

    static let shared = QuickCaptureManager()

    // MARK: - Constants

    private let maxTargets = 10
    private let targetsKey = "captureTargets"

    // MARK: - Published Properties

    @Published private(set) var captureTargets: [CaptureTarget] = []

    // MARK: - Initialization

    private init() {
        loadTargets()
        logDebug("QuickCaptureManager initialized with \(captureTargets.count) targets", category: .capture)
    }

    // MARK: - Targets API

    /// Updates or creates a capture target from a completed capture.
    func updateTarget(from source: CaptureSource, thumbnailPath: String?, projectId: UUID?) {
        if let index = captureTargets.firstIndex(where: { $0.appName == source.appName }) {
            // Update existing target
            captureTargets[index].lastWindowTitle = source.windowTitle
            captureTargets[index].lastCaptured = Date()
            captureTargets[index].thumbnailPath = thumbnailPath
            if let projectId { captureTargets[index].projectId = projectId }

            // Move to front
            let target = captureTargets.remove(at: index)
            captureTargets.insert(target, at: 0)
        } else {
            // Create new target
            let target = CaptureTarget(
                appName: source.appName,
                lastWindowTitle: source.windowTitle,
                lastCaptured: Date(),
                thumbnailPath: thumbnailPath,
                projectId: projectId
            )
            captureTargets.insert(target, at: 0)
        }

        // Trim
        if captureTargets.count > maxTargets {
            captureTargets = Array(captureTargets.prefix(maxTargets))
        }

        saveTargets()
        logInfo("Updated capture target: \(source.appName)", category: .capture)
    }

    /// Returns targets filtered by project ID.
    func targets(for projectId: UUID?) -> [CaptureTarget] {
        captureTargets.filter { $0.projectId == projectId }
    }

    /// Removes a target by app name.
    func removeTarget(appName: String) {
        captureTargets.removeAll { $0.appName == appName }
        saveTargets()
    }

    /// Re-captures a target's window by finding the app's largest visible window.
    func recapture(target: CaptureTarget) async -> CaptureResult {
        logInfo("Re-capturing target: \(target.appName)", category: .capture)

        // Find a window belonging to this app (use .optionAll to find windows on other Spaces)
        guard let windowList = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            logError("Failed to get window list for re-capture", category: .capture)
            return .error(NSError(domain: "QuickCaptureManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Cannot list windows"]))
        }

        // Collect all candidate windows and pick the largest one to avoid
        // capturing tiny auxiliary windows (menu bar items, panels, etc.)
        let minimumDimension: CGFloat = 100
        var bestCandidate: (windowID: CGWindowID, title: String, area: CGFloat)?

        for windowDict in windowList {
            guard let ownerName = windowDict[kCGWindowOwnerName as String] as? String,
                  ownerName == target.appName,
                  let windowID = windowDict[kCGWindowNumber as String] as? CGWindowID,
                  let layer = windowDict[kCGWindowLayer as String] as? Int,
                  layer == 0,
                  let boundsDict = windowDict[kCGWindowBounds as String] as? [String: CGFloat]
            else {
                continue
            }

            // Skip minimized windows (alpha 0 or no bounds)
            if let alpha = windowDict[kCGWindowAlpha as String] as? CGFloat, alpha <= 0 {
                continue
            }

            // Skip tiny windows (menu bar items, status indicators, etc.)
            let width = boundsDict["Width"] ?? 0
            let height = boundsDict["Height"] ?? 0
            if width < minimumDimension || height < minimumDimension {
                continue
            }

            let area = width * height
            let title = windowDict[kCGWindowName as String] as? String ?? ""

            if bestCandidate == nil || area > bestCandidate!.area {
                bestCandidate = (windowID: windowID, title: title, area: area)
            }
        }

        if let candidate = bestCandidate {
            let source = CaptureSource(appName: target.appName, windowTitle: candidate.title)
            return await captureWindowByID(candidate.windowID, source: source)
        }

        logWarning("No window found for app: \(target.appName)", category: .capture)
        return .error(NSError(domain: "QuickCaptureManager", code: -2, userInfo: [NSLocalizedDescriptionKey: "\(target.appName) has no open window"]))
    }

    // MARK: - Private

    private func captureWindowByID(_ windowID: CGWindowID, source: CaptureSource) async -> CaptureResult {
        let capturesDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Dispatch/QuickCaptures", isDirectory: true)

        try? FileManager.default.createDirectory(at: capturesDirectory, withIntermediateDirectories: true)

        let filename = "\(UUID().uuidString).png"
        let outputPath = capturesDirectory.appendingPathComponent(filename)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-l", String(windowID), "-x", outputPath.path]

        do {
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus == 0 && FileManager.default.fileExists(atPath: outputPath.path) {
                logInfo("Re-captured window: \(filename)", category: .capture)
                return .success(outputPath, source)
            } else {
                return .error(NSError(domain: "QuickCaptureManager", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "screencapture failed"]))
            }
        } catch {
            logError("Failed to run screencapture: \(error)", category: .capture)
            return .error(error)
        }
    }

    // MARK: - Persistence

    private func loadTargets() {
        guard let data = UserDefaults.standard.data(forKey: targetsKey) else { return }
        do {
            captureTargets = try JSONDecoder().decode([CaptureTarget].self, from: data)
            logDebug("Loaded \(captureTargets.count) capture targets", category: .capture)
        } catch {
            logError("Failed to decode capture targets: \(error)", category: .capture)
            captureTargets = []
        }
    }

    private func saveTargets() {
        do {
            let data = try JSONEncoder().encode(captureTargets)
            UserDefaults.standard.set(data, forKey: targetsKey)
        } catch {
            logError("Failed to encode capture targets: \(error)", category: .capture)
        }
    }
}

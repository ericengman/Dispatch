//
//  CaptureCoordinator.swift
//  Dispatch
//
//  Coordinates capture results and window opening.
//

import Combine
import Foundation

/// Coordinates capture results and window opening.
/// Uses @Published pendingCapture which MainView observes to trigger openWindow.
@MainActor
final class CaptureCoordinator: ObservableObject {
    static let shared = CaptureCoordinator()

    @Published var pendingCapture: QuickCapture?

    /// The current project context for new captures.
    /// Set by QuickCaptureSection when displayed in a project's SkillsSidePanel.
    var currentProjectId: UUID?

    private init() {}

    func handleCaptureResult(_ result: CaptureResult) {
        switch result {
        case let .success(url, source):
            guard FileManager.default.fileExists(atPath: url.path) else {
                logError("Capture file not found: \(url.path)", category: .capture)
                return
            }
            let capture = QuickCapture(
                fileURL: url,
                projectId: currentProjectId,
                sourceAppName: source?.appName,
                sourceWindowTitle: source?.windowTitle
            )
            pendingCapture = capture

            // Track this as a re-capturable target
            if let source {
                QuickCaptureManager.shared.updateTarget(from: source, thumbnailPath: url.path, projectId: currentProjectId)
            }

            logInfo("Capture ready for annotation: \(url.lastPathComponent) (source: \(source?.appName ?? "region"))", category: .capture)

        case .cancelled:
            logInfo("Capture cancelled by user", category: .capture)

        case let .error(error):
            logError("Capture failed: \(error)", category: .capture)
        }
    }
}

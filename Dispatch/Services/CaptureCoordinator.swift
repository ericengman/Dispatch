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

    private init() {}

    func handleCaptureResult(_ result: CaptureResult) {
        switch result {
        case let .success(url):
            guard FileManager.default.fileExists(atPath: url.path) else {
                logError("Capture file not found: \(url.path)", category: .capture)
                return
            }
            pendingCapture = QuickCapture(fileURL: url)
            logInfo("Capture ready for annotation: \(url.lastPathComponent)", category: .capture)

        case .cancelled:
            logInfo("Capture cancelled by user", category: .capture)

        case let .error(error):
            logError("Capture failed: \(error)", category: .capture)
        }
    }
}

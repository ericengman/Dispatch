//
//  QuickCapture.swift
//  Dispatch
//
//  Lightweight model for screenshots captured outside of SimulatorRun context.
//

import AppKit
import Foundation

/// Lightweight model for screenshots captured outside of SimulatorRun context.
/// Hashable + Codable for value-based WindowGroup identity.
struct QuickCapture: Hashable, Codable, Identifiable {
    let id: UUID
    let filePath: String
    let timestamp: Date
    var label: String?
    var projectId: UUID?
    var sourceAppName: String?
    var sourceWindowTitle: String?

    init(fileURL: URL, projectId: UUID? = nil, sourceAppName: String? = nil, sourceWindowTitle: String? = nil) {
        id = UUID()
        filePath = fileURL.path
        timestamp = Date()
        label = nil
        self.projectId = projectId
        self.sourceAppName = sourceAppName
        self.sourceWindowTitle = sourceWindowTitle
    }

    var fileURL: URL {
        URL(fileURLWithPath: filePath)
    }

    var image: NSImage? {
        NSImage(contentsOfFile: filePath)
    }

    // Hash on id only for unique window identity
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: QuickCapture, rhs: QuickCapture) -> Bool {
        lhs.id == rhs.id
    }
}

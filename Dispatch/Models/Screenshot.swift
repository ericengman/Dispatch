//
//  Screenshot.swift
//  Dispatch
//
//  Represents a single screenshot captured during iOS Simulator testing
//

import AppKit
import Foundation
import SwiftData

@Model
final class Screenshot {
    // MARK: - Properties

    var id: UUID

    /// File system path to the original screenshot image
    var filePath: String

    /// Order within the run (0-indexed)
    var captureIndex: Int

    /// Whether the user has hidden this screenshot from view
    var isHidden: Bool

    /// When the screenshot was captured
    var createdAt: Date

    /// Optional label/description added by user or Claude
    var label: String?

    // MARK: - Relationships

    /// The run this screenshot belongs to
    var run: SimulatorRun?

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        filePath: String,
        captureIndex: Int,
        isHidden: Bool = false,
        createdAt: Date = Date(),
        label: String? = nil,
        run: SimulatorRun? = nil
    ) {
        self.id = id
        self.filePath = filePath
        self.captureIndex = captureIndex
        self.isHidden = isHidden
        self.createdAt = createdAt
        self.label = label
        self.run = run

        logDebug("Created screenshot at index \(captureIndex): \(filePath)", category: .data)
    }

    // MARK: - Computed Properties

    /// URL representation of the file path
    var fileURL: URL {
        URL(fileURLWithPath: filePath)
    }

    /// File name without path
    var fileName: String {
        fileURL.lastPathComponent
    }

    /// Display label (uses label if set, otherwise generates from index)
    var displayLabel: String {
        if let label = label, !label.isEmpty {
            return label
        }
        return "Screenshot \(captureIndex + 1)"
    }

    /// Whether the file exists on disk
    var fileExists: Bool {
        FileManager.default.fileExists(atPath: filePath)
    }

    /// Loads the image from disk
    var image: NSImage? {
        guard fileExists else {
            logWarning("Screenshot file not found: \(filePath)", category: .data)
            return nil
        }
        return NSImage(contentsOfFile: filePath)
    }

    /// Thumbnail image (scaled down for performance)
    var thumbnail: NSImage? {
        guard let original = image else { return nil }

        let targetSize = NSSize(width: 120, height: 120)
        let aspectRatio = original.size.width / original.size.height

        var newSize: NSSize
        if aspectRatio > 1 {
            newSize = NSSize(width: targetSize.width, height: targetSize.width / aspectRatio)
        } else {
            newSize = NSSize(width: targetSize.height * aspectRatio, height: targetSize.height)
        }

        let thumbnail = NSImage(size: newSize)
        thumbnail.lockFocus()
        original.draw(
            in: NSRect(origin: .zero, size: newSize),
            from: NSRect(origin: .zero, size: original.size),
            operation: .copy,
            fraction: 1.0
        )
        thumbnail.unlockFocus()

        return thumbnail
    }

    /// Relative time since capture
    var relativeCaptureTime: String {
        RelativeTimeFormatter.format(createdAt)
    }

    /// Project name from parent run
    var projectName: String? {
        run?.project?.name
    }

    // MARK: - Methods

    /// Toggles the hidden state
    func toggleHidden() {
        isHidden.toggle()
        logDebug("Screenshot \(captureIndex) hidden state: \(isHidden)", category: .data)
    }

    /// Sets the label
    func setLabel(_ newLabel: String?) {
        label = newLabel
        logDebug("Screenshot \(captureIndex) label updated to: \(newLabel ?? "nil")", category: .data)
    }

    /// Deletes the file from disk
    func deleteFile() {
        guard fileExists else { return }

        do {
            try FileManager.default.removeItem(atPath: filePath)
            logInfo("Deleted screenshot file: \(filePath)", category: .data)
        } catch {
            error.log(category: .data, context: "Failed to delete screenshot file: \(filePath)")
        }
    }
}

// MARK: - Screenshot Queries

extension Screenshot {
    /// Predicate for visible (non-hidden) screenshots
    static var visible: Predicate<Screenshot> {
        #Predicate<Screenshot> { screenshot in
            !screenshot.isHidden
        }
    }

    /// Predicate for screenshots in a specific run
    static func inRun(_ run: SimulatorRun) -> Predicate<Screenshot> {
        let runId = run.id
        return #Predicate<Screenshot> { screenshot in
            screenshot.run?.id == runId
        }
    }
}

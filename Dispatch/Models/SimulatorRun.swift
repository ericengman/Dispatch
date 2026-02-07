//
//  SimulatorRun.swift
//  Dispatch
//
//  Represents a screenshot capture session from iOS Simulator testing
//

import Foundation
import SwiftData

@Model
final class SimulatorRun {
    // MARK: - Properties

    var id: UUID

    /// Run label/name provided by Claude during testing
    var name: String

    /// Device information (e.g., "iPhone 15 Pro")
    var deviceInfo: String?

    /// When the run was created
    var createdAt: Date

    /// Whether the run has been marked as complete
    var isComplete: Bool

    // MARK: - Relationships

    /// Associated project (optional, may be nil if project deleted)
    var project: Project?

    /// Screenshots captured during this run, ordered by captureIndex
    @Relationship(deleteRule: .cascade, inverse: \Screenshot.run)
    var screenshots: [Screenshot] = []

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        name: String,
        deviceInfo: String? = nil,
        createdAt: Date = Date(),
        isComplete: Bool = false,
        project: Project? = nil
    ) {
        self.id = id
        self.name = name
        self.deviceInfo = deviceInfo
        self.createdAt = createdAt
        self.isComplete = isComplete
        self.project = project

        logDebug("Created simulator run: '\(name)' for device: \(deviceInfo ?? "unknown")", category: .data)
    }

    // MARK: - Computed Properties

    /// Display name for the run
    var displayName: String {
        if !name.isEmpty {
            return name
        }
        return "Run \(Self.shortDateFormatter.string(from: createdAt))"
    }

    /// Number of screenshots in this run
    var screenshotCount: Int {
        screenshots.count
    }

    /// Number of visible (non-hidden) screenshots
    var visibleScreenshotCount: Int {
        screenshots.filter { !$0.isHidden }.count
    }

    /// Screenshots sorted by capture index
    var sortedScreenshots: [Screenshot] {
        screenshots.sorted { $0.captureIndex < $1.captureIndex }
    }

    /// First screenshot for thumbnail preview
    var thumbnailScreenshot: Screenshot? {
        sortedScreenshots.first
    }

    /// Relative time since creation
    var relativeCreatedTime: String {
        RelativeTimeFormatter.format(createdAt)
    }

    /// Formatted creation date
    var formattedCreatedDate: String {
        Self.dateFormatter.string(from: createdAt)
    }

    /// Device display string
    var deviceDisplay: String {
        deviceInfo ?? "Unknown Device"
    }

    /// Summary text for display
    var summaryText: String {
        let countText = screenshotCount == 1 ? "1 screenshot" : "\(screenshotCount) screenshots"
        if let device = deviceInfo {
            return "\(countText) • \(device)"
        }
        return countText
    }

    // MARK: - Methods

    /// Marks the run as complete
    func markComplete() {
        isComplete = true
        logDebug("Marked run '\(name)' as complete with \(screenshotCount) screenshots", category: .data)
    }

    /// Adds a screenshot to this run
    func addScreenshot(_ screenshot: Screenshot) {
        screenshot.run = self
        screenshots.append(screenshot)
        logDebug("Added screenshot to run '\(name)' at index \(screenshot.captureIndex)", category: .data)
    }

    // MARK: - Private

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    private static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, HH:mm"
        return formatter
    }()
}

// MARK: - SimulatorRun Queries

extension SimulatorRun {
    /// Predicate for runs belonging to a specific project
    static func forProject(_ project: Project) -> Predicate<SimulatorRun> {
        let projectId = project.id
        return #Predicate<SimulatorRun> { run in
            run.project?.id == projectId
        }
    }

    /// Predicate for recent runs (within specified days)
    static func withinDays(_ days: Int) -> Predicate<SimulatorRun> {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        return #Predicate<SimulatorRun> { run in
            run.createdAt >= cutoffDate
        }
    }

    /// Predicate for searching by name
    static func matching(searchText: String) -> Predicate<SimulatorRun> {
        #Predicate<SimulatorRun> { run in
            run.name.localizedStandardContains(searchText)
        }
    }
}

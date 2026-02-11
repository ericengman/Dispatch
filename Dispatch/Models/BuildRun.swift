//
//  BuildRun.swift
//  Dispatch
//
//  Per-destination build state tracking with structured output lines
//

import Foundation

// MARK: - Build Status

enum BuildStatus: Equatable, Sendable {
    case queued
    case compiling(String) // Current file being compiled
    case linking
    case installing
    case launching
    case succeeded
    case failed(String) // Summary of failure
    case cancelled

    var isTerminal: Bool {
        switch self {
        case .succeeded, .failed, .cancelled: return true
        default: return false
        }
    }

    var isActive: Bool {
        switch self {
        case .compiling, .linking, .installing, .launching: return true
        default: return false
        }
    }

    var displayText: String {
        switch self {
        case .queued: return "Queued"
        case let .compiling(file): return "Compiling \(file)"
        case .linking: return "Linking..."
        case .installing: return "Installing..."
        case .launching: return "Launching..."
        case .succeeded: return "Succeeded"
        case let .failed(summary): return "Failed: \(summary)"
        case .cancelled: return "Cancelled"
        }
    }
}

// MARK: - Build Output Level

enum BuildOutputLevel: String, Codable, Sendable {
    case info
    case warning
    case error
}

// MARK: - Build Output Line

struct BuildOutputLine: Identifiable, Sendable {
    let id = UUID()
    let text: String
    let level: BuildOutputLevel
    let timestamp: Date

    init(text: String, level: BuildOutputLevel = .info) {
        self.text = text
        self.level = level
        timestamp = Date()
    }
}

// MARK: - Build Output Filter

enum BuildOutputFilter: String, CaseIterable, Codable, Sendable {
    case all
    case warningsAndErrors
    case errorsOnly

    var displayName: String {
        switch self {
        case .all: return "All"
        case .warningsAndErrors: return "W+E"
        case .errorsOnly: return "Err"
        }
    }
}

// MARK: - Build Run

@Observable
@MainActor
final class BuildRun: Identifiable {
    let id: UUID
    let destination: BuildDestination
    let scheme: String

    var status: BuildStatus = .queued
    var outputLines: [BuildOutputLine] = []
    var filterMode: BuildOutputFilter = .warningsAndErrors
    var customFilterText: String = ""
    var isCustomFilterActive: Bool = false
    var warningCount: Int = 0
    var errorCount: Int = 0
    var startTime: Date?
    var endTime: Date?

    /// Handle to the running process for cancellation
    var process: Process?

    /// Filtered output lines based on current filter mode and custom text filter
    var filteredOutputLines: [BuildOutputLine] {
        var lines: [BuildOutputLine]
        switch filterMode {
        case .all:
            lines = outputLines
        case .warningsAndErrors:
            lines = outputLines.filter { $0.level == .warning || $0.level == .error }
        case .errorsOnly:
            lines = outputLines.filter { $0.level == .error }
        }

        if isCustomFilterActive, !customFilterText.isEmpty {
            let query = customFilterText.lowercased()
            lines = lines.filter { $0.text.lowercased().contains(query) }
        }

        return lines
    }

    /// Last meaningful output line for condensed preview
    var lastOutputPreview: String {
        if let lastLine = outputLines.last(where: { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }) {
            return lastLine.text
        }
        return status.displayText
    }

    init(id: UUID = UUID(), destination: BuildDestination, scheme: String) {
        self.id = id
        self.destination = destination
        self.scheme = scheme

        // Restore persisted filter
        let key = "buildFilter.\(destination.id)"
        if let raw = UserDefaults.standard.string(forKey: key),
           let filter = BuildOutputFilter(rawValue: raw) {
            filterMode = filter
        }
    }

    func setFilter(_ filter: BuildOutputFilter) {
        filterMode = filter
        let key = "buildFilter.\(destination.id)"
        UserDefaults.standard.set(filter.rawValue, forKey: key)
    }

    func appendOutput(_ text: String, level: BuildOutputLevel = .info) {
        let line = BuildOutputLine(text: text, level: level)
        outputLines.append(line)

        switch level {
        case .warning: warningCount += 1
        case .error: errorCount += 1
        case .info: break
        }
    }
}

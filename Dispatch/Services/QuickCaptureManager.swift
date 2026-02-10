//
//  QuickCaptureManager.swift
//  Dispatch
//
//  Manages MRU list of recent quick captures with UserDefaults persistence.
//

import AppKit
import Combine
import Foundation

/// Manages the Most Recently Used (MRU) list of quick captures.
/// Persists to UserDefaults and provides reactive updates via @Published.
@MainActor
final class QuickCaptureManager: ObservableObject {
    // MARK: - Singleton

    static let shared = QuickCaptureManager()

    // MARK: - Constants

    private let maxRecent = 5
    private let userDefaultsKey = "recentQuickCaptures"

    // MARK: - Published Properties

    @Published private(set) var recentCaptures: [QuickCapture] = []

    // MARK: - Initialization

    private init() {
        loadFromUserDefaults()
        logDebug("QuickCaptureManager initialized with \(recentCaptures.count) recent captures", category: .capture)
    }

    // MARK: - Public API

    /// Adds a capture to the front of the MRU list.
    /// Deduplicates by ID and trims to maxRecent.
    func addRecent(_ capture: QuickCapture) {
        logDebug("Adding capture to MRU: \(capture.id)", category: .capture)

        // Remove existing entry with same ID (if any)
        recentCaptures.removeAll { $0.id == capture.id }

        // Insert at front
        recentCaptures.insert(capture, at: 0)

        // Trim to max
        if recentCaptures.count > maxRecent {
            recentCaptures = Array(recentCaptures.prefix(maxRecent))
        }

        saveToUserDefaults()
        logInfo("MRU list updated: \(recentCaptures.count) captures", category: .capture)
    }

    /// Removes a specific capture from the MRU list by ID.
    func removeRecent(id: UUID) {
        logDebug("Removing capture from MRU: \(id)", category: .capture)
        recentCaptures.removeAll { $0.id == id }
        saveToUserDefaults()
    }

    /// Clears all recent captures from the MRU list.
    func clearRecent() {
        logInfo("Clearing all recent captures", category: .capture)
        recentCaptures.removeAll()
        saveToUserDefaults()
    }

    // MARK: - Persistence

    private func loadFromUserDefaults() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else {
            logDebug("No saved captures in UserDefaults", category: .capture)
            return
        }

        do {
            let decoded = try JSONDecoder().decode([QuickCapture].self, from: data)

            // Filter out captures with missing files
            recentCaptures = decoded.filter { capture in
                let exists = FileManager.default.fileExists(atPath: capture.filePath)
                if !exists {
                    logDebug("Filtering out missing capture file: \(capture.filePath)", category: .capture)
                }
                return exists
            }

            // Save back if we filtered any out
            if recentCaptures.count != decoded.count {
                saveToUserDefaults()
            }

            logDebug("Loaded \(recentCaptures.count) captures from UserDefaults", category: .capture)
        } catch {
            logError("Failed to decode recent captures: \(error)", category: .capture)
            recentCaptures = []
        }
    }

    private func saveToUserDefaults() {
        do {
            let data = try JSONEncoder().encode(recentCaptures)
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
            logDebug("Saved \(recentCaptures.count) captures to UserDefaults", category: .capture)
        } catch {
            logError("Failed to encode recent captures: \(error)", category: .capture)
        }
    }
}

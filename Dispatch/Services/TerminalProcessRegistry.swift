import Foundation

/// Tracks active terminal process PIDs for crash recovery
/// PIDs persist to UserDefaults to enable orphan cleanup on relaunch
class TerminalProcessRegistry {
    static let shared = TerminalProcessRegistry()

    private let defaults = UserDefaults.standard
    private let defaultsKey = "Dispatch.ActiveProcessPIDs"
    private let lock = NSLock()
    private var activePIDs: Set<pid_t> = []

    private init() {
        loadPersistedPIDs()
    }

    private func loadPersistedPIDs() {
        lock.lock()
        defer { lock.unlock() }

        let stored = defaults.array(forKey: defaultsKey) as? [Int] ?? []
        activePIDs = Set(stored.map { pid_t($0) })

        logDebug("Loaded \(activePIDs.count) persisted PIDs", category: .terminal)
    }

    /// Register a spawned process PID for tracking
    func register(pid: pid_t) {
        guard pid > 0 else { return }

        lock.lock()
        defer { lock.unlock() }

        activePIDs.insert(pid)
        persist()

        logInfo("Registered process PID: \(pid)", category: .terminal)
    }

    /// Unregister a PID when process exits (natural or forced)
    func unregister(pid: pid_t) {
        lock.lock()
        defer { lock.unlock() }

        let wasPresent = activePIDs.remove(pid) != nil
        if wasPresent {
            persist()
            logInfo("Unregistered process PID: \(pid)", category: .terminal)
        }
    }

    private func persist() {
        // Convert pid_t to Int for UserDefaults storage
        let pidArray = Array(activePIDs).map { Int($0) }
        defaults.set(pidArray, forKey: defaultsKey)
        // DO NOT call synchronize() - deprecated, automatic sync is sufficient
    }

    /// Get all tracked PIDs (for orphan cleanup on launch)
    func getAllPIDs() -> Set<pid_t> {
        lock.lock()
        defer { lock.unlock() }
        return activePIDs
    }

    /// Check if a specific PID is being tracked
    func contains(pid: pid_t) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return activePIDs.contains(pid)
    }
}

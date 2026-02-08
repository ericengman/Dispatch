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

    // MARK: - Process Lifecycle

    /// Check if a process is still running using kill(pid, 0)
    func isProcessRunning(_ pid: pid_t) -> Bool {
        let result = kill(pid, 0)

        if result == 0 {
            return true // Process exists and we have permission
        }

        // Check errno to distinguish cases
        switch errno {
        case ESRCH:
            return false // No such process
        case EPERM:
            return true // Process exists but no permission (still running)
        default:
            logDebug("Unexpected errno \(errno) checking PID \(pid)", category: .terminal)
            return false
        }
    }

    /// Terminate a process group gracefully (SIGTERM -> wait -> SIGKILL)
    /// - Parameters:
    ///   - pgid: Process group ID (same as shell PID due to POSIX_SPAWN_SETSID)
    ///   - timeout: Seconds to wait for graceful shutdown before SIGKILL
    func terminateProcessGroupGracefully(pgid: pid_t, timeout: TimeInterval = 3.0) {
        // Stage 1: Send SIGTERM to process group
        let termResult = killpg(pgid, SIGTERM)

        if termResult == -1, errno == ESRCH {
            logDebug("Process group \(pgid) already terminated", category: .terminal)
            return
        }

        logDebug("Sent SIGTERM to process group \(pgid)", category: .terminal)

        // Stage 2: Wait for graceful shutdown
        let deadline = Date().addingTimeInterval(timeout)
        var gracefullyTerminated = false

        while Date() < deadline {
            if !isProcessRunning(pgid) {
                gracefullyTerminated = true
                logDebug("Process group \(pgid) terminated gracefully", category: .terminal)
                break
            }
            Thread.sleep(forTimeInterval: 0.1)
        }

        // Stage 3: Force termination if still running
        if !gracefullyTerminated {
            logDebug("Process group \(pgid) timeout, sending SIGKILL", category: .terminal)
            killpg(pgid, SIGKILL)
            Thread.sleep(forTimeInterval: 0.1)
        }
    }

    /// Clean up orphaned processes from crashed/force-quit sessions
    /// Call this on app launch
    func cleanupOrphanedProcesses() {
        let persistedPIDs = getAllPIDs()

        guard !persistedPIDs.isEmpty else {
            logDebug("No persisted PIDs to clean up", category: .terminal)
            return
        }

        logInfo("Checking \(persistedPIDs.count) persisted PIDs for orphans", category: .terminal)

        for pid in persistedPIDs {
            if isProcessRunning(pid) {
                logInfo("Found orphaned process \(pid), terminating process group", category: .terminal)
                terminateProcessGroupGracefully(pgid: pid, timeout: 2.0)
            } else {
                logDebug("Stale PID \(pid) no longer running", category: .terminal)
            }

            // Remove from registry either way
            unregister(pid: pid)
        }

        logInfo("Orphan cleanup complete", category: .terminal)
    }
}

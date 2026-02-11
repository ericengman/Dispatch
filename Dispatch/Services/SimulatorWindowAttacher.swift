//
//  SimulatorWindowAttacher.swift
//  Dispatch
//
//  Manages simulator window positioning — attaches simulator windows
//  to the right side of Dispatch's main window and keeps them in sync.
//

import Cocoa
import Foundation

@Observable
@MainActor
final class SimulatorWindowAttacher {
    static let shared = SimulatorWindowAttacher()

    // MARK: - Public State

    var attachments: [SimulatorAttachment] = []

    // MARK: - Private State

    private var moveObserver: NSObjectProtocol?
    private var resizeObserver: NSObjectProtocol?
    private var pollTimer: Task<Void, Never>?

    // MARK: - Init

    private init() {
        logDebug("SimulatorWindowAttacher initialized", category: .build)
    }

    // MARK: - Public API

    /// Attach a simulator window to Dispatch's right edge.
    /// Starts polling for the simulator window if not found immediately.
    func attachSimulator(udid: String, deviceName: String) {
        // Don't re-attach if already tracked
        guard !attachments.contains(where: { $0.simulatorUDID == udid && $0.isAttached }) else {
            logDebug("Simulator \(deviceName) already attached", category: .build)
            return
        }

        let attachment = SimulatorAttachment(simulatorUDID: udid, deviceName: deviceName)
        attachments.append(attachment)
        logInfo("Attaching simulator \(deviceName) (UDID: \(udid))", category: .build)

        // Start observing window moves if not already
        startWindowObservation()

        // Poll for the simulator window
        Task {
            await findAndAttachWindow(for: attachment)
        }
    }

    /// Detach a simulator (stop tracking position)
    func detachSimulator(id: UUID) {
        guard let index = attachments.firstIndex(where: { $0.id == id }) else { return }
        attachments[index].isAttached = false
        logInfo("Detached simulator \(attachments[index].deviceName)", category: .build)

        // Stop observation if no attached simulators remain
        if !attachments.contains(where: { $0.isAttached }) {
            stopWindowObservation()
        }
    }

    /// Reattach a previously detached simulator
    func reattachSimulator(id: UUID) {
        guard let index = attachments.firstIndex(where: { $0.id == id }) else { return }
        attachments[index].isAttached = true
        startWindowObservation()
        updatePositions()
        logInfo("Reattached simulator \(attachments[index].deviceName)", category: .build)
    }

    /// Remove a simulator attachment entirely
    func removeAttachment(id: UUID) {
        attachments.removeAll { $0.id == id }
        if !attachments.contains(where: { $0.isAttached }) {
            stopWindowObservation()
        }
    }

    // MARK: - Window Discovery

    private func findAndAttachWindow(for attachment: SimulatorAttachment) async {
        // Poll up to 10 times over 5 seconds to find the window
        for attempt in 0 ..< 10 {
            if let windowNumber = findSimulatorWindow(deviceName: attachment.deviceName) {
                attachment.windowNumber = windowNumber
                logInfo("Found simulator window #\(windowNumber) for \(attachment.deviceName) on attempt \(attempt + 1)", category: .build)
                updatePositions()
                return
            }
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
        }
        logWarning("Could not find simulator window for \(attachment.deviceName) after polling", category: .build)
    }

    /// Find a Simulator.app window matching the device name
    private func findSimulatorWindow(deviceName: String) -> Int? {
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        for window in windowList {
            guard let ownerName = window[kCGWindowOwnerName as String] as? String,
                  ownerName == "Simulator",
                  let windowName = window[kCGWindowName as String] as? String,
                  windowName.contains(deviceName),
                  let windowNumber = window[kCGWindowNumber as String] as? Int
            else { continue }

            return windowNumber
        }
        return nil
    }

    // MARK: - Position Management

    /// Update all attached simulator positions relative to Dispatch's main window
    func updatePositions() {
        guard let mainWindow = NSApp.mainWindow else { return }
        let mainFrame = mainWindow.frame

        // Position simulators to the right of Dispatch window, stacked horizontally
        var xOffset: CGFloat = mainFrame.maxX + 4 // 4pt gap

        for attachment in attachments where attachment.isAttached {
            guard let windowNumber = attachment.windowNumber else { continue }

            // Set window position via CGWindow API or AppleScript
            setSimulatorWindowPosition(windowNumber: windowNumber, x: xOffset, y: mainFrame.origin.y, height: mainFrame.height)

            // Estimate simulator width (typical iPhone simulator ~400pt)
            xOffset += 400 + 4
        }
    }

    private func setSimulatorWindowPosition(windowNumber: Int, x: CGFloat, y: CGFloat, height: CGFloat) {
        // Use AppleScript to position Simulator window
        // CGWindow doesn't provide a direct "set position" API, so AppleScript is the pragmatic choice
        let script = """
        tell application "Simulator"
            try
                set targetWindow to missing value
                repeat with w in windows
                    if (id of w) is \(windowNumber) then
                        set targetWindow to w
                        exit repeat
                    end if
                end repeat
                if targetWindow is not missing value then
                    set bounds of targetWindow to {\(Int(x)), \(Int(y)), \(Int(x + 400)), \(Int(y + height))}
                end if
            end try
        end tell
        """

        DispatchQueue.global(qos: .utility).async {
            if let appleScript = NSAppleScript(source: script) {
                var error: NSDictionary?
                appleScript.executeAndReturnError(&error)
                if let error {
                    logError("AppleScript error positioning simulator: \(error)", category: .build)
                }
            }
        }
    }

    // MARK: - Window Observation

    private func startWindowObservation() {
        guard moveObserver == nil else { return }

        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: NSApp.mainWindow,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updatePositions()
            }
        }

        resizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: NSApp.mainWindow,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updatePositions()
            }
        }

        logDebug("Started window observation for simulator attachment", category: .build)
    }

    private func stopWindowObservation() {
        if let observer = moveObserver {
            NotificationCenter.default.removeObserver(observer)
            moveObserver = nil
        }
        if let observer = resizeObserver {
            NotificationCenter.default.removeObserver(observer)
            resizeObserver = nil
        }
        logDebug("Stopped window observation for simulator attachment", category: .build)
    }
}

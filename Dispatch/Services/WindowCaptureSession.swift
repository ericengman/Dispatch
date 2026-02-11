//
//  WindowCaptureSession.swift
//  Dispatch
//
//  Manages an interactive window capture session with highlight overlay and control buttons
//

import AppKit
import Foundation
import ScreenCaptureKit

// MARK: - Window Capture Session

/// Manages an interactive window capture session
/// Flow: Hover to highlight window and show controls → Capture or Cancel
@MainActor
final class WindowCaptureSession {
    // MARK: - Types

    enum SessionState {
        case idle
        case selecting // User is hovering over windows
        case capturing // Taking the screenshot
        case completed // Session ended
    }

    struct WindowInfo {
        let windowID: CGWindowID
        let ownerPID: pid_t
        let ownerName: String
        let title: String
        let frame: CGRect
    }

    // MARK: - Properties

    private var state: SessionState = .idle
    private var hoveredWindow: WindowInfo?
    private var highlightWindow: NSWindow?
    private var controlPanel: NSWindow?
    private var mouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var keyMonitor: Any?
    private var localKeyMonitor: Any?

    private var continuation: CheckedContinuation<CaptureResult, Never>?

    // MARK: - Public API

    /// Starts a window capture session
    /// - Returns: CaptureResult when the session completes
    func start() async -> CaptureResult {
        logDebug("Starting window capture session", category: .capture)

        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            self.state = .selecting

            // Start monitoring mouse movement
            self.startMouseTracking()

            // Start monitoring for Escape key
            self.startKeyMonitoring()

            logDebug("Window capture session started - waiting for selection", category: .capture)
        }
    }

    // MARK: - Mouse Tracking

    private func startMouseTracking() {
        // Monitor mouse movement globally
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.state == .selecting else { return }
                self.updateHighlight(at: NSEvent.mouseLocation)
            }
        }

        // Also monitor local events (when Dispatch is focused)
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            Task { @MainActor in
                guard let self, self.state == .selecting else { return }
                self.updateHighlight(at: NSEvent.mouseLocation)
            }
            return event
        }
    }

    private func updateHighlight(at point: NSPoint) {
        guard let windowInfo = getWindowInfo(at: point) else {
            hideHighlight()
            hideControlPanel()
            hoveredWindow = nil
            return
        }

        hoveredWindow = windowInfo
        showHighlight(for: windowInfo)
        showControlPanel(for: windowInfo)
    }

    // MARK: - Key Monitoring

    private func startKeyMonitoring() {
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Escape key
                Task { @MainActor in
                    self?.cancel()
                }
            }
        }

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Escape key
                Task { @MainActor in
                    self?.cancel()
                }
                return nil // Consume the event
            }
            return event
        }
    }

    // MARK: - Window Detection

    private func getWindowInfo(at point: NSPoint) -> WindowInfo? {
        // Convert from bottom-left origin to top-left origin for CGWindowList
        guard let mainScreen = NSScreen.main else { return nil }
        let screenHeight = mainScreen.frame.height
        let cgPoint = CGPoint(x: point.x, y: screenHeight - point.y)

        // Get all on-screen windows
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        // Find the topmost window containing the point
        for windowDict in windowList {
            guard let windowID = windowDict[kCGWindowNumber as String] as? CGWindowID,
                  let ownerPID = windowDict[kCGWindowOwnerPID as String] as? pid_t,
                  let boundsDict = windowDict[kCGWindowBounds as String] as? [String: CGFloat],
                  let layer = windowDict[kCGWindowLayer as String] as? Int
            else {
                continue
            }

            // Skip non-normal window layers (menu bar, overlays, etc.)
            // Layer 0 = normal windows, negative = menu bar, positive = overlays
            // Note: We intentionally allow capturing Dispatch's own windows
            if layer != 0 {
                continue
            }

            // Skip windows with no alpha (invisible)
            if let alpha = windowDict[kCGWindowAlpha as String] as? CGFloat, alpha < 0.1 {
                continue
            }

            // Skip Dock and other system UI elements
            let ownerName = windowDict[kCGWindowOwnerName as String] as? String ?? ""
            if ownerName == "Dock" || ownerName == "Window Server" || ownerName == "SystemUIServer" {
                continue
            }

            let frame = CGRect(
                x: boundsDict["X"] ?? 0,
                y: boundsDict["Y"] ?? 0,
                width: boundsDict["Width"] ?? 0,
                height: boundsDict["Height"] ?? 0
            )

            // Check if point is in window frame
            if frame.contains(cgPoint) {
                let title = windowDict[kCGWindowName as String] as? String ?? ""

                // Convert back to NSWindow coordinates (bottom-left origin)
                let nsFrame = CGRect(
                    x: frame.origin.x,
                    y: screenHeight - frame.origin.y - frame.height,
                    width: frame.width,
                    height: frame.height
                )

                return WindowInfo(
                    windowID: windowID,
                    ownerPID: ownerPID,
                    ownerName: ownerName,
                    title: title,
                    frame: nsFrame
                )
            }
        }

        return nil
    }

    // MARK: - Highlight Window

    private func showHighlight(for windowInfo: WindowInfo) {
        if highlightWindow == nil {
            createHighlightWindow()
        }

        guard let highlight = highlightWindow else { return }

        // Position highlight around the target window
        let inset: CGFloat = -4 // Expand slightly beyond window
        let highlightFrame = windowInfo.frame.insetBy(dx: inset, dy: inset)

        highlight.setFrame(highlightFrame, display: true)
        highlight.orderFront(nil)
    }

    private func hideHighlight() {
        highlightWindow?.orderOut(nil)
    }

    private func createHighlightWindow() {
        let window = NSWindow(
            contentRect: .zero,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.ignoresMouseEvents = true
        window.hasShadow = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        // Create border view
        let borderView = HighlightBorderView()
        window.contentView = borderView

        highlightWindow = window
    }

    // MARK: - Control Panel

    private func showControlPanel(for windowInfo: WindowInfo) {
        if controlPanel == nil {
            createControlPanel()
        }

        guard let panel = controlPanel else { return }

        // Position at top-left of the hovered window
        let panelWidth: CGFloat = 240
        let panelHeight: CGFloat = 56
        let padding: CGFloat = 10

        let panelOrigin = CGPoint(
            x: windowInfo.frame.origin.x + padding,
            y: windowInfo.frame.origin.y + windowInfo.frame.height - panelHeight - padding
        )

        panel.setFrame(CGRect(origin: panelOrigin, size: CGSize(width: panelWidth, height: panelHeight)), display: true)
        panel.orderFront(nil)
    }

    private func hideControlPanel() {
        controlPanel?.orderOut(nil)
    }

    private func createControlPanel() {
        let panel = NSPanel(
            contentRect: CGRect(x: 0, y: 0, width: 240, height: 56),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        // Blur background
        let visualEffect = NSVisualEffectView(frame: panel.contentView!.bounds)
        visualEffect.autoresizingMask = [.width, .height]
        visualEffect.material = .hudWindow
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 12
        visualEffect.layer?.masksToBounds = true
        panel.contentView?.addSubview(visualEffect)

        // Create buttons with blue styling
        let stackView = NSStackView()
        stackView.orientation = .horizontal
        stackView.spacing = 12
        stackView.translatesAutoresizingMaskIntoConstraints = false

        let cancelButton = createStyledButton(title: "Cancel", isPrimary: false)
        cancelButton.target = self
        cancelButton.action = #selector(cancelButtonClicked)

        let captureButton = createStyledButton(title: "📸 Capture", isPrimary: true)
        captureButton.target = self
        captureButton.action = #selector(captureButtonClicked)
        captureButton.keyEquivalent = "\r" // Enter key

        stackView.addArrangedSubview(cancelButton)
        stackView.addArrangedSubview(captureButton)

        visualEffect.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: visualEffect.centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: visualEffect.centerYAnchor)
        ])

        controlPanel = panel
    }

    private func createStyledButton(title: String, isPrimary: Bool) -> NSButton {
        let button = NSButton(title: title, target: nil, action: nil)
        button.bezelStyle = .rounded
        button.isBordered = false
        button.wantsLayer = true

        // Blue styling matching highlight border
        let blueColor = NSColor.systemBlue

        if isPrimary {
            // Filled blue button
            button.layer?.backgroundColor = blueColor.cgColor
            button.contentTintColor = .white
        } else {
            // Outlined blue button
            button.layer?.backgroundColor = NSColor.clear.cgColor
            button.layer?.borderColor = blueColor.cgColor
            button.layer?.borderWidth = 2
            button.contentTintColor = blueColor
        }

        button.layer?.cornerRadius = 8
        button.font = NSFont.systemFont(ofSize: 14, weight: .medium)

        // Full-sized tap targets covering entire button bounds
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: 100),
            button.heightAnchor.constraint(equalToConstant: 38)
        ])

        return button
    }

    @objc private func cancelButtonClicked() {
        cancel()
    }

    @objc private func captureButtonClicked() {
        capture()
    }

    // MARK: - Actions

    private func cancel() {
        logInfo("Window capture cancelled", category: .capture)
        cleanup()
        continuation?.resume(returning: .cancelled)
        continuation = nil
    }

    private func capture() {
        guard let windowInfo = hoveredWindow else {
            logError("No window under cursor for capture", category: .capture)
            cancel()
            return
        }

        state = .capturing
        stopMouseTracking()
        hideControlPanel()
        hideHighlight()

        logDebug("Capturing window ID: \(windowInfo.windowID)", category: .capture)

        // Capture using screencapture -l <windowID>
        let source = CaptureSource(appName: windowInfo.ownerName, windowTitle: windowInfo.title)
        Task {
            let result = await captureWindow(windowID: windowInfo.windowID, source: source)
            cleanup()
            continuation?.resume(returning: result)
            continuation = nil
        }
    }

    private func captureWindow(windowID: CGWindowID, source: CaptureSource) async -> CaptureResult {
        // Ensure captures directory exists
        let capturesDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Dispatch/QuickCaptures", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: capturesDirectory, withIntermediateDirectories: true)
        } catch {
            logError("Failed to create captures directory: \(error)", category: .capture)
            return .error(error)
        }

        let filename = "\(UUID().uuidString).png"
        let outputPath = capturesDirectory.appendingPathComponent(filename)

        // Use screencapture -l to capture specific window
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = [
            "-l", String(windowID), // Capture specific window by ID
            "-x", // No sound
            outputPath.path
        ]

        do {
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus == 0 && FileManager.default.fileExists(atPath: outputPath.path) {
                logInfo("Window captured: \(filename)", category: .capture)
                return .success(outputPath, source)
            } else {
                let error = NSError(
                    domain: "WindowCaptureSession",
                    code: Int(process.terminationStatus),
                    userInfo: [NSLocalizedDescriptionKey: "screencapture failed with status \(process.terminationStatus)"]
                )
                return .error(error)
            }
        } catch {
            logError("Failed to run screencapture: \(error)", category: .capture)
            return .error(error)
        }
    }

    // MARK: - Cleanup

    private func stopMouseTracking() {
        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
            mouseMonitor = nil
        }
        if let monitor = localMouseMonitor {
            NSEvent.removeMonitor(monitor)
            localMouseMonitor = nil
        }
    }

    private func stopKeyMonitoring() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
        if let monitor = localKeyMonitor {
            NSEvent.removeMonitor(monitor)
            localKeyMonitor = nil
        }
    }

    private func cleanup() {
        state = .completed
        stopMouseTracking()
        stopKeyMonitoring()
        hideHighlight()
        hideControlPanel()
        highlightWindow = nil
        controlPanel = nil
        hoveredWindow = nil
    }
}

// MARK: - Highlight Border View

private class HighlightBorderView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // Draw blue border
        let borderColor = NSColor.systemBlue.withAlphaComponent(0.8)
        borderColor.setStroke()

        let borderPath = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 6, yRadius: 6)
        borderPath.lineWidth = 4
        borderPath.stroke()

        // Light fill for visibility
        let fillColor = NSColor.systemBlue.withAlphaComponent(0.1)
        fillColor.setFill()
        borderPath.fill()
    }
}

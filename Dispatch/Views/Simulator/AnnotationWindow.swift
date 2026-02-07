//
//  AnnotationWindow.swift
//  Dispatch
//
//  Separate window for detailed screenshot annotation and prompt composition
//

import AppKit
import Combine
import SwiftUI

// MARK: - Annotation Window Controller

/// Manages the annotation window lifecycle
@MainActor
final class AnnotationWindowController: ObservableObject {
    // MARK: - Singleton

    static let shared = AnnotationWindowController()

    // MARK: - Published Properties

    @Published var isOpen: Bool = false
    @Published var currentRun: SimulatorRun?
    @Published var initialScreenshot: Screenshot?

    // MARK: - Private Properties

    private var window: NSWindow?

    private init() {}

    // MARK: - Window Management

    /// Opens the annotation window with a run and optional initial screenshot
    func open(run: SimulatorRun, screenshot: Screenshot? = nil) {
        currentRun = run
        initialScreenshot = screenshot ?? run.sortedScreenshots.first

        if window == nil {
            createWindow()
        }

        window?.makeKeyAndOrderFront(nil)
        isOpen = true

        logInfo("Opened annotation window for run: \(run.displayName)", category: .simulator)
    }

    /// Closes the annotation window
    func close() {
        window?.close()
        isOpen = false
        currentRun = nil
        initialScreenshot = nil

        logDebug("Closed annotation window", category: .simulator)
    }

    // MARK: - Private Methods

    private func createWindow() {
        let contentView = AnnotationWindowContent()
            .environmentObject(self)
            .environmentObject(AnnotationViewModel())

        let hostingController = NSHostingController(rootView: contentView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = "Screenshot Annotation"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 1200, height: 800))
        window.minSize = NSSize(width: 1000, height: 700)
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = WindowDelegate(controller: self)

        self.window = window
    }

    // MARK: - Window Delegate

    private class WindowDelegate: NSObject, NSWindowDelegate {
        weak var controller: AnnotationWindowController?

        init(controller: AnnotationWindowController) {
            self.controller = controller
        }

        func windowWillClose(_: Notification) {
            Task { @MainActor in
                controller?.isOpen = false
            }
        }
    }
}

// MARK: - Annotation Window Content

struct AnnotationWindowContent: View {
    @EnvironmentObject private var windowController: AnnotationWindowController
    @EnvironmentObject private var annotationVM: AnnotationViewModel

    // MARK: - State

    @State private var selectedScreenshot: Screenshot?
    @State private var dispatchError: String?
    @State private var showingDispatchError = false
    @State private var libraryInstalled = false
    @State private var hookInstalled = false

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Main content area
            HSplitView {
                // Left: Canvas and toolbar
                leftPanel
                    .frame(minWidth: 600)

                // Right: Send queue and prompt
                rightPanel
                    .frame(minWidth: 280, maxWidth: 350)
            }

            Divider()

            // Bottom: Screenshot strip
            bottomStrip
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .alert("Dispatch Failed", isPresented: $showingDispatchError) {
            Button("OK", role: .cancel) {
                dispatchError = nil
            }
            Button("Open Settings") {
                openTerminalSettings()
            }
        } message: {
            Text(dispatchError ?? "Failed to send to Terminal. Check automation permissions.")
        }
        .onAppear {
            setupInitialState()
            checkIntegrationStatus()
        }
        .onKeyPress(keys: [.escape]) { _ in
            windowController.close()
            return .handled
        }
        .onKeyPress(keys: [.delete, .deleteForward]) { _ in
            handleDeleteKey()
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "cdartzCDART")) { press in
            handleToolShortcut(press.characters)
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "1234567")) { press in
            handleColorShortcut(press.characters)
        }
    }

    // MARK: - Left Panel

    private var leftPanel: some View {
        VStack(spacing: 0) {
            // Canvas area
            AnnotationCanvasView()
                .environmentObject(annotationVM)

            Divider()

            // Toolbar
            AnnotationToolbar()
                .environmentObject(annotationVM)
        }
    }

    // MARK: - Right Panel

    private var rightPanel: some View {
        VStack(spacing: 0) {
            // Send queue header
            HStack {
                Label("Send Queue", systemImage: "tray.and.arrow.up")
                    .font(.headline)

                Spacer()

                Text("\(annotationVM.queueCount)/5")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()

            // Send queue
            SendQueueView()
                .environmentObject(annotationVM)
                .frame(height: 120)

            Divider()

            // Prompt input
            VStack(alignment: .leading, spacing: 8) {
                Text("Prompt")
                    .font(.headline)

                TextEditor(text: $annotationVM.promptText)
                    .font(.body)
                    .frame(minHeight: 100)
                    .overlay(
                        Group {
                            if annotationVM.promptText.isEmpty {
                                Text("Describe the issue or ask Claude to fix...")
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 8)
                                    .padding(.leading, 4)
                            }
                        },
                        alignment: .topLeading
                    )
                    .scrollContentBackground(.hidden)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1)
                    )
            }
            .padding()

            Spacer()

            // Dispatch button
            dispatchSection
                .padding()
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }

    // MARK: - Dispatch Section

    private var dispatchSection: some View {
        VStack(spacing: 12) {
            // Integration status
            integrationStatusView

            // Keyboard shortcut hint
            HStack {
                Spacer()
                Text("Press")
                    .foregroundStyle(.secondary)
                Text("⌘⏎")
                    .font(.system(.caption, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                Text("to dispatch")
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .font(.caption)

            // Dispatch button
            Button {
                Task {
                    await dispatch()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "paperplane.fill")
                    Text("Dispatch to Terminal")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canDispatch)
            .keyboardShortcut(.return, modifiers: .command)
        }
    }

    @ViewBuilder
    private var integrationStatusView: some View {
        HStack(spacing: 4) {
            Image(systemName: statusIcon)
                .font(.caption2)
                .foregroundStyle(statusColor)
            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Bottom Strip

    private var bottomStrip: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("All Screenshots")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                if let run = windowController.currentRun {
                    Text("\(run.screenshotCount) total")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)

            if let run = windowController.currentRun {
                BottomStripView(
                    screenshots: run.sortedScreenshots,
                    selectedScreenshot: selectedScreenshot,
                    queuedIds: Set(annotationVM.sendQueue.map { $0.screenshot.id }),
                    onSelect: { screenshot in
                        selectScreenshot(screenshot)
                    }
                )
                .environmentObject(annotationVM)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
    }

    // MARK: - Computed Properties

    private var canDispatch: Bool {
        annotationVM.hasQueuedImages && !annotationVM.promptText.isEmpty
    }

    private var statusIcon: String {
        switch (libraryInstalled, hookInstalled) {
        case (true, true): return "checkmark.circle.fill"
        case (true, false): return "exclamationmark.circle"
        case (false, _): return "xmark.circle"
        }
    }

    private var statusColor: Color {
        switch (libraryInstalled, hookInstalled) {
        case (true, true): return .green
        case (true, false): return .orange
        case (false, _): return .red
        }
    }

    private var statusText: String {
        switch (libraryInstalled, hookInstalled) {
        case (true, true): return "Integration ready"
        case (true, false): return "Library ready, hook inactive"
        case (false, _): return "Library not installed"
        }
    }

    // MARK: - Actions

    private func setupInitialState() {
        if let screenshot = windowController.initialScreenshot {
            selectScreenshot(screenshot)
        }
    }

    private func selectScreenshot(_ screenshot: Screenshot) {
        selectedScreenshot = screenshot
        annotationVM.loadScreenshot(screenshot)
    }

    private func dispatch() async {
        guard canDispatch else { return }

        // Capture count before dispatch
        let imageCount = annotationVM.queueCount
        let prompt = annotationVM.promptText

        // Copy images to clipboard
        let success = await annotationVM.copyToClipboard()

        if success {
            do {
                // Paste images first, then send prompt
                try await TerminalService.shared.pasteFromClipboard()

                // Small delay to ensure paste completes before typing
                try await Task.sleep(nanoseconds: 200_000_000) // 200ms

                try await TerminalService.shared.sendTextToActiveWindow(prompt)

                // Clear state on success
                annotationVM.handleDispatchComplete()

                logInfo("Dispatched \(imageCount) images with prompt", category: .simulator)
            } catch let error as TerminalServiceError {
                // Handle specific Terminal errors with helpful messages
                handleDispatchError(error)
            } catch {
                // Generic error
                dispatchError = error.localizedDescription
                showingDispatchError = true
                error.log(category: .simulator, context: "Failed to dispatch images")
            }
        } else {
            // Clipboard copy failure
            dispatchError = "Failed to copy images to clipboard. Check available memory."
            showingDispatchError = true
            logError("Failed to copy images to clipboard", category: .simulator)
        }
    }

    private func handleDispatchError(_ error: TerminalServiceError) {
        switch error {
        case .permissionDenied:
            dispatchError = "Terminal automation permission denied. Grant access in System Settings > Privacy & Security > Automation."
        case .accessibilityPermissionDenied:
            dispatchError = "Accessibility permission denied. Grant access in System Settings > Privacy & Security > Accessibility."
        case .terminalNotRunning:
            dispatchError = "Terminal.app is not running. Launch Terminal and try again."
        case .noWindowsOpen:
            dispatchError = "No Terminal windows are open. Open a Terminal window and try again."
        default:
            dispatchError = error.localizedDescription
        }
        showingDispatchError = true
        error.log(category: .simulator, context: "Dispatch failed")
    }

    private func openTerminalSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }

    private func checkIntegrationStatus() {
        Task {
            // Check library
            let libraryPath = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".claude/lib/dispatch.sh")
            let exists = FileManager.default.fileExists(atPath: libraryPath.path)
            if exists {
                let attributes = try? FileManager.default.attributesOfItem(atPath: libraryPath.path)
                let permissions = attributes?[.posixPermissions] as? Int ?? 0
                libraryInstalled = (permissions & 0o111) != 0
            } else {
                libraryInstalled = false
            }

            // Check hook
            await HookInstallerManager.shared.refreshStatus()
            hookInstalled = HookInstallerManager.shared.status.isInstalled
        }
    }

    // MARK: - Keyboard Shortcuts

    private func handleDeleteKey() -> KeyPress.Result {
        // Remove the active image from the queue if it's queued
        guard let active = annotationVM.activeImage else { return .ignored }

        if annotationVM.sendQueue.contains(where: { $0.id == active.id }) {
            annotationVM.removeFromQueue(id: active.id)
            logDebug("Removed active image from queue via Delete key", category: .simulator)
            return .handled
        }

        return .ignored
    }

    private func handleToolShortcut(_ characters: String) -> KeyPress.Result {
        guard let char = characters.lowercased().first else { return .ignored }

        switch char {
        case "c":
            annotationVM.selectTool(.crop)
        case "d":
            annotationVM.selectTool(.freehand)
        case "a":
            annotationVM.selectTool(.arrow)
        case "r":
            annotationVM.selectTool(.rectangle)
        case "t":
            annotationVM.selectTool(.text)
        default:
            return .ignored
        }
        return .handled
    }

    private func handleColorShortcut(_ characters: String) -> KeyPress.Result {
        guard let char = characters.first,
              let number = Int(String(char)),
              let color = AnnotationColor.fromShortcut(number)
        else {
            return .ignored
        }

        annotationVM.selectColor(color)
        return .handled
    }
}

// MARK: - Preview

#Preview {
    AnnotationWindowContent()
        .environmentObject(AnnotationWindowController.shared)
        .environmentObject(AnnotationViewModel())
        .frame(width: 1200, height: 800)
}

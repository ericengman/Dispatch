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
    private var windowDelegate: WindowDelegate?

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
        let delegate = WindowDelegate(controller: self)
        windowDelegate = delegate
        window.delegate = delegate

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

    // MARK: - Focus

    private enum FocusField: Hashable {
        case prompt
    }

    @FocusState private var focusedField: FocusField?

    // MARK: - State

    @State private var isSessionPickerExpanded = false
    @State private var selectedScreenshot: Screenshot?
    @State private var selectedSessionId: UUID?
    @State private var dispatchError: String?
    @State private var showingDispatchError = false
    @State private var libraryInstalled = false
    @State private var hookInstalled = false

    private var sessionManager: TerminalSessionManager { TerminalSessionManager.shared }
    private var bridge: EmbeddedTerminalBridge { EmbeddedTerminalBridge.shared }

    /// All sessions with an available terminal
    private var availableSessions: [TerminalSession] {
        sessionManager.sessions.filter { bridge.isAvailable(sessionId: $0.id) }
    }

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
        } message: {
            Text(dispatchError ?? "Failed to dispatch to embedded terminal.")
        }
        .onAppear {
            setupInitialState()
            checkIntegrationStatus()
            // Auto-select session: prefer active, fall back to first available
            let available = sessionManager.sessions.filter { sessionManager.terminal(for: $0.id) != nil }
            if let activeId = sessionManager.activeSessionId,
               available.contains(where: { $0.id == activeId }) {
                selectedSessionId = activeId
            } else {
                selectedSessionId = available.first?.id
            }
            focusedField = .prompt
        }
        .onKeyPress(keys: [.escape]) { _ in
            windowController.close()
            return .handled
        }
        .onKeyPress(keys: [.return]) { press in
            guard press.modifiers.contains(.command),
                  let sessionId = selectedSessionId,
                  annotationVM.hasQueuedImages,
                  !annotationVM.promptText.isEmpty
            else { return .ignored }
            Task { await dispatch(to: sessionId) }
            return .handled
        }
        .onKeyPress(keys: [.delete, .deleteForward]) { _ in
            handleDeleteKey()
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "12345"), phases: .down, action: { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            return handleToolShortcut(press.characters)
        })
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
                    .focused($focusedField, equals: .prompt)
                    .onKeyPress(.tab) {
                        isSessionPickerExpanded = true
                        return .handled
                    }
            }
            .padding()

            Spacer()

            // Integration status + dispatch button
            VStack(spacing: 12) {
                integrationStatusView

                CaptureDispatchButton(
                    selectedSessionId: $selectedSessionId,
                    isExpanded: $isSessionPickerExpanded,
                    sessions: availableSessions,
                    isDisabled: !annotationVM.hasQueuedImages || annotationVM.promptText.isEmpty,
                    onDispatch: { sessionId in
                        await dispatch(to: sessionId)
                    },
                    onNewSession: createNewSession
                )
            }
            .padding()
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
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

    private func createNewSession() {
        guard let project = windowController.currentRun?.project else {
            logWarning("Cannot create session: no project associated with current run", category: .simulator)
            return
        }

        let session = sessionManager.createSession(
            name: project.name,
            workingDirectory: project.path
        )

        if let session {
            selectedSessionId = session.id
            logInfo("Created new session '\(session.name)' from annotation window", category: .simulator)
        }
    }

    private func dispatch(to sessionId: UUID) async {
        // Verify session is still available for dispatch
        guard bridge.isAvailable(sessionId: sessionId) else {
            dispatchError = "Session is no longer available. Select a different session or open a new terminal."
            showingDispatchError = true
            return
        }

        // Render annotated images and save to temp files for Claude Code to read
        let imagePaths = await saveRenderedImages()

        guard !imagePaths.isEmpty else {
            dispatchError = "Failed to render images for dispatch"
            showingDispatchError = true
            return
        }

        // Build prompt with image file references so Claude Code can see them
        var fullPrompt = annotationVM.promptText
        let pathList = imagePaths.map { $0.path }.joined(separator: " ")
        fullPrompt = "\(pathList)\n\n\(fullPrompt)"

        // Dispatch to selected session
        let dispatched = await EmbeddedTerminalService.shared.dispatchPrompt(fullPrompt, to: sessionId)
        guard dispatched else {
            dispatchError = "Failed to dispatch to embedded terminal."
            showingDispatchError = true
            return
        }

        let imageCount = imagePaths.count
        // Clear state on success
        annotationVM.handleDispatchComplete()

        logInfo("Dispatched \(imageCount) images to session \(sessionId)", category: .simulator)

        // Activate the dispatched session and bring main window to front
        sessionManager.setActiveSession(sessionId)
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.canBecomeMain }) {
            window.makeKeyAndOrderFront(nil)
        }
    }

    /// Renders all queued annotated images and saves them to temp files.
    /// Returns the file URLs of the saved images.
    private func saveRenderedImages() async -> [URL] {
        let renderer = AnnotationRenderer.shared
        let rendered = await renderer.renderBatch(annotationVM.sendQueue)

        var urls: [URL] = []
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DispatchCaptures", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        for (index, image) in rendered.enumerated() {
            guard let pngData = renderer.pngData(from: image) else { continue }
            let filename = "dispatch_\(UUID().uuidString.prefix(8))_\(index).png"
            let url = tempDir.appendingPathComponent(filename)
            do {
                try pngData.write(to: url)
                urls.append(url)
                logDebug("Saved rendered image: \(url.path)", category: .simulator)
            } catch {
                logError("Failed to save rendered image: \(error)", category: .simulator)
            }
        }

        return urls
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
        guard let char = characters.first else { return .ignored }

        switch char {
        case "1":
            annotationVM.selectTool(.crop)
        case "2":
            annotationVM.selectTool(.freehand)
        case "3":
            annotationVM.selectTool(.arrow)
        case "4":
            annotationVM.selectTool(.rectangle)
        case "5":
            annotationVM.selectTool(.text)
        default:
            return .ignored
        }
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

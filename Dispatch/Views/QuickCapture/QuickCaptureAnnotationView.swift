//
//  QuickCaptureAnnotationView.swift
//  Dispatch
//
//  Annotation view for QuickCapture screenshots.
//

import SwiftData
import SwiftUI

/// Annotation view for QuickCapture screenshots.
/// Reuses existing annotation infrastructure (AnnotationCanvasView, AnnotationToolbar).
struct QuickCaptureAnnotationView: View {
    let capture: QuickCapture

    // MARK: - Focus

    private enum FocusField: Hashable {
        case prompt
    }

    @FocusState private var focusedField: FocusField?

    // MARK: - State

    private static let lastSessionKey = "quickCapture_lastSessionId"

    @StateObject private var annotationVM = AnnotationViewModel()
    @State private var isSessionPickerExpanded = false
    @State private var showingError = false
    @State private var errorMessage: String?
    @State private var selectedSessionId: UUID?
    @State private var isSessionStarting = false
    @State private var sessionStartCheckTimer: Timer?
    @State private var projectPath: String?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    private var sessionManager: TerminalSessionManager { TerminalSessionManager.shared }
    private var bridge: EmbeddedTerminalBridge { EmbeddedTerminalBridge.shared }

    /// Sessions matching the capture's project (by relationship or working directory)
    private var projectSessions: [TerminalSession] {
        guard capture.projectId != nil || projectPath != nil else { return [] }
        return sessionManager.sessionsForProject(id: capture.projectId, path: projectPath)
    }

    /// All sessions with an available terminal, for the dispatch button menu
    private var availableSessions: [TerminalSession] {
        sessionManager.sessions.filter { bridge.isAvailable(sessionId: $0.id) }
    }

    /// Whether dispatch is possible (for onKeyPress guard)
    private var isDispatching: Bool {
        !annotationVM.hasQueuedImages || annotationVM.promptText.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            HSplitView {
                // Left: Canvas and toolbar (reuse existing)
                leftPanel
                    .frame(minWidth: 600)

                // Right: Queue, prompt, and dispatch
                rightPanel
                    .frame(minWidth: 280, maxWidth: 350)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
        .onAppear {
            loadCapture()
            // Look up project path for fallback session matching
            if let projectId = capture.projectId {
                let descriptor = FetchDescriptor<Project>(predicate: #Predicate { $0.id == projectId })
                projectPath = try? modelContext.fetch(descriptor).first?.path
            }
            // Auto-select session based on project context
            let readySessions = projectSessions.filter { bridge.isAvailable(sessionId: $0.id) }
            if readySessions.count == 1 {
                selectedSessionId = readySessions.first?.id
                logDebug("Auto-selected only ready project session: \(selectedSessionId?.uuidString ?? "nil")", category: .capture)
            } else if readySessions.count > 1 {
                // Multiple ready project sessions — prefer the active one
                if let activeId = sessionManager.activeSessionId, readySessions.contains(where: { $0.id == activeId }) {
                    selectedSessionId = activeId
                } else {
                    selectedSessionId = readySessions.first?.id
                }
            } else if let lastIdString = UserDefaults.standard.string(forKey: Self.lastSessionKey),
                      let lastId = UUID(uuidString: lastIdString),
                      bridge.isAvailable(sessionId: lastId) {
                // Restore last used session if its terminal is ready
                selectedSessionId = lastId
                logDebug("Restored last used session: \(lastId)", category: .capture)
            } else if let activeId = sessionManager.activeSessionId,
                      bridge.isAvailable(sessionId: activeId) {
                // Fall back to active session if its terminal is ready
                selectedSessionId = activeId
            }
            focusedField = .prompt
        }
        .onChange(of: selectedSessionId) { _, newId in
            if let id = newId {
                UserDefaults.standard.set(id.uuidString, forKey: Self.lastSessionKey)
            }
        }
        .onKeyPress(keys: [.escape]) { _ in
            dismiss()
            return .handled
        }
        .onKeyPress(keys: [.return]) { press in
            guard press.modifiers.contains(.shift),
                  let sessionId = selectedSessionId,
                  !isDispatching
            else { return .ignored }
            Task { await dispatch(to: sessionId) }
            return .handled
        }
        .onDisappear {
            // Cleanup timers and cached image data
            sessionStartCheckTimer?.invalidate()
            sessionStartCheckTimer = nil
            AnnotatedImage.cleanupQuickCapture(id: capture.id)
        }
    }

    private var leftPanel: some View {
        VStack(spacing: 0) {
            AnnotationCanvasView()
                .environmentObject(annotationVM)

            Divider()

            AnnotationToolbar()
                .environmentObject(annotationVM)
        }
    }

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
            promptSection

            Spacer()

            // Project session hints (no-session warning, start button)
            sessionHintsSection
                .padding(.horizontal)

            Divider()

            // Unified dispatch button with session picker
            CaptureDispatchButton(
                selectedSessionId: $selectedSessionId,
                isExpanded: $isSessionPickerExpanded,
                sessions: availableSessions,
                isDisabled: !annotationVM.hasQueuedImages || annotationVM.promptText.isEmpty,
                onDispatch: { sessionId in
                    await dispatch(to: sessionId)
                },
                onNewSession: {
                    startSessionForProject()
                }
            )
            .padding()
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }

    private var promptSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Prompt")
                .font(.headline)

            TextEditor(text: $annotationVM.promptText)
                .font(.body)
                .frame(minHeight: 100)
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
    }

    /// Hints shown above the dispatch button (no-session warning, start button)
    @ViewBuilder
    private var sessionHintsSection: some View {
        if availableSessions.isEmpty {
            if capture.projectId != nil {
                noSessionView
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("No terminal sessions open")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.vertical, 8)
            }
        } else if capture.projectId != nil, projectSessions.filter({ bridge.isAvailable(sessionId: $0.id) }).isEmpty {
            Text("No session matched this project")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.vertical, 4)
        }
    }

    private var noSessionView: some View {
        VStack(spacing: 8) {
            if isSessionStarting {
                ProgressView()
                    .controlSize(.small)
                Text("Starting session...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("No Claude Code session available")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button {
                    startSessionForProject()
                } label: {
                    Label("Start Claude Code Session", systemImage: "terminal")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 8)
    }

    private func startSessionForProject() {
        guard let projectId = capture.projectId else { return }

        // Look up the Project model
        let descriptor = FetchDescriptor<Project>(predicate: #Predicate { $0.id == projectId })
        guard let project = try? modelContext.fetch(descriptor).first else {
            logError("Could not find project for id: \(projectId)", category: .capture)
            return
        }

        // Create session linked to this project
        let session = sessionManager.createSession(
            name: project.name,
            workingDirectory: project.path
        )

        guard let session else {
            errorMessage = "Failed to create session (max sessions reached?)"
            showingError = true
            return
        }

        session.project = project
        isSessionStarting = true
        logInfo("Started new session '\(session.name)' for project \(project.name), waiting for terminal...", category: .capture)

        // Poll for terminal registration every 0.5s, up to 10s
        var attempts = 0
        sessionStartCheckTimer?.invalidate()
        sessionStartCheckTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [sessionId = session.id] timer in
            Task { @MainActor in
                attempts += 1
                if self.bridge.isAvailable(sessionId: sessionId) {
                    timer.invalidate()
                    self.sessionStartCheckTimer = nil
                    self.isSessionStarting = false
                    self.selectedSessionId = sessionId
                    logInfo("Session terminal ready after \(attempts) checks", category: .capture)
                } else if attempts >= 20 {
                    timer.invalidate()
                    self.sessionStartCheckTimer = nil
                    self.isSessionStarting = false
                    self.selectedSessionId = sessionId // Still select it — may become ready later
                    logWarning("Session terminal not ready after 10s timeout", category: .capture)
                }
            }
        }
    }

    private func loadCapture() {
        // Verify image exists before proceeding
        guard capture.image != nil else {
            errorMessage = "Failed to load screenshot from: \(capture.filePath)"
            showingError = true
            logError("Failed to load QuickCapture image: \(capture.filePath)", category: .capture)
            return
        }

        let annotatedImage = AnnotatedImage(quickCapture: capture)

        // Load into AnnotationViewModel and auto-add to send queue
        annotationVM.loadAnnotatedImage(annotatedImage)
        annotationVM.addToQueue(annotatedImage)

        logInfo("Loaded QuickCapture into annotation view and queue: \(capture.fileURL.lastPathComponent)", category: .capture)
    }

    private func dispatch(to sessionId: UUID) async {
        // Render annotated images and save to temp files for Claude Code to read
        let imagePaths = await saveRenderedImages()

        guard !imagePaths.isEmpty else {
            errorMessage = "Failed to render images for dispatch"
            showingError = true
            return
        }

        // Build prompt with image file references so Claude Code can see them
        var fullPrompt = annotationVM.promptText
        if !imagePaths.isEmpty {
            let pathList = imagePaths.map { $0.path }.joined(separator: " ")
            fullPrompt = "\(pathList)\n\n\(fullPrompt)"
        }

        // Dispatch to selected session, with fallback to active session
        var dispatched = await EmbeddedTerminalService.shared.dispatchPrompt(
            fullPrompt,
            to: sessionId
        )

        // If selected session unavailable, try the active session as fallback
        if !dispatched, let activeId = TerminalSessionManager.shared.activeSessionId, activeId != sessionId {
            logWarning("Session \(sessionId) unavailable, falling back to active session \(activeId)", category: .capture)
            dispatched = await EmbeddedTerminalService.shared.dispatchPrompt(fullPrompt, to: activeId)
        }

        guard dispatched else {
            if isSessionStarting {
                errorMessage = "Session is still starting. Please wait a moment."
            } else {
                errorMessage = "Session terminal not ready. Open a session in the main window first."
            }
            showingError = true
            return
        }

        let imageCount = imagePaths.count
        // Clear state on success
        annotationVM.handleDispatchComplete()

        logInfo("Dispatched \(imageCount) images to session \(sessionId)", category: .capture)

        // Activate the dispatched session and bring main window to front
        sessionManager.setActiveSession(sessionId)
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.canBecomeMain }) {
            window.makeKeyAndOrderFront(nil)
        }

        // Close window after successful dispatch
        dismiss()
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
                logDebug("Saved rendered image: \(url.path)", category: .capture)
            } catch {
                logError("Failed to save rendered image: \(error)", category: .capture)
            }
        }

        return urls
    }
}

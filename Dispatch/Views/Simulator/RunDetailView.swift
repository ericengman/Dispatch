//
//  RunDetailView.swift
//  Dispatch
//
//  Inline view for displaying and annotating screenshots from a run
//  Displays in main content area instead of a separate window
//

import SwiftUI

struct RunDetailView: View {
    // MARK: - Properties

    let run: SimulatorRun
    let onClose: () -> Void

    // MARK: - State

    @StateObject private var annotationVM = AnnotationViewModel()
    @State private var selectedScreenshot: Screenshot?

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            headerBar

            Divider()

            // Main content area
            HSplitView {
                // Left: Canvas and toolbar
                leftPanel
                    .frame(minWidth: 500)

                // Right: Send queue and prompt
                rightPanel
                    .frame(minWidth: 280, maxWidth: 350)
            }

            Divider()

            // Bottom: Screenshot strip
            bottomStrip
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            setupInitialState()
        }
        .onKeyPress(keys: [.escape]) { _ in
            onClose()
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

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack {
            // Close button
            Button {
                onClose()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.medium))
            }
            .buttonStyle(.plain)
            .help("Back to prompts (Esc)")

            // Run info
            VStack(alignment: .leading, spacing: 2) {
                Text(run.displayName)
                    .font(.headline)

                HStack(spacing: 8) {
                    Text("\(run.screenshotCount) screenshots")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("•")
                        .foregroundStyle(.tertiary)

                    Text(run.relativeCreatedTime)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            // Open in window button
            Button {
                AnnotationWindowController.shared.open(run: run, screenshot: selectedScreenshot)
            } label: {
                Label("Open in Window", systemImage: "rectangle.on.rectangle")
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
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

    // MARK: - Bottom Strip

    private var bottomStrip: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("All Screenshots")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Text("\(run.screenshotCount) total")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal)
            .padding(.top, 8)

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
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
    }

    // MARK: - Computed Properties

    private var canDispatch: Bool {
        annotationVM.hasQueuedImages && !annotationVM.promptText.isEmpty
    }

    // MARK: - Actions

    private func setupInitialState() {
        if let first = run.sortedScreenshots.first {
            selectScreenshot(first)
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
            // Dispatch prompt text to embedded terminal
            let embeddedService = EmbeddedTerminalService.shared
            guard embeddedService.isAvailable else {
                logError("No embedded terminal available", category: .simulator)
                return
            }

            let dispatched = embeddedService.dispatchPrompt(prompt)
            guard dispatched else {
                logError("Failed to dispatch to embedded terminal", category: .simulator)
                return
            }

            // Clear state on success
            annotationVM.handleDispatchComplete()

            logInfo("Dispatched prompt with \(imageCount) images in clipboard (paste with Cmd+V)", category: .simulator)
        } else {
            logError("Failed to copy images to clipboard", category: .simulator)
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
    RunDetailView(
        run: SimulatorRun(name: "Test Run"),
        onClose: {}
    )
    .frame(width: 1200, height: 800)
}

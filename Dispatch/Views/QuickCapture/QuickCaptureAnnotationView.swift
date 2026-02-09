//
//  QuickCaptureAnnotationView.swift
//  Dispatch
//
//  Annotation view for QuickCapture screenshots.
//

import SwiftUI

/// Annotation view for QuickCapture screenshots.
/// Reuses existing annotation infrastructure (AnnotationCanvasView, AnnotationToolbar).
struct QuickCaptureAnnotationView: View {
    let capture: QuickCapture

    @StateObject private var annotationVM = AnnotationViewModel()
    @State private var showingError = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

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
        }
        .onKeyPress(keys: [.escape]) { _ in
            dismiss()
            return .handled
        }
        .onDisappear {
            // Cleanup cached image data
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

            // Placeholder for session picker (added in 25-02)
            Text("Session selection coming in next plan")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding()

            Divider()

            // Dispatch button (disabled until 25-02 adds session picker)
            dispatchButton
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
        }
        .padding()
    }

    private var dispatchButton: some View {
        Button {
            // Dispatch implemented in 25-02
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "paperplane.fill")
                Text("Dispatch to Session")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.borderedProminent)
        .disabled(true) // Enabled in 25-02 with session picker
        .keyboardShortcut(.return, modifiers: .command)
    }

    private func loadCapture() {
        // Verify image exists before proceeding
        guard capture.image != nil else {
            errorMessage = "Failed to load screenshot from: \(capture.filePath)"
            showingError = true
            logError("Failed to load QuickCapture image: \(capture.filePath)", category: .capture)
            return
        }

        // Create AnnotatedImage using the QuickCapture-compatible initializer
        // This uses the extension added in Task 1 that handles non-SwiftData images
        let annotatedImage = AnnotatedImage(quickCapture: capture)

        // Load into AnnotationViewModel using existing API
        // Verified: loadAnnotatedImage(_ image: AnnotatedImage) exists at SimulatorViewModel.swift:316-319
        annotationVM.loadAnnotatedImage(annotatedImage)

        logInfo("Loaded QuickCapture into annotation view: \(capture.fileURL.lastPathComponent)", category: .capture)
    }
}

//
//  QuickCaptureSidebarSection.swift
//  Dispatch
//
//  Collapsible sidebar section with capture buttons and recent captures thumbnail grid.
//

import SwiftUI

/// Quick Capture section for the sidebar with capture buttons and recent captures.
struct QuickCaptureSidebarSection: View {
    // MARK: - Properties

    @ObservedObject private var captureManager = QuickCaptureManager.shared
    @Environment(\.openWindow) private var openWindow

    // MARK: - Body

    var body: some View {
        Section {
            if captureManager.recentCaptures.isEmpty {
                emptyState
            } else {
                recentCapturesGrid
            }
        } header: {
            sectionHeader
        }
    }

    // MARK: - Header

    private var sectionHeader: some View {
        HStack {
            Label("Quick Capture", systemImage: "camera")

            Spacer()

            HStack(spacing: 8) {
                // Region capture button
                Button {
                    triggerRegionCapture()
                } label: {
                    Image(systemName: "viewfinder.rectangular")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Capture region (crosshair selection)")

                // Window capture button
                Button {
                    triggerWindowCapture()
                } label: {
                    Image(systemName: "macwindow")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Capture window (hover and click)")
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "camera.viewfinder")
                .font(.title2)
                .foregroundStyle(.tertiary)

            Text("No recent captures")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Use the buttons above to capture")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    // MARK: - Recent Captures Grid

    private var recentCapturesGrid: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHGrid(rows: [GridItem(.fixed(80))], spacing: 8) {
                ForEach(captureManager.recentCaptures) { capture in
                    QuickCaptureThumbnailCell(
                        capture: capture,
                        onSelect: {
                            selectCapture(capture)
                        },
                        onRecapture: {
                            recaptureWindow(from: capture)
                        }
                    )
                }
            }
            .padding(.horizontal, 4)
        }
    }

    // MARK: - Actions

    private func triggerRegionCapture() {
        Task {
            let result = await ScreenshotCaptureService.shared.captureRegion()
            handleCaptureResult(result)
        }
    }

    private func triggerWindowCapture() {
        Task {
            let result = await ScreenshotCaptureService.shared.captureWindow()
            handleCaptureResult(result)
        }
    }

    private func handleCaptureResult(_ result: CaptureResult) {
        // Use CaptureCoordinator to handle result consistently
        // This also adds to MRU list
        CaptureCoordinator.shared.handleCaptureResult(result)
    }

    private func selectCapture(_ capture: QuickCapture) {
        logInfo("Opening capture from sidebar: \(capture.id)", category: .capture)
        openWindow(value: capture)
    }

    private func recaptureWindow(from _: QuickCapture) {
        // For now, just trigger a new window capture
        // Future: Could restore window selection based on stored metadata
        triggerWindowCapture()
    }
}

// MARK: - Preview

#Preview {
    List {
        QuickCaptureSidebarSection()
    }
    .listStyle(.sidebar)
    .frame(width: 250, height: 200)
}

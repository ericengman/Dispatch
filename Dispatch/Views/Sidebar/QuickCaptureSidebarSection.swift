//
//  QuickCaptureSidebarSection.swift
//  Dispatch
//
//  Collapsible sidebar section showing capture targets (previously captured apps)
//  for quick re-capture.
//

import SwiftUI

/// Quick Capture section for the sidebar showing re-capturable app targets.
struct QuickCaptureSidebarSection: View {
    // MARK: - Properties

    @ObservedObject private var captureManager = QuickCaptureManager.shared
    @AppStorage("quickCapture_lastTool") private var lastTool: String = "region"
    @Environment(\.openWindow) private var openWindow

    // MARK: - Body

    var body: some View {
        Section {
            if captureManager.captureTargets.isEmpty {
                emptyState
            } else {
                targetsList
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
                    lastTool = "region"
                    triggerRegionCapture()
                } label: {
                    Image(systemName: "viewfinder.rectangular")
                        .foregroundStyle(lastTool == "region" ? Color.accentColor : .secondary)
                }
                .buttonStyle(.borderless)
                .help("Capture region (crosshair selection)")

                // Window capture button
                Button {
                    lastTool = "window"
                    triggerWindowCapture()
                } label: {
                    Image(systemName: "macwindow")
                        .foregroundStyle(lastTool == "window" ? Color.accentColor : .secondary)
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

            Text("No capture targets")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Capture a window to add it here")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    // MARK: - Targets List

    private var targetsList: some View {
        VStack(spacing: 2) {
            ForEach(captureManager.captureTargets) { target in
                CaptureTargetCell(
                    target: target,
                    onRecapture: {
                        recaptureTarget(target)
                    }
                )
            }
        }
    }

    // MARK: - Actions

    private func triggerRegionCapture() {
        Task {
            let result = await ScreenshotCaptureService.shared.captureRegion()
            CaptureCoordinator.shared.handleCaptureResult(result)
        }
    }

    private func triggerWindowCapture() {
        Task {
            let result = await ScreenshotCaptureService.shared.captureWindow()
            CaptureCoordinator.shared.handleCaptureResult(result)
        }
    }

    private func recaptureTarget(_ target: CaptureTarget) {
        Task {
            let result = await captureManager.recapture(target: target)
            switch result {
            case .success:
                CaptureCoordinator.shared.handleCaptureResult(result)
            case .error:
                logError("Failed to re-capture \(target.appName)", category: .capture)
            case .cancelled:
                break
            }
        }
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

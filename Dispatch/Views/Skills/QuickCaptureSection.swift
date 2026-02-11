//
//  QuickCaptureSection.swift
//  Dispatch
//
//  Per-project Quick Capture section for SkillsSidePanel.
//  Shows capture buttons and previously-captured app targets for quick re-capture.
//

import SwiftUI

/// Per-project Quick Capture section for the SkillsSidePanel.
/// Shows previously captured applications as re-capture targets.
struct QuickCaptureSection: View {
    // MARK: - Properties

    let project: Project?
    let isExpanded: Bool
    let onToggle: () -> Void

    @ObservedObject private var captureManager = QuickCaptureManager.shared
    @ObservedObject private var captureCoordinator = CaptureCoordinator.shared
    @Environment(\.openWindow) private var openWindow

    @AppStorage("quickCapture_lastTool") private var lastTool: String = "region"
    @State private var recaptureError: String?

    // MARK: - Computed Properties

    /// Capture targets filtered to this project
    private var projectTargets: [CaptureTarget] {
        captureManager.targets(for: project?.id)
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Header bar with capture buttons
            SectionHeaderBar(
                title: "Quick Capture",
                icon: "camera",
                iconColor: .cyan,
                count: projectTargets.count,
                isExpanded: isExpanded,
                onToggle: onToggle,
                trailingContent: {
                    captureButtons
                }
            )

            // Content
            if isExpanded {
                if projectTargets.isEmpty {
                    emptyState
                        .padding(12)
                } else {
                    targetsList
                }

                Divider()
            }
        }
        .onAppear {
            // Set project context for new captures
            captureCoordinator.currentProjectId = project?.id
            logDebug("QuickCaptureSection appeared for project: \(project?.name ?? "none")", category: .capture)
        }
        .onChange(of: project?.id) { _, newId in
            captureCoordinator.currentProjectId = newId
        }
        .alert("Re-capture Failed", isPresented: .init(
            get: { recaptureError != nil },
            set: { if !$0 { recaptureError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(recaptureError ?? "")
        }
    }

    // MARK: - Capture Buttons

    private var captureButtons: some View {
        HStack(spacing: 12) {
            // Region capture button
            Button {
                lastTool = "region"
                triggerRegionCapture()
            } label: {
                Image(systemName: "viewfinder.rectangular")
                    .font(.title3)
                    .frame(width: 36, height: 36)
                    .background(Color.accentColor.opacity(lastTool == "region" ? 0.25 : 0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.accentColor.opacity(lastTool == "region" ? 0.5 : 0), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            .help("Capture region (crosshair selection)")

            // Window capture button
            Button {
                lastTool = "window"
                triggerWindowCapture()
            } label: {
                Image(systemName: "macwindow")
                    .font(.title3)
                    .frame(width: 36, height: 36)
                    .background(Color.accentColor.opacity(lastTool == "window" ? 0.25 : 0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.accentColor.opacity(lastTool == "window" ? 0.5 : 0), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            .help("Capture window (hover and click)")
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        HStack {
            Spacer()
            VStack(spacing: 4) {
                Image(systemName: "camera.viewfinder")
                    .font(.title3)
                    .foregroundStyle(.quaternary)
                Text("No capture targets yet")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Text("Capture a window to add it here")
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
            }
            Spacer()
        }
        .frame(height: 60)
    }

    // MARK: - Targets List

    private var targetsList: some View {
        VStack(spacing: 2) {
            ForEach(projectTargets) { target in
                CaptureTargetCell(
                    target: target,
                    onRecapture: {
                        recaptureTarget(target)
                    }
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Actions

    private func triggerRegionCapture() {
        Task {
            let result = await ScreenshotCaptureService.shared.captureRegion()
            captureCoordinator.handleCaptureResult(result)
        }
    }

    private func triggerWindowCapture() {
        Task {
            let result = await ScreenshotCaptureService.shared.captureWindow()
            captureCoordinator.handleCaptureResult(result)
        }
    }

    private func recaptureTarget(_ target: CaptureTarget) {
        Task {
            let result = await captureManager.recapture(target: target)
            switch result {
            case .success:
                captureCoordinator.handleCaptureResult(result)
            case let .error(error):
                recaptureError = error.localizedDescription
            case .cancelled:
                break
            }
        }
    }
}

// MARK: - Capture Target Cell

/// Displays a capture target as a compact row: [icon] AppName · 5m ago
struct CaptureTargetCell: View {
    let target: CaptureTarget
    let onRecapture: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            // App icon
            if let icon = target.appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 16, height: 16)
            } else {
                Image(systemName: "app.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, height: 16)
            }

            // App name
            Text(target.appName)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(1)

            // Dot separator + time ago
            Text("·")
                .foregroundStyle(.tertiary)
            Text(target.timeAgo)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            // Re-capture icon on hover
            if isHovered {
                Image(systemName: "camera.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? Color.primary.opacity(0.06) : .clear)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onRecapture()
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .help("Re-capture \(target.appName)")
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 0) {
        QuickCaptureSection(
            project: nil,
            isExpanded: true,
            onToggle: {}
        )
    }
    .frame(width: 320, height: 200)
}

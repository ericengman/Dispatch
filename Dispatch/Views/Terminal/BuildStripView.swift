//
//  BuildStripView.swift
//  Dispatch
//
//  Condensed build output strip, modeled on BrewStripView.
//  Shows destination name, status, warnings/errors, elapsed time.
//

import SwiftUI

struct BuildStripView: View {
    let build: BuildRun
    let buildController: BuildRunController

    static let stripHeight: CGFloat = 70

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Top row: status dot + destination name + filter picker + elapsed time + cancel
            HStack(spacing: 6) {
                statusDot

                Text(build.destination.displayName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text("(\(build.scheme))")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)

                Spacer()

                // Filter picker
                filterPicker

                // Elapsed time
                if let startTime = build.startTime {
                    if let endTime = build.endTime {
                        Text(BrewStripView.formatElapsed(from: startTime, to: endTime))
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                    } else {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Text(BrewStripView.formatElapsed(from: startTime, to: context.date))
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // Cancel button (only during active builds)
                if build.status.isActive || build.status == .queued {
                    Button {
                        buildController.cancelBuild(id: build.id)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Cancel build")
                }

                // Dismiss button (for completed builds)
                if build.status.isTerminal {
                    Button {
                        buildController.removeBuild(id: build.id)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .help("Dismiss")
                }
            }

            // Middle row: status text or last output line
            Text(build.lastOutputPreview)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .white, location: 0),
                            .init(color: .white, location: 0.85),
                            .init(color: .clear, location: 1.0)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )

            // Bottom row: warning and error badges
            HStack(spacing: 8) {
                if build.warningCount > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.yellow)
                        Text("\(build.warningCount)")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(.yellow)
                    }
                }

                if build.errorCount > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.red)
                        Text("\(build.errorCount)")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(.red)
                    }
                }

                Spacer()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .frame(height: Self.stripHeight)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(statusBorderColor.opacity(0.3), lineWidth: 1)
        )
        .contentShape(Rectangle())
    }

    // MARK: - Status Dot

    @ViewBuilder
    private var statusDot: some View {
        let color = statusDotColor
        let isAnimated = build.status.isActive

        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .scaleEffect(isAnimated ? 1.3 : 1.0)
            .opacity(isAnimated ? 0.7 : 1.0)
            .animation(
                isAnimated
                    ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
                    : .default,
                value: isAnimated
            )
    }

    private var statusDotColor: Color {
        switch build.status {
        case .queued: return .gray
        case .compiling, .linking: return .blue
        case .installing, .launching: return .orange
        case .succeeded: return .green
        case .failed: return .red
        case .cancelled: return .gray
        }
    }

    private var statusBorderColor: Color {
        statusDotColor
    }

    // MARK: - Filter Picker

    @ViewBuilder
    private var filterPicker: some View {
        HStack(spacing: 4) {
            // Built-in filters
            HStack(spacing: 0) {
                ForEach(BuildOutputFilter.allCases, id: \.self) { filter in
                    Button {
                        build.isCustomFilterActive = false
                        build.customFilterText = ""
                        build.setFilter(filter)
                    } label: {
                        Text(filter.displayName)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(build.filterMode == filter && !build.isCustomFilterActive ? .primary : .tertiary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                build.filterMode == filter && !build.isCustomFilterActive
                                    ? RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.1))
                                    : nil
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
            )

            // Saved filter chips
            ForEach(buildController.filtersForDestination(build.destination.id), id: \.self) { savedFilter in
                Button {
                    build.customFilterText = savedFilter
                    build.isCustomFilterActive = true
                } label: {
                    Text(savedFilter)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(build.isCustomFilterActive && build.customFilterText == savedFilter ? .primary : .tertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(build.isCustomFilterActive && build.customFilterText == savedFilter
                                    ? Color.accentColor.opacity(0.15)
                                    : Color.primary.opacity(0.05))
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

#Preview {
    BuildStripView(
        build: {
            let run = BuildRun(destination: .myMac, scheme: "Dispatch")
            run.status = .compiling("MainView.swift")
            run.startTime = Date().addingTimeInterval(-45)
            run.warningCount = 3
            run.errorCount = 1
            return run
        }(),
        buildController: BuildRunController.shared
    )
    .frame(width: 600)
    .padding()
}

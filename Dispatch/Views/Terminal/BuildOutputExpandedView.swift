//
//  BuildOutputExpandedView.swift
//  Dispatch
//
//  Full scrollable build log view, shown when a build strip is expanded/peeking
//

import AppKit
import SwiftUI

struct BuildOutputExpandedView: View {
    let build: BuildRun
    let buildController: BuildRunController

    @State private var autoScroll = true
    @State private var scrollProxy: ScrollViewProxy?
    @State private var filterText: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header: destination + status + controls
            HStack(spacing: 8) {
                statusDot

                Text(build.destination.displayName)
                    .font(.system(size: 12, weight: .medium))

                Text("(\(build.scheme))")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)

                Text(build.status.displayText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

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

                // Badge counts
                if build.warningCount > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9))
                        Text("\(build.warningCount)")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                    }
                    .foregroundStyle(.yellow)
                }

                if build.errorCount > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 9))
                        Text("\(build.errorCount)")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                    }
                    .foregroundStyle(.red)
                }

                // Copy button
                Button {
                    let text = build.filteredOutputLines.map(\.text).joined(separator: "\n")
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Copy output")

                // Condense button
                Button {
                    buildController.manualCondense(build.id)
                } label: {
                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Condense")

                // Cancel / Dismiss
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
                } else if build.status.isTerminal {
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
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.8))

            Divider()

            // Scrollable output
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(build.filteredOutputLines) { line in
                            Text(line.text)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(colorForLevel(line.level))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 1)
                                .id(line.id)
                        }
                    }
                }
                .textSelection(.enabled)
                .onAppear {
                    scrollProxy = proxy
                }
                .onChange(of: build.outputLines.count) { _, _ in
                    if autoScroll, let lastLine = build.filteredOutputLines.last {
                        withAnimation(.easeOut(duration: 0.1)) {
                            proxy.scrollTo(lastLine.id, anchor: .bottom)
                        }
                    }
                }
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(statusBorderColor.opacity(0.3), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Helpers

    private func colorForLevel(_ level: BuildOutputLevel) -> Color {
        switch level {
        case .info: return .secondary
        case .warning: return .yellow
        case .error: return .red
        }
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

    @ViewBuilder
    private var filterPicker: some View {
        HStack(spacing: 4) {
            // Built-in filters
            HStack(spacing: 0) {
                ForEach(BuildOutputFilter.allCases, id: \.self) { filter in
                    Button {
                        build.isCustomFilterActive = false
                        build.customFilterText = ""
                        filterText = ""
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
                    filterText = savedFilter
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
                .contextMenu {
                    Button("Delete Filter", role: .destructive) {
                        if build.customFilterText == savedFilter {
                            build.isCustomFilterActive = false
                            build.customFilterText = ""
                            filterText = ""
                        }
                        buildController.removeSavedFilter(savedFilter, for: build.destination.id)
                    }
                }
            }

            // Filter text field
            TextField("Filter...", text: $filterText)
                .textFieldStyle(.plain)
                .font(.system(size: 10))
                .frame(width: 80)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.05)))
                .onChange(of: filterText) { _, newValue in
                    build.customFilterText = newValue
                    build.isCustomFilterActive = !newValue.isEmpty
                }
                .onSubmit {
                    if !filterText.isEmpty {
                        build.customFilterText = filterText
                        build.isCustomFilterActive = true
                    }
                }

            // Save filter button
            if !filterText.isEmpty {
                Button {
                    buildController.addSavedFilter(filterText, for: build.destination.id)
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Save filter")
            }
        }
    }
}

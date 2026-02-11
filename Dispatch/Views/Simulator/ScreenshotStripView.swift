//
//  ScreenshotStripView.swift
//  Dispatch
//
//  Horizontal scrollable strip of screenshot thumbnails
//

import SwiftUI

struct ScreenshotStripView: View {
    // MARK: - Properties

    let screenshots: [Screenshot]
    let selectedScreenshot: Screenshot?
    let showHidden: Bool
    let onSelect: (Screenshot) -> Void
    let onDoubleClick: (Screenshot) -> Void
    let onToggleHidden: (Screenshot) -> Void

    // MARK: - State

    @State private var focusedId: UUID?

    // MARK: - Computed

    private var displayedScreenshots: [Screenshot] {
        if showHidden {
            return screenshots
        } else {
            return screenshots.filter { !$0.isHidden }
        }
    }

    // MARK: - Body

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 8) {
                    ForEach(screenshots) { screenshot in
                        if showHidden || !screenshot.isHidden {
                            ScreenshotThumbnailView(
                                screenshot: screenshot,
                                isSelected: selectedScreenshot?.id == screenshot.id,
                                isHidden: screenshot.isHidden,
                                onSelect: { onSelect(screenshot) },
                                onDoubleClick: { onDoubleClick(screenshot) },
                                onToggleHidden: { onToggleHidden(screenshot) }
                            )
                            .id(screenshot.id)
                        } else {
                            // Collapsed hidden indicator
                            hiddenIndicator(for: screenshot)
                                .id(screenshot.id)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 4)
            }
            .onChange(of: selectedScreenshot?.id) { _, newId in
                if let id = newId {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
        }
        .frame(height: 90)
        .background(.quaternary.opacity(0.3))
        .focusable()
        .onKeyPress(.leftArrow) {
            selectPrevious()
            return .handled
        }
        .onKeyPress(.rightArrow) {
            selectNext()
            return .handled
        }
        .onKeyPress(.space) {
            toggleSelectedHidden()
            return .handled
        }
        .onKeyPress(.return) {
            openSelectedInAnnotation()
            return .handled
        }
    }

    // MARK: - Hidden Indicator

    private func hiddenIndicator(for screenshot: Screenshot) -> some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.2))
            .frame(width: 8, height: 70)
            .overlay {
                Image(systemName: "eye.slash")
                    .font(.system(size: 8))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(-90))
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .onTapGesture {
                onToggleHidden(screenshot)
            }
    }

    // MARK: - Keyboard Navigation

    private func selectNext() {
        let displayed = displayedScreenshots
        guard !displayed.isEmpty else { return }

        if let current = selectedScreenshot,
           let index = displayed.firstIndex(where: { $0.id == current.id }) {
            let nextIndex = min(index + 1, displayed.count - 1)
            onSelect(displayed[nextIndex])
        } else {
            onSelect(displayed.first!)
        }
    }

    private func selectPrevious() {
        let displayed = displayedScreenshots
        guard !displayed.isEmpty else { return }

        if let current = selectedScreenshot,
           let index = displayed.firstIndex(where: { $0.id == current.id }) {
            let prevIndex = max(index - 1, 0)
            onSelect(displayed[prevIndex])
        } else {
            onSelect(displayed.last!)
        }
    }

    private func toggleSelectedHidden() {
        if let screenshot = selectedScreenshot {
            onToggleHidden(screenshot)
        }
    }

    private func openSelectedInAnnotation() {
        if let screenshot = selectedScreenshot {
            onDoubleClick(screenshot)
        }
    }
}

// MARK: - Screenshot Thumbnail View

struct ScreenshotThumbnailView: View {
    // MARK: - Properties

    let screenshot: Screenshot
    let isSelected: Bool
    let isHidden: Bool
    let onSelect: () -> Void
    let onDoubleClick: () -> Void
    let onToggleHidden: () -> Void

    // MARK: - State

    @State private var thumbnail: NSImage?
    @State private var isHovering = false

    // MARK: - Body

    var body: some View {
        VStack(spacing: 4) {
            // Thumbnail image
            thumbnailImage
                .frame(width: 80, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(
                            isSelected ? Color.accentColor : Color.clear,
                            lineWidth: 2
                        )
                )
                .scaleEffect(isSelected ? 1.05 : 1.0)
                .opacity(isHidden ? 0.5 : 1.0)
                .shadow(
                    color: isSelected ? .accentColor.opacity(0.3) : .clear,
                    radius: 4
                )

            // Label
            Text(screenshot.displayLabel)
                .font(.caption2)
                .foregroundStyle(isSelected ? .primary : .secondary)
                .lineLimit(1)
                .frame(width: 80)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
        .onTapGesture(count: 2) {
            onDoubleClick()
        }
        .onHover { hovering in
            isHovering = hovering
        }
        .overlay(alignment: .topTrailing) {
            if isHovering {
                hiddenToggleButton
            }
        }
        .animation(.easeInOut(duration: 0.15), value: isSelected)
        .animation(.easeInOut(duration: 0.15), value: isHovering)
        .onAppear {
            loadThumbnail()
        }
    }

    // MARK: - Thumbnail Image

    @ViewBuilder
    private var thumbnailImage: some View {
        if let thumbnail = thumbnail {
            Image(nsImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 80, height: 60)
                .clipped()
        } else {
            Rectangle()
                .fill(Color.secondary.opacity(0.2))
                .overlay {
                    ProgressView()
                        .scaleEffect(0.5)
                }
        }
    }

    // MARK: - Hidden Toggle

    private var hiddenToggleButton: some View {
        Button {
            onToggleHidden()
        } label: {
            Image(systemName: isHidden ? "eye" : "eye.slash")
                .font(.caption)
                .padding(4)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .offset(x: 4, y: -4)
    }

    // MARK: - Thumbnail Loading

    private func loadThumbnail() {
        guard thumbnail == nil else { return }

        Task {
            let image = screenshot.thumbnail
            self.thumbnail = image
        }
    }
}

// MARK: - Preview

#Preview {
    VStack {
        Text("Screenshot Strip Preview")
            .font(.headline)

        ScreenshotStripView(
            screenshots: [],
            selectedScreenshot: nil,
            showHidden: false,
            onSelect: { _ in },
            onDoubleClick: { _ in },
            onToggleHidden: { _ in }
        )
    }
    .frame(width: 600, height: 150)
}

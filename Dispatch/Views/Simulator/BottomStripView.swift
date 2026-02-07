//
//  BottomStripView.swift
//  Dispatch
//
//  Read-only horizontal strip of all screenshots in a run (bottom of annotation window)
//

import SwiftUI

struct BottomStripView: View {
    let screenshots: [Screenshot]
    let selectedScreenshot: Screenshot?
    let queuedIds: Set<UUID>
    let onSelect: (Screenshot) -> Void

    @EnvironmentObject private var annotationVM: AnnotationViewModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 8) {
                    ForEach(screenshots) { screenshot in
                        BottomStripThumbnail(
                            screenshot: screenshot,
                            isSelected: selectedScreenshot?.id == screenshot.id,
                            isQueued: queuedIds.contains(screenshot.id),
                            onSelect: { onSelect(screenshot) }
                        )
                        .id(screenshot.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .frame(height: 80)
            .onChange(of: selectedScreenshot?.id) { _, newId in
                if let id = newId {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
        }
        .focusable()
        .onKeyPress(.leftArrow) {
            selectPrevious()
            return .handled
        }
        .onKeyPress(.rightArrow) {
            selectNext()
            return .handled
        }
    }

    // MARK: - Keyboard Navigation

    private func selectNext() {
        guard !screenshots.isEmpty else { return }

        if let current = selectedScreenshot,
           let index = screenshots.firstIndex(where: { $0.id == current.id }) {
            let nextIndex = min(index + 1, screenshots.count - 1)
            onSelect(screenshots[nextIndex])
        } else {
            onSelect(screenshots.first!)
        }
    }

    private func selectPrevious() {
        guard !screenshots.isEmpty else { return }

        if let current = selectedScreenshot,
           let index = screenshots.firstIndex(where: { $0.id == current.id }) {
            let prevIndex = max(index - 1, 0)
            onSelect(screenshots[prevIndex])
        } else {
            onSelect(screenshots.last!)
        }
    }
}

// MARK: - Bottom Strip Thumbnail

struct BottomStripThumbnail: View {
    let screenshot: Screenshot
    let isSelected: Bool
    let isQueued: Bool
    let onSelect: () -> Void

    @State private var thumbnail: NSImage?
    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                // Thumbnail
                thumbnailImage
                    .frame(width: 60, height: 45)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(
                                isSelected ? Color.accentColor : Color.clear,
                                lineWidth: 2
                            )
                    )
                    .scaleEffect(isSelected ? 1.05 : 1.0)
                    .shadow(
                        color: isSelected ? .accentColor.opacity(0.3) : .clear,
                        radius: 3
                    )

                // Queued indicator
                if isQueued {
                    queuedIndicator
                }
            }

            // Index label
            Text("\(screenshot.captureIndex + 1)")
                .font(.caption2)
                .foregroundStyle(isSelected ? .primary : .tertiary)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
        .onHover { hovering in
            isHovering = hovering
        }
        .animation(.easeInOut(duration: 0.15), value: isSelected)
        .onAppear {
            loadThumbnail()
        }
    }

    @ViewBuilder
    private var thumbnailImage: some View {
        if let thumbnail = thumbnail {
            Image(nsImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 60, height: 45)
                .clipped()
        } else {
            Rectangle()
                .fill(Color.secondary.opacity(0.2))
        }
    }

    private var queuedIndicator: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.green)
                    .background(Circle().fill(Color.white).padding(-1))
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(2)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isQueued)
    }

    private func loadThumbnail() {
        guard thumbnail == nil else { return }

        Task.detached(priority: .userInitiated) {
            let image = screenshot.thumbnail
            await MainActor.run {
                self.thumbnail = image
            }
        }
    }
}

// MARK: - Preview

#Preview {
    BottomStripView(
        screenshots: [],
        selectedScreenshot: nil,
        queuedIds: [],
        onSelect: { _ in }
    )
    .environmentObject(AnnotationViewModel())
    .frame(width: 600)
    .background(Color(nsColor: .controlBackgroundColor))
}

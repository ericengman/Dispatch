//
//  QuickCaptureThumbnailCell.swift
//  Dispatch
//
//  Individual thumbnail cell for recent capture with hover re-capture action.
//

import SwiftUI

/// Individual thumbnail cell displaying a recent capture with hover actions.
struct QuickCaptureThumbnailCell: View {
    // MARK: - Properties

    let capture: QuickCapture
    let onSelect: () -> Void
    let onRecapture: () -> Void

    // MARK: - State

    @State private var thumbnail: NSImage?
    @State private var isLoading = true
    @State private var isHovered = false

    // MARK: - Body

    var body: some View {
        VStack(spacing: 4) {
            // Thumbnail image
            thumbnailView
                .frame(width: 80, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(alignment: .topTrailing) {
                    recaptureOverlay
                }

            // Timestamp caption
            Text(relativeTimestamp)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
        .onHover { hovering in
            isHovered = hovering
        }
        .task {
            await loadThumbnail()
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var thumbnailView: some View {
        if let thumbnail {
            Image(nsImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else if isLoading {
            ZStack {
                Color.secondary.opacity(0.1)
                ProgressView()
                    .scaleEffect(0.6)
            }
        } else {
            ZStack {
                Color.secondary.opacity(0.1)
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var recaptureOverlay: some View {
        if isHovered {
            Button {
                onRecapture()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(4)
                    .background(Color.accentColor)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(4)
            .help("Re-capture this window")
        }
    }

    // MARK: - Computed Properties

    private var relativeTimestamp: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: capture.timestamp, relativeTo: Date())
    }

    // MARK: - Methods

    private func loadThumbnail() async {
        isLoading = true
        let loaded = await ThumbnailCache.shared.thumbnail(for: capture)
        await MainActor.run {
            thumbnail = loaded
            isLoading = false
        }
    }
}

// MARK: - Preview

#Preview {
    HStack {
        QuickCaptureThumbnailCell(
            capture: QuickCapture(fileURL: URL(fileURLWithPath: "/tmp/test.png")),
            onSelect: { print("Selected") },
            onRecapture: { print("Recapture") }
        )
    }
    .padding()
    .frame(width: 200, height: 100)
}

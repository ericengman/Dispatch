//
//  SendQueueView.swift
//  Dispatch
//
//  Horizontal scroll view of images queued for dispatch
//

import SwiftUI

struct SendQueueView: View {
    @EnvironmentObject private var annotationVM: AnnotationViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if annotationVM.sendQueue.isEmpty {
                emptyState
            } else {
                queueContent
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        HStack {
            Spacer()
            VStack(spacing: 8) {
                Image(systemName: "tray")
                    .font(.title2)
                    .foregroundStyle(.quaternary)

                Text("Queue empty")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("Annotate a screenshot to add it")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Queue Content

    private var queueContent: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 8) {
                ForEach(annotationVM.sendQueue.indices, id: \.self) { index in
                    let image = annotationVM.sendQueue[index]
                    QueueItemView(
                        image: image,
                        index: index,
                        onSelect: {
                            annotationVM.loadAnnotatedImage(image)
                        },
                        onRemove: {
                            withAnimation(.easeOut(duration: 0.2)) {
                                annotationVM.removeFromQueue(id: image.id)
                            }
                        }
                    )
                    .transition(.asymmetric(
                        insertion: .scale.combined(with: .opacity),
                        removal: .scale.combined(with: .opacity)
                    ))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: annotationVM.sendQueue.count)
        }
    }
}

// MARK: - Queue Item View

struct QueueItemView: View {
    let image: AnnotatedImage
    let index: Int
    let onSelect: () -> Void
    let onRemove: () -> Void

    @State private var isHovering = false
    @State private var thumbnail: NSImage?

    var body: some View {
        VStack(spacing: 4) {
            // Thumbnail with annotations overlay
            thumbnailView
                .frame(width: 80, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 1)
                )
                .overlay(alignment: .topTrailing) {
                    if isHovering {
                        removeButton
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    // Position indicator
                    Text("\(index + 1)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor)
                        .clipShape(Capsule())
                        .offset(x: -4, y: 4)
                }

            // Label
            Text(image.displayTitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 80)
        }
        .onTapGesture {
            onSelect()
        }
        .onHover { hovering in
            isHovering = hovering
        }
        .onAppear {
            loadThumbnail()
        }
    }

    @ViewBuilder
    private var thumbnailView: some View {
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

    private var removeButton: some View {
        Button {
            onRemove()
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(.white)
                .background(Circle().fill(Color.red))
        }
        .buttonStyle(.plain)
        .offset(x: 6, y: -6)
    }

    private func loadThumbnail() {
        guard thumbnail == nil else { return }

        Task {
            // Try to render with annotations
            if let rendered = await AnnotationRenderer.shared.render(image) {
                // Scale down for thumbnail
                let thumb = scaledThumbnail(from: rendered)
                self.thumbnail = thumb
            } else {
                // Fall back to original
                let thumb = image.screenshot.thumbnail
                self.thumbnail = thumb
            }
        }
    }

    private func scaledThumbnail(from image: NSImage) -> NSImage {
        let targetSize = NSSize(width: 120, height: 90)
        let aspectRatio = image.size.width / image.size.height

        var newSize: NSSize
        if aspectRatio > targetSize.width / targetSize.height {
            newSize = NSSize(width: targetSize.width, height: targetSize.width / aspectRatio)
        } else {
            newSize = NSSize(width: targetSize.height * aspectRatio, height: targetSize.height)
        }

        let thumbnail = NSImage(size: newSize)
        thumbnail.lockFocus()
        image.draw(
            in: NSRect(origin: .zero, size: newSize),
            from: NSRect(origin: .zero, size: image.size),
            operation: .copy,
            fraction: 1.0
        )
        thumbnail.unlockFocus()

        return thumbnail
    }
}

// MARK: - Preview

#Preview {
    SendQueueView()
        .environmentObject(AnnotationViewModel())
        .frame(width: 300, height: 120)
        .background(Color(nsColor: .controlBackgroundColor))
}

//
//  AnnotationCanvasView.swift
//  Dispatch
//
//  Main canvas view for displaying and annotating screenshots
//

import AppKit
import SwiftUI

struct AnnotationCanvasView: View {
    @EnvironmentObject private var annotationVM: AnnotationViewModel

    // MARK: - State

    @State private var imageSize: CGSize = .zero
    @State private var containerSize: CGSize = .zero
    @State private var currentDrawing: [CGPoint] = []
    @State private var dragStart: CGPoint?
    @State private var currentDragEnd: CGPoint?

    // MARK: - Body

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background
                Color(nsColor: .controlBackgroundColor)

                if let image = annotationVM.activeImage,
                   let nsImage = image.screenshot.image {
                    // Image with annotations
                    canvasContent(nsImage: nsImage, image: image)
                        .scaleEffect(annotationVM.zoomLevel)
                        .offset(x: annotationVM.panOffset.x, y: annotationVM.panOffset.y)
                } else {
                    // Empty state
                    emptyState
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .onAppear {
                containerSize = geometry.size
            }
            .onChange(of: geometry.size) { _, newSize in
                containerSize = newSize
            }
            .gesture(panGesture)
            .gesture(magnificationGesture)
        }
    }

    // MARK: - Canvas Content

    @ViewBuilder
    private func canvasContent(nsImage: NSImage, image: AnnotatedImage) -> some View {
        let displaySize = calculateDisplaySize(for: nsImage.size)

        ZStack {
            // Base image
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: displaySize.width, height: displaySize.height)

            // Annotations canvas
            Canvas { context, size in
                // Draw existing annotations
                for annotation in image.annotations {
                    drawAnnotation(annotation, in: &context, size: size, imageSize: nsImage.size)
                }

                // Draw current drawing in progress
                if !currentDrawing.isEmpty {
                    drawCurrentPath(in: &context)
                }

                // Draw live preview for arrow/rectangle while dragging
                if let start = dragStart, let end = currentDragEnd {
                    drawLivePreview(from: start, to: end, in: &context)
                }
            }
            .frame(width: displaySize.width, height: displaySize.height)

            // Crop overlay
            if annotationVM.currentTool == .crop, let cropRect = annotationVM.cropRect {
                CropOverlayView(
                    cropRect: cropRect,
                    imageSize: displaySize,
                    onUpdate: { newRect in
                        annotationVM.cropRect = newRect
                    },
                    onApply: {
                        // Convert view coordinates to image coordinates for storage
                        let viewRect = annotationVM.cropRect!
                        let scaleX = nsImage.size.width / displaySize.width
                        let scaleY = nsImage.size.height / displaySize.height
                        let imageRect = CGRect(
                            x: viewRect.origin.x * scaleX,
                            y: viewRect.origin.y * scaleY,
                            width: viewRect.width * scaleX,
                            height: viewRect.height * scaleY
                        )
                        annotationVM.applyCrop(imageRect)
                        annotationVM.cropRect = nil
                    },
                    onCancel: {
                        annotationVM.cropRect = nil
                    }
                )
                .frame(width: displaySize.width, height: displaySize.height)
            }

            // Drawing gesture overlay — must match canvas frame to keep coordinates aligned
            // Hide when crop overlay is showing to allow button interaction
            if !(annotationVM.currentTool == .crop && annotationVM.cropRect != nil) {
                Color.clear
                    .contentShape(Rectangle())
                    .frame(width: displaySize.width, height: displaySize.height)
                    .gesture(drawingGesture(imageSize: displaySize))
            }
        }
        .onAppear {
            imageSize = nsImage.size
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo")
                .font(.system(size: 48))
                .foregroundStyle(.quaternary)

            Text("Select a screenshot to annotate")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("Click a thumbnail in the strip below")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Drawing

    private func drawAnnotation(_ annotation: Annotation, in context: inout GraphicsContext, size: CGSize, imageSize: CGSize) {
        let scaleX = size.width / imageSize.width
        let scaleY = size.height / imageSize.height

        context.stroke(
            pathForAnnotation(annotation, scaleX: scaleX, scaleY: scaleY),
            with: .color(annotation.color.color),
            lineWidth: annotation.lineWidth
        )

        // Draw arrowhead for arrows
        if annotation.type == .arrow, annotation.points.count >= 2 {
            drawArrowhead(annotation, in: &context, scaleX: scaleX, scaleY: scaleY)
        }

        // Draw text
        if annotation.type == .text, let text = annotation.text, let position = annotation.points.first {
            let scaledPosition = CGPoint(x: position.x * scaleX, y: position.y * scaleY)
            context.draw(
                Text(text)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(annotation.color.color),
                at: scaledPosition,
                anchor: .topLeading
            )
        }
    }

    private func pathForAnnotation(_ annotation: Annotation, scaleX: CGFloat, scaleY: CGFloat) -> Path {
        Path { path in
            switch annotation.type {
            case .freehand:
                guard let first = annotation.points.first else { return }
                path.move(to: CGPoint(x: first.x * scaleX, y: first.y * scaleY))
                for point in annotation.points.dropFirst() {
                    path.addLine(to: CGPoint(x: point.x * scaleX, y: point.y * scaleY))
                }

            case .arrow:
                guard annotation.points.count >= 2 else { return }
                let start = annotation.points[0]
                let end = annotation.points[1]
                path.move(to: CGPoint(x: start.x * scaleX, y: start.y * scaleY))
                path.addLine(to: CGPoint(x: end.x * scaleX, y: end.y * scaleY))

            case .rectangle:
                guard annotation.points.count >= 2 else { return }
                let p1 = annotation.points[0]
                let p2 = annotation.points[1]
                let rect = CGRect(
                    x: min(p1.x, p2.x) * scaleX,
                    y: min(p1.y, p2.y) * scaleY,
                    width: abs(p2.x - p1.x) * scaleX,
                    height: abs(p2.y - p1.y) * scaleY
                )
                path.addRect(rect)

            case .text:
                // Text is drawn separately
                break
            }
        }
    }

    private func drawArrowhead(_ annotation: Annotation, in context: inout GraphicsContext, scaleX: CGFloat, scaleY: CGFloat) {
        let start = annotation.points[0]
        let end = annotation.points[1]

        let scaledEnd = CGPoint(x: end.x * scaleX, y: end.y * scaleY)
        let scaledStart = CGPoint(x: start.x * scaleX, y: start.y * scaleY)

        let angle = atan2(scaledEnd.y - scaledStart.y, scaledEnd.x - scaledStart.x)
        let arrowLength: CGFloat = 15.0
        let arrowAngle: CGFloat = .pi / 6

        let arrowPath = Path { path in
            path.move(to: scaledEnd)
            path.addLine(to: CGPoint(
                x: scaledEnd.x - arrowLength * cos(angle - arrowAngle),
                y: scaledEnd.y - arrowLength * sin(angle - arrowAngle)
            ))
            path.addLine(to: CGPoint(
                x: scaledEnd.x - arrowLength * cos(angle + arrowAngle),
                y: scaledEnd.y - arrowLength * sin(angle + arrowAngle)
            ))
            path.closeSubpath()
        }

        context.fill(arrowPath, with: .color(annotation.color.color))
    }

    private func drawCurrentPath(in context: inout GraphicsContext) {
        guard !currentDrawing.isEmpty else { return }

        let path = Path { path in
            path.move(to: currentDrawing[0])
            for point in currentDrawing.dropFirst() {
                path.addLine(to: point)
            }
        }

        context.stroke(
            path,
            with: .color(annotationVM.currentColor.color),
            lineWidth: 3.0
        )
    }

    private func drawLivePreview(from start: CGPoint, to end: CGPoint, in context: inout GraphicsContext) {
        let color = annotationVM.currentColor.color
        let lineWidth: CGFloat = 3.0

        switch annotationVM.currentTool {
        case .rectangle:
            let rect = CGRect(
                x: min(start.x, end.x),
                y: min(start.y, end.y),
                width: abs(end.x - start.x),
                height: abs(end.y - start.y)
            )
            let path = Path { p in p.addRect(rect) }
            context.stroke(path, with: .color(color), lineWidth: lineWidth)

        case .arrow:
            // Line
            let linePath = Path { p in
                p.move(to: start)
                p.addLine(to: end)
            }
            context.stroke(linePath, with: .color(color), lineWidth: lineWidth)

            // Arrowhead
            let angle = atan2(end.y - start.y, end.x - start.x)
            let arrowLength: CGFloat = 15.0
            let arrowAngle: CGFloat = .pi / 6
            let arrowPath = Path { p in
                p.move(to: end)
                p.addLine(to: CGPoint(
                    x: end.x - arrowLength * cos(angle - arrowAngle),
                    y: end.y - arrowLength * sin(angle - arrowAngle)
                ))
                p.addLine(to: CGPoint(
                    x: end.x - arrowLength * cos(angle + arrowAngle),
                    y: end.y - arrowLength * sin(angle + arrowAngle)
                ))
                p.closeSubpath()
            }
            context.fill(arrowPath, with: .color(color))

        case .crop:
            // Crop preview rectangle
            let rect = CGRect(
                x: min(start.x, end.x),
                y: min(start.y, end.y),
                width: abs(end.x - start.x),
                height: abs(end.y - start.y)
            )
            let path = Path { p in p.addRect(rect) }
            context.stroke(path, with: .color(.white), style: StrokeStyle(lineWidth: 2, dash: [6, 3]))

        default:
            break
        }
    }

    // MARK: - Gestures

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .modifiers(.option)
            .onChanged { value in
                annotationVM.panOffset = CGPoint(
                    x: annotationVM.panOffset.x + value.translation.width,
                    y: annotationVM.panOffset.y + value.translation.height
                )
            }
    }

    private var magnificationGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let newZoom = annotationVM.zoomLevel * value.magnification
                annotationVM.zoomLevel = max(0.25, min(5.0, newZoom))
            }
    }

    private func drawingGesture(imageSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                handleDrawingChanged(value: value, imageSize: imageSize)
            }
            .onEnded { value in
                handleDrawingEnded(value: value, imageSize: imageSize)
            }
    }

    private func handleDrawingChanged(value: DragGesture.Value, imageSize _: CGSize) {
        let tool = annotationVM.currentTool

        switch tool {
        case .crop:
            // Crop uses view coordinates since CropOverlayView displays in view space
            let viewLocation = value.location
            if dragStart == nil {
                dragStart = viewLocation
            }
            let start = dragStart!
            annotationVM.cropRect = CGRect(
                x: min(start.x, viewLocation.x),
                y: min(start.y, viewLocation.y),
                width: abs(viewLocation.x - start.x),
                height: abs(viewLocation.y - start.y)
            )

        case .freehand:
            currentDrawing.append(value.location)

        case .arrow, .rectangle:
            if dragStart == nil {
                dragStart = value.location
            }
            currentDragEnd = value.location

        case .text:
            // Text tool uses tap, not drag
            break
        }

        annotationVM.isDrawing = true
    }

    private func handleDrawingEnded(value: DragGesture.Value, imageSize: CGSize) {
        let tool = annotationVM.currentTool
        let color = annotationVM.currentColor

        // Convert to image coordinates
        let location = convertToImageCoordinates(value.location, imageSize: imageSize)
        let startLocation = dragStart.map { convertToImageCoordinates($0, imageSize: imageSize) }
            ?? convertToImageCoordinates(value.startLocation, imageSize: imageSize)

        switch tool {
        case .crop:
            // Crop rect is already set, just mark as not drawing
            break

        case .freehand:
            if currentDrawing.count > 1 {
                // Convert screen coordinates to image coordinates
                let imagePoints = currentDrawing.map { convertToImageCoordinates($0, imageSize: imageSize) }
                let annotation = Annotation.freehand(points: imagePoints, color: color)
                annotationVM.addAnnotation(annotation)
            }
            currentDrawing.removeAll()

        case .arrow:
            let annotation = Annotation.arrow(from: startLocation, to: location, color: color)
            annotationVM.addAnnotation(annotation)

        case .rectangle:
            let annotation = Annotation.rectangle(from: startLocation, to: location, color: color)
            annotationVM.addAnnotation(annotation)

        case .text:
            // Text uses tap gesture instead
            break
        }

        dragStart = nil
        currentDragEnd = nil
        annotationVM.isDrawing = false
    }

    // MARK: - Helpers

    private func calculateDisplaySize(for imageSize: CGSize) -> CGSize {
        guard containerSize.width > 40, containerSize.height > 40,
              imageSize.width > 0, imageSize.height > 0
        else {
            return CGSize(width: 1, height: 1)
        }

        let maxWidth = containerSize.width - 40
        let maxHeight = containerSize.height - 40

        let widthRatio = maxWidth / imageSize.width
        let heightRatio = maxHeight / imageSize.height
        let ratio = min(widthRatio, heightRatio)

        return CGSize(
            width: max(1, imageSize.width * ratio),
            height: max(1, imageSize.height * ratio)
        )
    }

    private func convertToImageCoordinates(_ point: CGPoint, imageSize _: CGSize) -> CGPoint {
        // This assumes the point is already in the canvas coordinate system
        // and the image is displayed at imageSize (which is the display size)
        guard let image = annotationVM.activeImage?.screenshot.image else {
            return point
        }

        let displaySize = calculateDisplaySize(for: image.size)
        let scaleX = image.size.width / displaySize.width
        let scaleY = image.size.height / displaySize.height

        return CGPoint(
            x: point.x * scaleX,
            y: point.y * scaleY
        )
    }
}

// MARK: - Crop Overlay View

struct CropOverlayView: View {
    let cropRect: CGRect
    let imageSize: CGSize
    let onUpdate: (CGRect) -> Void
    let onApply: () -> Void
    let onCancel: () -> Void

    @State private var dragOffset: CGSize = .zero
    @State private var activeHandle: CropHandle?

    enum CropHandle {
        case topLeft, topRight, bottomLeft, bottomRight
        case top, bottom, left, right
        case center
    }

    var body: some View {
        ZStack {
            // Dimmed overlay outside crop area
            DimmedOverlayShape(cropRect: effectiveCropRect)
                .fill(Color.black.opacity(0.5))
                .allowsHitTesting(false)

            // Crop rectangle
            Rectangle()
                .strokeBorder(Color.white, lineWidth: 2)
                .frame(width: effectiveCropRect.width, height: effectiveCropRect.height)
                .position(
                    x: effectiveCropRect.midX,
                    y: effectiveCropRect.midY
                )
                .shadow(color: .black.opacity(0.3), radius: 2)

            // Grid lines (rule of thirds)
            gridLines

            // Corner handles
            cornerHandles

            // Apply/Cancel buttons
            buttonOverlay
        }
        .contentShape(Rectangle())
    }

    private var effectiveCropRect: CGRect {
        cropRect.offsetBy(dx: dragOffset.width, dy: dragOffset.height)
    }

    private var gridLines: some View {
        Path { path in
            let rect = effectiveCropRect
            // Vertical lines
            path.move(to: CGPoint(x: rect.minX + rect.width / 3, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX + rect.width / 3, y: rect.maxY))
            path.move(to: CGPoint(x: rect.minX + 2 * rect.width / 3, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX + 2 * rect.width / 3, y: rect.maxY))
            // Horizontal lines
            path.move(to: CGPoint(x: rect.minX, y: rect.minY + rect.height / 3))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height / 3))
            path.move(to: CGPoint(x: rect.minX, y: rect.minY + 2 * rect.height / 3))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + 2 * rect.height / 3))
        }
        .stroke(Color.white.opacity(0.5), lineWidth: 0.5)
    }

    private var cornerHandles: some View {
        let handleSize: CGFloat = 12
        let rect = effectiveCropRect

        return ZStack {
            // Corner handles
            ForEach([
                (CGPoint(x: rect.minX, y: rect.minY), CropHandle.topLeft),
                (CGPoint(x: rect.maxX, y: rect.minY), CropHandle.topRight),
                (CGPoint(x: rect.minX, y: rect.maxY), CropHandle.bottomLeft),
                (CGPoint(x: rect.maxX, y: rect.maxY), CropHandle.bottomRight)
            ], id: \.1) { position, _ in
                Circle()
                    .fill(Color.white)
                    .frame(width: handleSize, height: handleSize)
                    .position(position)
                    .shadow(color: .black.opacity(0.3), radius: 2)
            }
        }
    }

    private var buttonOverlay: some View {
        VStack {
            Spacer()
            HStack(spacing: 16) {
                Button("Cancel") {
                    onCancel()
                }
                .buttonStyle(.bordered)

                Button("Apply Crop") {
                    onApply()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(.bottom, 20)
    }
}

// MARK: - Dimmed Overlay Shape

struct DimmedOverlayShape: Shape {
    let cropRect: CGRect

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(rect)
        path.addRect(cropRect)
        return path
    }
}

// MARK: - Preview

#Preview {
    AnnotationCanvasView()
        .environmentObject(AnnotationViewModel())
        .frame(width: 800, height: 600)
}

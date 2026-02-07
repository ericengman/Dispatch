//
//  AnnotationRenderer.swift
//  Dispatch
//
//  Renders annotations onto screenshots for export
//

import AppKit
import Foundation

// MARK: - Annotation Renderer

/// Renders annotations onto images for export
final class AnnotationRenderer: @unchecked Sendable {
    // MARK: - Properties

    private let queue = DispatchQueue(label: "com.dispatch.annotation.renderer", qos: .userInitiated)

    // MARK: - Singleton

    static let shared = AnnotationRenderer()

    private init() {}

    // MARK: - Rendering

    /// Renders an annotated image with all annotations and optional crop
    func render(_ annotatedImage: AnnotatedImage) async -> NSImage? {
        guard let originalImage = annotatedImage.screenshot.image else {
            logWarning("Cannot render: original image not found", category: .simulator)
            return nil
        }

        return await withCheckedContinuation { continuation in
            queue.async {
                let result = self.renderSync(
                    originalImage: originalImage,
                    annotations: annotatedImage.annotations,
                    cropRect: annotatedImage.cropRect
                )
                continuation.resume(returning: result)
            }
        }
    }

    /// Synchronous rendering for internal use
    private func renderSync(
        originalImage: NSImage,
        annotations: [Annotation],
        cropRect: CGRect?
    ) -> NSImage? {
        let imageSize = originalImage.size

        // Determine output size based on crop
        let outputSize: NSSize
        let drawOrigin: CGPoint

        if let crop = cropRect {
            outputSize = crop.size
            drawOrigin = CGPoint(x: -crop.origin.x, y: -crop.origin.y)
        } else {
            outputSize = imageSize
            drawOrigin = .zero
        }

        // Create new image
        let outputImage = NSImage(size: outputSize)
        outputImage.lockFocus()

        defer {
            outputImage.unlockFocus()
        }

        guard let context = NSGraphicsContext.current?.cgContext else {
            logError("Failed to get graphics context", category: .simulator)
            return nil
        }

        // Draw original image
        originalImage.draw(
            in: NSRect(origin: drawOrigin, size: imageSize),
            from: NSRect(origin: .zero, size: imageSize),
            operation: .copy,
            fraction: 1.0
        )

        // Draw annotations
        for annotation in annotations {
            drawAnnotation(annotation, in: context, offset: drawOrigin)
        }

        return outputImage
    }

    // MARK: - Drawing Annotations

    private func drawAnnotation(_ annotation: Annotation, in context: CGContext, offset: CGPoint) {
        let color = annotation.color.nsColor.cgColor
        context.setStrokeColor(color)
        context.setFillColor(color)
        context.setLineWidth(annotation.lineWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        switch annotation.type {
        case .freehand:
            drawFreehand(annotation, in: context, offset: offset)

        case .arrow:
            drawArrow(annotation, in: context, offset: offset)

        case .rectangle:
            drawRectangle(annotation, in: context, offset: offset)

        case .text:
            drawText(annotation, in: context, offset: offset)
        }
    }

    private func drawFreehand(_ annotation: Annotation, in context: CGContext, offset: CGPoint) {
        guard annotation.points.count > 1 else { return }

        context.beginPath()

        let firstPoint = annotation.points[0].applying(CGAffineTransform(translationX: offset.x, y: offset.y))
        context.move(to: firstPoint)

        for i in 1 ..< annotation.points.count {
            let point = annotation.points[i].applying(CGAffineTransform(translationX: offset.x, y: offset.y))
            context.addLine(to: point)
        }

        context.strokePath()
    }

    private func drawArrow(_ annotation: Annotation, in context: CGContext, offset: CGPoint) {
        guard annotation.points.count >= 2 else { return }

        let start = annotation.points[0].applying(CGAffineTransform(translationX: offset.x, y: offset.y))
        let end = annotation.points[1].applying(CGAffineTransform(translationX: offset.x, y: offset.y))

        // Draw line
        context.beginPath()
        context.move(to: start)
        context.addLine(to: end)
        context.strokePath()

        // Draw arrowhead
        let arrowLength: CGFloat = 15.0
        let arrowAngle: CGFloat = .pi / 6 // 30 degrees

        let angle = atan2(end.y - start.y, end.x - start.x)

        let arrowPoint1 = CGPoint(
            x: end.x - arrowLength * cos(angle - arrowAngle),
            y: end.y - arrowLength * sin(angle - arrowAngle)
        )

        let arrowPoint2 = CGPoint(
            x: end.x - arrowLength * cos(angle + arrowAngle),
            y: end.y - arrowLength * sin(angle + arrowAngle)
        )

        context.beginPath()
        context.move(to: end)
        context.addLine(to: arrowPoint1)
        context.addLine(to: arrowPoint2)
        context.closePath()
        context.fillPath()
    }

    private func drawRectangle(_ annotation: Annotation, in context: CGContext, offset: CGPoint) {
        guard annotation.points.count >= 2 else { return }

        let p1 = annotation.points[0].applying(CGAffineTransform(translationX: offset.x, y: offset.y))
        let p2 = annotation.points[1].applying(CGAffineTransform(translationX: offset.x, y: offset.y))

        let rect = CGRect(
            x: min(p1.x, p2.x),
            y: min(p1.y, p2.y),
            width: abs(p2.x - p1.x),
            height: abs(p2.y - p1.y)
        )

        context.stroke(rect)
    }

    private func drawText(_ annotation: Annotation, in _: CGContext, offset: CGPoint) {
        guard let text = annotation.text, !text.isEmpty,
              let firstPoint = annotation.points.first else { return }

        let point = firstPoint.applying(CGAffineTransform(translationX: offset.x, y: offset.y))

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 16, weight: .semibold),
            .foregroundColor: annotation.color.nsColor,
            .backgroundColor: NSColor.white.withAlphaComponent(0.8)
        ]

        let attributedString = NSAttributedString(string: text, attributes: attributes)
        attributedString.draw(at: point)
    }

    // MARK: - Export

    /// Exports an annotated image to PNG data
    func exportToPNG(_ annotatedImage: AnnotatedImage) async -> Data? {
        guard let rendered = await render(annotatedImage) else { return nil }
        return pngData(from: rendered)
    }

    /// Exports an annotated image to JPEG data
    func exportToJPEG(_ annotatedImage: AnnotatedImage, quality: CGFloat = 0.9) async -> Data? {
        guard let rendered = await render(annotatedImage) else { return nil }
        return jpegData(from: rendered, quality: quality)
    }

    /// Converts NSImage to PNG data
    func pngData(from image: NSImage) -> Data? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData)
        else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }

    /// Converts NSImage to JPEG data
    func jpegData(from image: NSImage, quality: CGFloat = 0.9) -> Data? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData)
        else {
            return nil
        }
        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: quality])
    }

    // MARK: - Batch Rendering

    /// Renders multiple annotated images in parallel
    func renderBatch(_ images: [AnnotatedImage]) async -> [NSImage] {
        await withTaskGroup(of: (Int, NSImage?).self) { group in
            for (index, image) in images.enumerated() {
                group.addTask {
                    let rendered = await self.render(image)
                    return (index, rendered)
                }
            }

            var results: [(Int, NSImage?)] = []
            for await result in group {
                results.append(result)
            }

            return results
                .sorted { $0.0 < $1.0 }
                .compactMap { $0.1 }
        }
    }

    // MARK: - Clipboard Operations

    /// Copies rendered images to the clipboard
    func copyToClipboard(_ images: [AnnotatedImage]) async -> Bool {
        let rendered = await renderBatch(images)
        guard !rendered.isEmpty else {
            logWarning("No images to copy to clipboard", category: .simulator)
            return false
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        let success = pasteboard.writeObjects(rendered)

        if success {
            logInfo("Copied \(rendered.count) image(s) to clipboard", category: .simulator)
        } else {
            logError("Failed to copy images to clipboard", category: .simulator)
        }

        return success
    }

    /// Copies a single rendered image to the clipboard
    func copyToClipboard(_ image: AnnotatedImage) async -> Bool {
        await copyToClipboard([image])
    }
}

// MARK: - Undo/Redo Manager

/// Manages undo/redo stack for annotation operations
final class AnnotationUndoManager: @unchecked Sendable {
    // MARK: - Properties

    private var undoStack: [AnnotationAction] = []
    private var redoStack: [AnnotationAction] = []
    private let maxStackSize = 50
    private let lock = NSLock()

    // MARK: - State

    var canUndo: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !undoStack.isEmpty
    }

    var canRedo: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !redoStack.isEmpty
    }

    // MARK: - Operations

    /// Records an action for potential undo
    func recordAction(_ action: AnnotationAction) {
        lock.lock()
        defer { lock.unlock() }

        undoStack.append(action)
        redoStack.removeAll()

        // Trim stack if too large
        if undoStack.count > maxStackSize {
            undoStack.removeFirst()
        }

        logDebug("Recorded action: \(action), undo stack size: \(undoStack.count)", category: .simulator)
    }

    /// Pops and returns the last action for undo
    func popUndo() -> AnnotationAction? {
        lock.lock()
        defer { lock.unlock() }

        guard let action = undoStack.popLast() else { return nil }
        redoStack.append(action)

        logDebug("Undo: \(action), redo stack size: \(redoStack.count)", category: .simulator)
        return action
    }

    /// Pops and returns the last action for redo
    func popRedo() -> AnnotationAction? {
        lock.lock()
        defer { lock.unlock() }

        guard let action = redoStack.popLast() else { return nil }
        undoStack.append(action)

        logDebug("Redo: \(action), undo stack size: \(undoStack.count)", category: .simulator)
        return action
    }

    /// Clears all undo/redo history
    func clear() {
        lock.lock()
        defer { lock.unlock() }

        undoStack.removeAll()
        redoStack.removeAll()

        logDebug("Cleared undo/redo history", category: .simulator)
    }
}

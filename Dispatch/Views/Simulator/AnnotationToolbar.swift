//
//  AnnotationToolbar.swift
//  Dispatch
//
//  Toolbar for selecting annotation tools and colors
//

import SwiftUI

struct AnnotationToolbar: View {
    @EnvironmentObject private var annotationVM: AnnotationViewModel

    var body: some View {
        HStack(spacing: 16) {
            // Tool selection
            toolsSection

            Divider()
                .frame(height: 24)

            // Color picker
            colorSection

            Divider()
                .frame(height: 24)

            // Actions
            actionsSection

            Spacer()

            // Zoom controls
            zoomSection
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Tools Section

    private var toolsSection: some View {
        HStack(spacing: 4) {
            ForEach(AnnotationTool.allCases) { tool in
                ToolButton(
                    tool: tool,
                    isSelected: annotationVM.currentTool == tool,
                    action: { annotationVM.selectTool(tool) }
                )
            }
        }
    }

    // MARK: - Color Section

    private var colorSection: some View {
        HStack(spacing: 4) {
            ForEach(AnnotationColor.allCases) { color in
                ColorButton(
                    color: color,
                    isSelected: annotationVM.currentColor == color,
                    action: { annotationVM.selectColor(color) }
                )
            }
        }
    }

    // MARK: - Actions Section

    private var actionsSection: some View {
        HStack(spacing: 8) {
            Button {
                annotationVM.undo()
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .buttonStyle(.borderless)
            .disabled(!annotationVM.canUndo)
            .keyboardShortcut("z", modifiers: .command)
            .help("Undo (⌘Z)")

            Button {
                annotationVM.redo()
            } label: {
                Image(systemName: "arrow.uturn.forward")
            }
            .buttonStyle(.borderless)
            .disabled(!annotationVM.canRedo)
            .keyboardShortcut("z", modifiers: [.command, .shift])
            .help("Redo (⇧⌘Z)")

            Divider()
                .frame(height: 16)

            Button {
                annotationVM.clearAnnotations()
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .disabled(annotationVM.activeImage?.annotations.isEmpty ?? true)
            .help("Clear Annotations")
        }
    }

    // MARK: - Zoom Section

    private var zoomSection: some View {
        HStack(spacing: 8) {
            Button {
                annotationVM.zoomOut()
            } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            .buttonStyle(.borderless)
            .help("Zoom Out")

            Text("\(Int(annotationVM.zoomLevel * 100))%")
                .font(.caption)
                .monospacedDigit()
                .frame(width: 40)

            Button {
                annotationVM.zoomIn()
            } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            .buttonStyle(.borderless)
            .help("Zoom In")

            Button {
                annotationVM.resetZoom()
            } label: {
                Image(systemName: "1.magnifyingglass")
            }
            .buttonStyle(.borderless)
            .help("Reset Zoom (100%)")
        }
    }
}

// MARK: - Tool Button

struct ToolButton: View {
    let tool: AnnotationTool
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: tool.iconName)
                    .font(.system(size: 14))

                Text(String(tool.shortcutKey).uppercased())
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 36, height: 36)
            .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help("\(tool.displayName) (\(String(tool.shortcutKey).uppercased()))")
    }
}

// MARK: - Color Button

struct ColorButton: View {
    let color: AnnotationColor
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(color.color)
                    .frame(width: 20, height: 20)

                if color == .white {
                    Circle()
                        .strokeBorder(Color.secondary.opacity(0.5), lineWidth: 1)
                        .frame(width: 20, height: 20)
                }

                if isSelected {
                    Circle()
                        .strokeBorder(Color.primary, lineWidth: 2)
                        .frame(width: 26, height: 26)
                }
            }
            .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .help("\(color.rawValue.capitalized) (\(color.shortcutNumber))")
    }
}

// MARK: - Preview

#Preview {
    AnnotationToolbar()
        .environmentObject(AnnotationViewModel())
        .frame(width: 700)
}

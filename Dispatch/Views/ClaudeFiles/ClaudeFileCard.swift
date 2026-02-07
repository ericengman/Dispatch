//
//  ClaudeFileCard.swift
//  Dispatch
//
//  Card view for CLAUDE.md files
//

import SwiftUI

struct ClaudeFileCard: View {
    let file: ClaudeFile
    @Binding var selectedFile: ClaudeFile?

    @State private var isHovering = false

    private var isSelected: Bool {
        selectedFile?.id == file.id
    }

    var body: some View {
        cardContent
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 70, alignment: .topLeading)
            .background(cardBackground)
            .overlay(cardBorder)
            .contentShape(Rectangle())
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHovering = hovering
                }
            }
            .onTapGesture(count: 2) {
                file.openInEditor()
            }
            .onTapGesture(count: 1) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if selectedFile?.id == file.id {
                        selectedFile = nil
                    } else {
                        selectedFile = file
                    }
                }
            }
    }

    // MARK: - Card Content

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            headerView
            Spacer()
            footerView
        }
    }

    private var headerView: some View {
        HStack(alignment: .top) {
            Text(file.shortName)
                .font(.subheadline.weight(.medium))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .foregroundStyle(.primary)

            Spacer()

            Image(systemName: file.scope.icon)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var footerView: some View {
        HStack {
            if file.exists {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.green.opacity(0.7))
            } else {
                Image(systemName: "plus.circle.dashed")
                    .font(.caption2)
                    .foregroundStyle(.secondary.opacity(0.5))
            }

            Spacer()

            if isHovering {
                Button {
                    file.openInEditor()
                } label: {
                    Image(systemName: "arrow.up.right.square")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Open in external editor")
            }
        }
    }

    // MARK: - Card Styling

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(isSelected ? Color.accentColor.opacity(0.15) : Color(nsColor: .controlBackgroundColor))
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 8)
            .strokeBorder(
                isSelected ? Color.accentColor.opacity(0.5) : Color.secondary.opacity(0.2),
                lineWidth: 1
            )
    }
}

// MARK: - Preview

#Preview {
    let systemFile = ClaudeFile(
        scope: .system,
        filePath: URL(fileURLWithPath: "/Users/test/.claude/CLAUDE.md")
    )

    return VStack(spacing: 16) {
        ClaudeFileCard(file: systemFile, selectedFile: .constant(nil))
            .frame(width: 120)

        ClaudeFileCard(file: systemFile, selectedFile: .constant(systemFile))
            .frame(width: 120)
    }
    .padding()
}

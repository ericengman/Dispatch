//
//  SkillFileViewer.swift
//  Dispatch
//
//  Quick viewer for skill file content
//

import SwiftUI

struct SkillFileViewer: View {
    // MARK: - Properties

    let skill: Skill
    let onDismiss: () -> Void

    // MARK: - State

    @State private var fileContent: String = ""
    @State private var isLoading = true

    // MARK: - Body

    var body: some View {
        Button {
            onDismiss()
        } label: {
            VStack(spacing: 0) {
                // Header
                headerView

                Divider()

                // Content
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        Text(fileContent)
                            .font(.system(.body, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .textSelection(.enabled)
                    }
                }

                Divider()

                // Footer hint
                footerView
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor))
        }
        .buttonStyle(.plain)
        .onAppear {
            loadContent()
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(skill.name)
                    .font(.headline)

                Text(skill.filePath.path)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            // Open in editor button
            Button {
                SkillManager.shared.openSkillFile(skill)
            } label: {
                Label("Open File", systemImage: "arrow.up.forward.square")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding()
        .background(.bar)
    }

    // MARK: - Footer

    private var footerView: some View {
        HStack {
            Spacer()

            Text("Tap anywhere to close")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Spacer()
        }
        .padding(.vertical, 8)
        .background(.bar)
    }

    // MARK: - Actions

    private func loadContent() {
        Task {
            do {
                let content = try String(contentsOf: skill.filePath, encoding: .utf8)
                await MainActor.run {
                    fileContent = content
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    fileContent = "Error loading file: \(error.localizedDescription)"
                    isLoading = false
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    SkillFileViewer(
        skill: Skill(
            name: "Test Skill",
            description: "A test skill",
            content: "# Test\nThis is test content",
            scope: .system,
            filePath: URL(fileURLWithPath: "/tmp/test.md")
        ),
        onDismiss: {}
    )
    .frame(width: 600, height: 400)
}

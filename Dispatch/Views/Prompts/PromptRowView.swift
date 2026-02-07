//
//  PromptRowView.swift
//  Dispatch
//
//  Row view for displaying a single prompt in a list
//

import SwiftUI

struct PromptRowView: View {
    // MARK: - Properties

    let prompt: Prompt
    var onToggleStar: ((Prompt) -> Void)?

    // MARK: - Environment

    @Environment(\.colorScheme) private var colorScheme

    // MARK: - Body

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Star button
            Button {
                onToggleStar?(prompt)
            } label: {
                Image(systemName: prompt.isStarred ? "star.fill" : "star")
                    .foregroundStyle(prompt.isStarred ? .yellow : .secondary)
                    .font(.system(size: 14))
                    .frame(width: 20)
            }
            .buttonStyle(.plain)
            .help(prompt.isStarred ? "Remove from Starred" : "Add to Starred")

            // Content
            VStack(alignment: .leading, spacing: 4) {
                // Title row
                HStack {
                    Text(prompt.displayTitle)
                        .font(.headline)
                        .lineLimit(1)

                    Spacer()

                    // Project badge
                    if let project = prompt.project {
                        ProjectBadgeView(project: project)
                    }

                    // Relative time
                    Text(prompt.relativeUpdatedTime)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Preview text
                if !prompt.previewText.isEmpty && prompt.previewText != prompt.displayTitle {
                    Text(prompt.previewText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                // Indicators
                HStack(spacing: 8) {
                    // Usage count
                    if prompt.usageCount > 0 {
                        Label("\(prompt.usageCount)", systemImage: "arrow.up.circle")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    // Placeholder indicator
                    if prompt.hasPlaceholders {
                        Label("Placeholders", systemImage: "curlybraces")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

// MARK: - Compact Row View

struct PromptRowCompactView: View {
    let prompt: Prompt

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: prompt.isStarred ? "star.fill" : "star")
                .foregroundStyle(prompt.isStarred ? .yellow : .secondary)
                .font(.system(size: 12))

            Text(prompt.displayTitle)
                .font(.body)
                .lineLimit(1)

            Spacer()

            if let project = prompt.project {
                Circle()
                    .fill(project.color)
                    .frame(width: 8, height: 8)
            }

            Text(prompt.relativeUpdatedTime)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Preview

#Preview {
    VStack {
        PromptRowView(prompt: PreviewData.samplePrompt)
            .padding()

        Divider()

        PromptRowCompactView(prompt: PreviewData.samplePrompt)
            .padding()
    }
    .frame(width: 400)
}

// MARK: - Preview Data

enum PreviewData {
    static var samplePrompt: Prompt {
        let prompt = Prompt(
            title: "Sample Prompt",
            content: "This is a sample prompt with some content that demonstrates how the row view works.",
            isStarred: true,
            usageCount: 5
        )
        return prompt
    }
}

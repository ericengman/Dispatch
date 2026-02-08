//
//  SessionResumePicker.swift
//  Dispatch
//
//  Picker for selecting a Claude Code session to resume
//

import SwiftUI

struct SessionResumePicker: View {
    let sessions: [ClaudeCodeSession]
    let onSelect: (ClaudeCodeSession?) -> Void // nil = start fresh

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Resume Previous Session")
                    .font(.headline)
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding()

            Divider()

            if sessions.isEmpty {
                ContentUnavailableView(
                    "No Recent Sessions",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("No sessions found for this project")
                )
                .frame(minHeight: 200)
            } else {
                // Session list
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(sessions) { session in
                            SessionResumeRow(session: session) {
                                onSelect(session)
                                dismiss()
                            }
                        }
                    }
                    .padding()
                }
                .frame(maxHeight: 300)
            }

            Divider()

            // Start Fresh button
            HStack {
                Spacer()
                Button("Start Fresh Session") {
                    onSelect(nil)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 500)
    }
}

private struct SessionResumeRow: View {
    let session: ClaudeCodeSession
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                // Message count badge
                VStack {
                    Text("\(session.messageCount)")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("msgs")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(width: 40)
                .padding(.vertical, 4)
                .background(Color.accentColor.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 4) {
                    // First prompt (truncated)
                    Text(session.displayPrompt)
                        .font(.body)
                        .lineLimit(2)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)

                    // Metadata row
                    HStack(spacing: 8) {
                        // Git branch
                        if let branch = session.gitBranch, !branch.isEmpty {
                            Label(branch, systemImage: "arrow.triangle.branch")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        // Relative time
                        Text(session.relativeModified)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()

                Image(systemName: "arrow.right.circle")
                    .foregroundStyle(.secondary)
                    .imageScale(.large)
            }
            .padding(10)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    SessionResumePicker(
        sessions: [
            ClaudeCodeSession(
                sessionId: "123",
                projectPath: "/Users/eric/Dispatch",
                firstPrompt: "I hit send on a prompt and nothing happened. The logic for sending the prompts works in skills, can you ensure that logic is transferred over to the prompts as well",
                messageCount: 49,
                created: Date().addingTimeInterval(-3600 * 24),
                modified: Date().addingTimeInterval(-3600 * 2),
                gitBranch: "feature/skills-dispatch"
            ),
            ClaudeCodeSession(
                sessionId: "456",
                projectPath: "/Users/eric/Dispatch",
                firstPrompt: "Fix the bug in checkout",
                messageCount: 12,
                created: Date().addingTimeInterval(-3600 * 48),
                modified: Date().addingTimeInterval(-3600 * 5),
                gitBranch: "main"
            )
        ]
    ) { session in
        print("Selected: \(session?.sessionId ?? "new")")
    }
}

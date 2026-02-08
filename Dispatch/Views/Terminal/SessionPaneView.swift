//
//  SessionPaneView.swift
//  Dispatch
//
//  Wrapper view for individual terminal session with header and focus indicator
//

import SwiftUI

struct SessionPaneView: View {
    let session: TerminalSession

    @State private var sessionManager = TerminalSessionManager.shared

    private var isActive: Bool {
        sessionManager.activeSessionId == session.id
    }

    var body: some View {
        VStack(spacing: 0) {
            // Session header
            HStack(spacing: 8) {
                // Active indicator
                Circle()
                    .fill(isActive ? Color.accentColor : Color.clear)
                    .frame(width: 8, height: 8)

                Text(session.name)
                    .font(.caption)
                    .fontWeight(isActive ? .semibold : .regular)
                    .foregroundStyle(isActive ? .primary : .secondary)
                    .lineLimit(1)

                Spacer()

                // Close button
                Button {
                    sessionManager.closeSession(session.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .opacity(0.7)
                .help("Close session")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isActive ? Color.accentColor.opacity(0.1) : Color(nsColor: .controlBackgroundColor))

            Divider()

            // Terminal view with session ID
            EmbeddedTerminalView(
                sessionId: session.id,
                launchMode: .claudeCode(workingDirectory: nil, skipPermissions: true)
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isActive ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: isActive ? 2 : 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            // SESS-04: Clicking makes session active for prompt dispatch
            sessionManager.setActiveSession(session.id)
        }
    }
}

#Preview {
    SessionPaneView(session: TerminalSession(name: "Test Session"))
        .frame(width: 400, height: 300)
}

//
//  SessionTabBar.swift
//  Dispatch
//
//  Tab bar for session switching with new session button
//

import SwiftUI

struct SessionTabBar: View {
    @State private var sessionManager = TerminalSessionManager.shared

    var body: some View {
        HStack(spacing: 0) {
            // Session tabs
            ForEach(sessionManager.sessions) { session in
                SessionTab(session: session)
            }

            Spacer()

            // New session button
            Button {
                _ = sessionManager.createSession()
            } label: {
                Image(systemName: "plus")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .disabled(!sessionManager.canCreateSession)
            .opacity(sessionManager.canCreateSession ? 1.0 : 0.5)
            .help(sessionManager.canCreateSession ? "New Session" : "Max sessions reached")
            .padding(.horizontal, 8)
        }
        .frame(height: 28)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

private struct SessionTab: View {
    let session: TerminalSession
    @State private var sessionManager = TerminalSessionManager.shared

    private var isActive: Bool {
        sessionManager.activeSessionId == session.id
    }

    var body: some View {
        HStack(spacing: 4) {
            Text(session.name)
                .font(.caption)
                .fontWeight(isActive ? .semibold : .regular)
                .foregroundStyle(isActive ? .primary : .secondary)
                .lineLimit(1)

            Button {
                sessionManager.closeSession(session.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .opacity(0.6)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(isActive ? Color.accentColor.opacity(0.2) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .contentShape(Rectangle())
        .onTapGesture {
            sessionManager.setActiveSession(session.id)
        }
    }
}

#Preview {
    VStack {
        SessionTabBar()
    }
    .frame(width: 600)
}

//
//  SessionTabBar.swift
//  Dispatch
//
//  Tab bar for session switching with new session button
//

import SwiftUI

struct SessionTabBar: View {
    @State private var sessionManager = TerminalSessionManager.shared
    @State private var showResumePicker = false
    @State private var recentSessions: [ClaudeCodeSession] = []

    // Project path for session discovery (defaults to current directory)
    var projectPath: String?

    var body: some View {
        HStack(spacing: 0) {
            // Session tabs
            ForEach(sessionManager.sessions) { session in
                SessionTab(session: session)
            }

            Spacer()

            // New session menu
            Menu {
                Button("New Session", systemImage: "plus") {
                    _ = sessionManager.createSession()
                }

                Divider()

                Button("Resume Previous...", systemImage: "clock.arrow.circlepath") {
                    Task {
                        await loadRecentSessions()
                        showResumePicker = true
                    }
                }
            } label: {
                Image(systemName: "plus")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(!sessionManager.canCreateSession)
            .opacity(sessionManager.canCreateSession ? 1.0 : 0.5)
            .help(sessionManager.canCreateSession ? "New Session" : "Max sessions reached")
            .padding(.horizontal, 8)
        }
        .frame(height: 28)
        .background(Color(nsColor: .controlBackgroundColor))
        .sheet(isPresented: $showResumePicker) {
            SessionResumePicker(sessions: recentSessions) { selectedSession in
                if let session = selectedSession {
                    _ = sessionManager.createResumeSession(claudeSession: session)
                } else {
                    _ = sessionManager.createSession()
                }
            }
        }
    }

    private func loadRecentSessions() async {
        let path = projectPath ?? FileManager.default.currentDirectoryPath
        recentSessions = await ClaudeSessionDiscoveryService.shared.getRecentSessions(for: path)
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

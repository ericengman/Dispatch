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
        // Terminal view with session ID - no header since tab bar handles session switching
        EmbeddedTerminalView(
            sessionId: session.id,
            launchMode: .claudeCode(workingDirectory: nil, skipPermissions: true)
        )
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(isActive ? Color.accentColor : Color.clear, lineWidth: 2)
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

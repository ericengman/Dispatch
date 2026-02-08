//
//  MultiSessionTerminalView.swift
//  Dispatch
//
//  Container view for multi-session terminal with tab bar and layout modes
//

import SwiftUI

struct MultiSessionTerminalView: View {
    @State private var sessionManager = TerminalSessionManager.shared

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar for session switching
            SessionTabBar()
            Divider()

            // Layout mode picker (only show with 2+ sessions)
            if sessionManager.sessions.count >= 2 {
                HStack {
                    Picker("Layout", selection: $sessionManager.layoutMode) {
                        Label("Focus", systemImage: "rectangle").tag(TerminalSessionManager.LayoutMode.single)
                        Label("Side by Side", systemImage: "rectangle.split.2x1").tag(TerminalSessionManager.LayoutMode.horizontalSplit)
                        Label("Stacked", systemImage: "rectangle.split.1x2").tag(TerminalSessionManager.LayoutMode.verticalSplit)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(nsColor: .controlBackgroundColor))

                Divider()
            }

            // Terminal content area
            if sessionManager.sessions.isEmpty {
                // Empty state
                ContentUnavailableView(
                    "No Sessions",
                    systemImage: "terminal",
                    description: Text("Create a new session to get started")
                )
            } else {
                terminalContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            // Auto-create first session if none exist
            if sessionManager.sessions.isEmpty {
                _ = sessionManager.createSession()
            }
        }
    }

    @ViewBuilder
    private var terminalContent: some View {
        switch sessionManager.layoutMode {
        case .single:
            // Focus mode: show active session fullscreen
            if let activeSession = sessionManager.activeSession {
                SessionPaneView(session: activeSession)
                    .id(activeSession.id)
                    .padding(8)
            }

        case .horizontalSplit:
            // Side-by-side: show first 2 sessions
            HSplitView {
                if let first = sessionManager.sessions.first {
                    SessionPaneView(session: first)
                        .id(first.id)
                        .padding(8)
                }

                if sessionManager.sessions.count > 1 {
                    SessionPaneView(session: sessionManager.sessions[1])
                        .id(sessionManager.sessions[1].id)
                        .padding(8)
                }
            }

        case .verticalSplit:
            // Stacked: show first 2 sessions
            VSplitView {
                if let first = sessionManager.sessions.first {
                    SessionPaneView(session: first)
                        .id(first.id)
                        .padding(8)
                }

                if sessionManager.sessions.count > 1 {
                    SessionPaneView(session: sessionManager.sessions[1])
                        .id(sessionManager.sessions[1].id)
                        .padding(8)
                }
            }
        }
    }
}

#Preview {
    MultiSessionTerminalView()
        .frame(width: 800, height: 600)
}

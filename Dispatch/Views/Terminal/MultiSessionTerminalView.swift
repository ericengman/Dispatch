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
        // Use GeometryReader to handle layout ourselves without recreating views
        GeometryReader { geometry in
            let sessions = sessionManager.sessions
            let activeId = sessionManager.activeSessionId

            ZStack {
                // Always keep all session views alive to prevent recreation
                ForEach(sessions) { session in
                    SessionPaneView(session: session)
                        .frame(
                            width: frameWidth(for: session, in: geometry, sessions: sessions),
                            height: frameHeight(for: session, in: geometry, sessions: sessions)
                        )
                        .position(
                            x: positionX(for: session, in: geometry, sessions: sessions),
                            y: positionY(for: session, in: geometry, sessions: sessions)
                        )
                        .opacity(shouldShow(session: session, activeId: activeId, sessions: sessions) ? 1 : 0)
                        .allowsHitTesting(shouldShow(session: session, activeId: activeId, sessions: sessions))
                }
            }
            .padding(8)
        }
    }

    // MARK: - Layout Calculations

    private func shouldShow(session: TerminalSession, activeId: UUID?, sessions: [TerminalSession]) -> Bool {
        switch sessionManager.layoutMode {
        case .single:
            return session.id == activeId
        case .horizontalSplit, .verticalSplit:
            guard let index = sessions.firstIndex(where: { $0.id == session.id }) else { return false }
            return index < 2
        }
    }

    private func frameWidth(for _: TerminalSession, in geometry: GeometryProxy, sessions _: [TerminalSession]) -> CGFloat {
        let available = geometry.size.width - 16 // Account for padding

        switch sessionManager.layoutMode {
        case .single:
            return available
        case .horizontalSplit:
            return (available - 8) / 2 // Split with gap
        case .verticalSplit:
            return available
        }
    }

    private func frameHeight(for _: TerminalSession, in geometry: GeometryProxy, sessions _: [TerminalSession]) -> CGFloat {
        let available = geometry.size.height - 16 // Account for padding

        switch sessionManager.layoutMode {
        case .single:
            return available
        case .horizontalSplit:
            return available
        case .verticalSplit:
            return (available - 8) / 2 // Split with gap
        }
    }

    private func positionX(for session: TerminalSession, in geometry: GeometryProxy, sessions: [TerminalSession]) -> CGFloat {
        let available = geometry.size.width - 16
        guard let index = sessions.firstIndex(where: { $0.id == session.id }) else {
            return available / 2
        }

        switch sessionManager.layoutMode {
        case .single:
            return available / 2
        case .horizontalSplit:
            let paneWidth = (available - 8) / 2
            return index == 0 ? paneWidth / 2 : available - paneWidth / 2
        case .verticalSplit:
            return available / 2
        }
    }

    private func positionY(for session: TerminalSession, in geometry: GeometryProxy, sessions: [TerminalSession]) -> CGFloat {
        let available = geometry.size.height - 16
        guard let index = sessions.firstIndex(where: { $0.id == session.id }) else {
            return available / 2
        }

        switch sessionManager.layoutMode {
        case .single:
            return available / 2
        case .horizontalSplit:
            return available / 2
        case .verticalSplit:
            let paneHeight = (available - 8) / 2
            return index == 0 ? paneHeight / 2 : available - paneHeight / 2
        }
    }
}

#Preview {
    MultiSessionTerminalView()
        .frame(width: 800, height: 600)
}

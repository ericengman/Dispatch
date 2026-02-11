//
//  SessionPaneView.swift
//  Dispatch
//
//  Wrapper view for individual terminal session with header and focus indicator
//

import SwiftUI

struct SessionPaneView: View {
    let session: TerminalSession

    /// When true, adds padding/border/radius for split layouts. When false, fills edge-to-edge.
    var showChrome: Bool = true

    private var sessionManager: TerminalSessionManager { TerminalSessionManager.shared }
    /// Whether the close button is visible (mouse within proximity)
    @State private var showCloseButton = false

    private var isActive: Bool {
        sessionManager.activeSessionId == session.id
    }

    /// Distance in points from the top-right corner to trigger close button visibility
    private let closeButtonProximity: CGFloat = 100

    var body: some View {
        let mode = session.launchMode
        EmbeddedTerminalView(
            sessionId: session.id,
            launchMode: mode
        )
        .padding(showChrome ? 4 : 0)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: showChrome ? 4 : 0))
        .overlay(
            RoundedRectangle(cornerRadius: showChrome ? 4 : 0)
                .stroke(showChrome && isActive ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .overlay(alignment: .topTrailing) {
            Button {
                sessionManager.closeSession(session.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(8)
            .opacity(showCloseButton ? 1 : 0)
            .animation(.easeInOut(duration: 0.15), value: showCloseButton)
        }
        .overlay {
            GeometryReader { geometry in
                Color.clear
                    .onContinuousHover { phase in
                        switch phase {
                        case let .active(location):
                            // Button center is near top-right: (width - 18, 18)
                            let buttonCenter = CGPoint(x: geometry.size.width - 18, y: 18)
                            let dx = location.x - buttonCenter.x
                            let dy = location.y - buttonCenter.y
                            let distance = sqrt(dx * dx + dy * dy)
                            showCloseButton = distance < closeButtonProximity
                        case .ended:
                            showCloseButton = false
                        }
                    }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            sessionManager.setActiveSession(session.id)
        }
    }
}

#Preview {
    SessionPaneView(session: TerminalSession(name: "Test Session"))
        .frame(width: 400, height: 300)
}

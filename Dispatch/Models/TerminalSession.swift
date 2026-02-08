// TerminalSession.swift
// Observable model representing a single terminal session

import Foundation
import SwiftTerm

@Observable
final class TerminalSession: Identifiable {
    let id: UUID
    var name: String
    let createdAt: Date

    // Coordinator reference set by EmbeddedTerminalView
    weak var coordinator: EmbeddedTerminalView.Coordinator?

    // Terminal reference for monitoring
    weak var terminal: LocalProcessTerminalView?

    init(name: String? = nil) {
        id = UUID()
        self.name = name ?? "Session \(UUID().uuidString.prefix(8))"
        createdAt = Date()
    }

    var isReady: Bool {
        coordinator?.isReadyForDispatch ?? false
    }
}

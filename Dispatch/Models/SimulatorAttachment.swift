//
//  SimulatorAttachment.swift
//  Dispatch
//
//  Tracks an attached simulator window that follows Dispatch's main window
//

import Foundation

@Observable
@MainActor
final class SimulatorAttachment: Identifiable {
    let id: UUID
    let simulatorUDID: String
    let deviceName: String
    var windowNumber: Int?
    var isAttached: Bool = true

    init(id: UUID = UUID(), simulatorUDID: String, deviceName: String) {
        self.id = id
        self.simulatorUDID = simulatorUDID
        self.deviceName = deviceName
    }
}

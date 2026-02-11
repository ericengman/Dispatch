//
//  BuildDestination.swift
//  Dispatch
//
//  Value types for build destinations (simulators, devices, Mac)
//

import Foundation

// MARK: - Destination Platform

enum DestinationPlatform: String, Codable, Hashable, Sendable {
    case iOSSimulator
    case macOS
    case iOSDevice

    var displayName: String {
        switch self {
        case .iOSSimulator: return "iOS Simulator"
        case .macOS: return "macOS"
        case .iOSDevice: return "iOS Device"
        }
    }
}

// MARK: - Destination Group (for picker sections)

enum DestinationGroup: String, CaseIterable, Codable, Hashable, Sendable {
    case recent
    case iPhone
    case iPad
    case mac

    var displayName: String {
        switch self {
        case .recent: return "Recent"
        case .iPhone: return "iPhone"
        case .iPad: return "iPad"
        case .mac: return "Mac"
        }
    }

    var systemImage: String {
        switch self {
        case .recent: return "clock"
        case .iPhone: return "iphone"
        case .iPad: return "ipad"
        case .mac: return "macbook"
        }
    }
}

// MARK: - Build Destination

struct BuildDestination: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let platform: DestinationPlatform
    let name: String
    let osVersion: String?
    let udid: String?

    var displayName: String {
        if let osVersion {
            return "\(name) (\(osVersion))"
        }
        return name
    }

    var xcodebuildArg: String {
        switch platform {
        case .macOS:
            return "platform=macOS"
        case .iOSSimulator:
            if let udid {
                return "platform=iOS Simulator,id=\(udid)"
            }
            return "platform=iOS Simulator,name=\(name)"
        case .iOSDevice:
            if let udid {
                return "platform=iOS,id=\(udid)"
            }
            return "platform=iOS,name=\(name)"
        }
    }

    var group: DestinationGroup {
        switch platform {
        case .macOS: return .mac
        case .iOSDevice: return .iPhone
        case .iOSSimulator:
            let lowerName = name.lowercased()
            if lowerName.contains("ipad") {
                return .iPad
            }
            return .iPhone
        }
    }

    // Convenience initializer for macOS
    static var myMac: BuildDestination {
        BuildDestination(
            id: "macOS-local",
            platform: .macOS,
            name: "My Mac",
            osVersion: nil,
            udid: nil
        )
    }
}

//
//  XcodeProjectInfo.swift
//  Dispatch
//
//  Detected Xcode project metadata from a directory path
//

import Foundation

// MARK: - Project Type

enum XcodeProjectType: String, Codable, Sendable {
    case xcodeproj
    case xcworkspace
}

// MARK: - Platform Hint

enum PlatformHint: String, Codable, Sendable {
    case iOS
    case macOS
    case multiplatform
}

// MARK: - Xcode Project Info

struct XcodeProjectInfo: Sendable {
    let projectFilePath: String
    let projectType: XcodeProjectType
    let schemes: [String]
    let platformHint: PlatformHint

    var projectName: String {
        let url = URL(fileURLWithPath: projectFilePath)
        return url.deletingPathExtension().lastPathComponent
    }
}

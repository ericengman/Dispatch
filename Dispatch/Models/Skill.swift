//
//  Skill.swift
//  Dispatch
//
//  Model for Claude Code skills (custom slash commands)
//

import Foundation
import Combine
import AppKit

// MARK: - Skill Scope

enum SkillScope: String, Sendable, Identifiable, CaseIterable {
    case system = "System"
    case project = "Project"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .system: return "globe"
        case .project: return "folder"
        }
    }
}

// MARK: - Skill

struct Skill: Identifiable, Hashable, Sendable {
    let id: UUID
    let name: String
    let description: String
    let content: String
    let scope: SkillScope
    let filePath: URL
    let projectPath: URL?

    init(
        id: UUID = UUID(),
        name: String,
        description: String = "",
        content: String,
        scope: SkillScope,
        filePath: URL,
        projectPath: URL? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.content = content
        self.scope = scope
        self.filePath = filePath
        self.projectPath = projectPath
    }

    /// The command name (without the slash)
    var commandName: String {
        // For folder-based skills (skill-name/SKILL.md), use the parent folder name
        // For legacy direct .md files, use the filename without extension
        let fileName = filePath.deletingPathExtension().lastPathComponent
        if fileName.uppercased() == "SKILL" {
            // It's a folder-based skill, use parent directory name
            return filePath.deletingLastPathComponent().lastPathComponent
        }
        return fileName
    }

    /// The full slash command
    var slashCommand: String {
        "/\(commandName)"
    }

    /// Preview of the content (first line or truncated)
    var contentPreview: String {
        let firstLine = content.components(separatedBy: .newlines).first ?? content
        if firstLine.count > 100 {
            return String(firstLine.prefix(100)) + "..."
        }
        return firstLine
    }

    /// Whether this skill expects input parameters
    /// Detects common parameter patterns in skill content
    var hasInputParameters: Bool {
        let parameterPatterns = [
            "\\$1", "\\$2", "\\$3",           // Positional args
            "\\$\\{.*\\}",                     // ${variable}
            "\\$ARGS", "\\$INPUT",             // Named args
            "<[A-Z_]+>",                       // <PLACEHOLDER>
            "\\[required\\]", "\\[optional\\]", // [required] markers
            "{{.*}}",                          // {{mustache}}
            "%s", "%@"                         // Format specifiers
        ]

        for pattern in parameterPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(content.startIndex..., in: content)
                if regex.firstMatch(in: content, options: [], range: range) != nil {
                    return true
                }
            }
        }

        return false
    }
}

// MARK: - Skill Discovery Service

actor SkillDiscoveryService {
    static let shared = SkillDiscoveryService()

    private let fileManager = FileManager.default

    // System skills directory - ~/.claude/skills/
    private var systemSkillsDirectory: URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")
            .appendingPathComponent("skills")
    }

    private init() {
    }

    // MARK: - Discovery

    /// Discovers all system-wide skills
    func discoverSystemSkills() async -> [Skill] {
        logDebug("Discovering system skills at: \(systemSkillsDirectory.path)", category: .data)

        guard fileManager.fileExists(atPath: systemSkillsDirectory.path) else {
            logDebug("System skills directory doesn't exist", category: .data)
            return []
        }

        return await discoverSkills(in: systemSkillsDirectory, scope: .system, projectPath: nil)
    }

    /// Discovers project-level skills for a given project path
    func discoverProjectSkills(at projectPath: URL) async -> [Skill] {
        // Check both .claude/skills/ and .claude/commands/ for project skills
        let skillsDirs = [
            projectPath.appendingPathComponent(".claude").appendingPathComponent("skills"),
            projectPath.appendingPathComponent(".claude").appendingPathComponent("commands")
        ]

        var allSkills: [Skill] = []

        for skillsDir in skillsDirs {
            logDebug("Checking project skills at: \(skillsDir.path)", category: .data)

            if fileManager.fileExists(atPath: skillsDir.path) {
                let skills = await discoverSkills(in: skillsDir, scope: .project, projectPath: projectPath)
                allSkills.append(contentsOf: skills)
            }
        }

        return allSkills
    }

    /// Discovers all skills (system + all projects)
    func discoverAllSkills(projectPaths: [URL]) async -> [Skill] {
        var allSkills: [Skill] = []

        // System skills
        let systemSkills = await discoverSystemSkills()
        allSkills.append(contentsOf: systemSkills)

        // Project skills
        for projectPath in projectPaths {
            let projectSkills = await discoverProjectSkills(at: projectPath)
            allSkills.append(contentsOf: projectSkills)
        }

        logInfo("Discovered \(allSkills.count) total skills (\(systemSkills.count) system)", category: .data)
        return allSkills
    }

    // MARK: - Private

    private func discoverSkills(in directory: URL, scope: SkillScope, projectPath: URL?) async -> [Skill] {
        var skills: [Skill] = []

        do {
            let contents = try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )

            for itemURL in contents {
                var isDirectory: ObjCBool = false

                // Check if it's a directory (skill folder structure: skill-name/SKILL.md)
                if fileManager.fileExists(atPath: itemURL.path, isDirectory: &isDirectory), isDirectory.boolValue {
                    let skillFile = itemURL.appendingPathComponent("SKILL.md")
                    if fileManager.fileExists(atPath: skillFile.path) {
                        if let skill = await parseSkillFile(at: skillFile, skillName: itemURL.lastPathComponent, scope: scope, projectPath: projectPath) {
                            skills.append(skill)
                        }
                    }
                }
                // Also check for direct .md files (legacy format)
                else if itemURL.pathExtension.lowercased() == "md" {
                    if let skill = await parseSkillFile(at: itemURL, skillName: nil, scope: scope, projectPath: projectPath) {
                        skills.append(skill)
                    }
                }
            }
        } catch {
            logError("Failed to read skills directory: \(error)", category: .data)
        }

        logDebug("Found \(skills.count) skills in \(directory.lastPathComponent)", category: .data)
        return skills.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    private func parseSkillFile(at url: URL, skillName: String?, scope: SkillScope, projectPath: URL?) async -> Skill? {
        do {
            let content = try String(contentsOf: url, encoding: .utf8)

            // Use provided skill name or extract from filename
            let name: String
            if let skillName = skillName {
                name = skillName
                    .replacingOccurrences(of: "-", with: " ")
                    .replacingOccurrences(of: "_", with: " ")
                    .split(separator: " ")
                    .map { $0.capitalized }
                    .joined(separator: " ")
            } else {
                name = url.deletingPathExtension().lastPathComponent
                    .replacingOccurrences(of: "-", with: " ")
                    .replacingOccurrences(of: "_", with: " ")
                    .capitalized
            }

            // Try to extract description from first line if it starts with #
            var description = ""
            let lines = content.components(separatedBy: .newlines)
            if let firstLine = lines.first, firstLine.hasPrefix("#") {
                description = firstLine
                    .trimmingCharacters(in: CharacterSet(charactersIn: "# "))
                    .trimmingCharacters(in: .whitespaces)
            } else if let firstNonEmptyLine = lines.first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                description = String(firstNonEmptyLine.prefix(80))
            }

            // Get the command name from the skill folder or filename
            let commandName = skillName ?? url.deletingPathExtension().lastPathComponent

            return Skill(
                name: name,
                description: description,
                content: content,
                scope: scope,
                filePath: url,
                projectPath: projectPath
            )
        } catch {
            logError("Failed to parse skill file \(url.path): \(error)", category: .data)
            return nil
        }
    }
}

// MARK: - Skill Manager (MainActor)

@MainActor
final class SkillManager: ObservableObject {
    static let shared = SkillManager()

    // MARK: - Published Properties

    @Published private(set) var systemSkills: [Skill] = []
    @Published private(set) var projectSkills: [Skill] = []
    @Published private(set) var isLoading: Bool = false
    @Published var selectedProjectPath: URL?

    // MARK: - Starred/Demoted Skills Storage

    private let starredSkillsKey = "starredSkillPaths"
    private let demotedSkillsKey = "demotedSkillPaths"

    private var starredSkillPaths: Set<String> {
        get {
            Set(UserDefaults.standard.stringArray(forKey: starredSkillsKey) ?? [])
        }
        set {
            UserDefaults.standard.set(Array(newValue), forKey: starredSkillsKey)
        }
    }

    private var demotedSkillPaths: Set<String> {
        get {
            Set(UserDefaults.standard.stringArray(forKey: demotedSkillsKey) ?? [])
        }
        set {
            UserDefaults.standard.set(Array(newValue), forKey: demotedSkillsKey)
        }
    }

    // MARK: - Computed Properties

    var allSkills: [Skill] {
        systemSkills + projectSkills
    }

    var hasSkills: Bool {
        !systemSkills.isEmpty || !projectSkills.isEmpty
    }

    // MARK: - Initialization

    private init() {
    }

    // MARK: - Starring & Demoting

    func isStarred(_ skill: Skill) -> Bool {
        starredSkillPaths.contains(skill.filePath.path)
    }

    func isDemoted(_ skill: Skill) -> Bool {
        demotedSkillPaths.contains(skill.filePath.path)
    }

    func toggleStarred(_ skill: Skill) {
        let path = skill.filePath.path
        if starredSkillPaths.contains(path) {
            starredSkillPaths.remove(path)
        } else {
            starredSkillPaths.insert(path)
            // Remove from demoted if starring
            demotedSkillPaths.remove(path)
        }
        resortSkills()
    }

    func toggleDemoted(_ skill: Skill) {
        let path = skill.filePath.path
        if demotedSkillPaths.contains(path) {
            demotedSkillPaths.remove(path)
        } else {
            demotedSkillPaths.insert(path)
            // Remove from starred if demoting
            starredSkillPaths.remove(path)
        }
        resortSkills()
    }

    private func resortSkills() {
        systemSkills = sortSkillsByPriority(systemSkills)
        projectSkills = sortSkillsByPriority(projectSkills)
        objectWillChange.send()
    }

    private func sortSkillsByPriority(_ skills: [Skill]) -> [Skill] {
        skills.sorted { skill1, skill2 in
            let starred1 = isStarred(skill1)
            let starred2 = isStarred(skill2)
            let demoted1 = isDemoted(skill1)
            let demoted2 = isDemoted(skill2)

            // Starred comes first
            if starred1 != starred2 {
                return starred1
            }
            // Demoted goes last
            if demoted1 != demoted2 {
                return demoted2 // demoted2 true means skill1 should come first
            }
            // Otherwise alphabetical
            return skill1.name.lowercased() < skill2.name.lowercased()
        }
    }

    // MARK: - File Opening

    func openSkillFile(_ skill: Skill) {
        NSWorkspace.shared.open(skill.filePath)
    }

    // MARK: - Loading

    /// Loads all skills
    func loadSkills() async {
        isLoading = true

        // Load system skills
        let system = await SkillDiscoveryService.shared.discoverSystemSkills()
        systemSkills = sortSkillsByPriority(system)

        // Load project skills if a project is selected
        if let projectPath = selectedProjectPath {
            let project = await SkillDiscoveryService.shared.discoverProjectSkills(at: projectPath)
            projectSkills = sortSkillsByPriority(project)
        } else {
            projectSkills = []
        }

        isLoading = false
        logInfo("Loaded \(systemSkills.count) system skills, \(projectSkills.count) project skills", category: .data)
    }

    /// Loads skills for a specific project
    func loadProjectSkills(for projectPath: URL?) async {
        selectedProjectPath = projectPath

        if let path = projectPath {
            let skills = await SkillDiscoveryService.shared.discoverProjectSkills(at: path)
            projectSkills = sortSkillsByPriority(skills)
            logDebug("Loaded \(skills.count) skills for project at \(path.lastPathComponent)", category: .data)
        } else {
            projectSkills = []
        }
    }

    /// Refreshes all skills
    func refresh() async {
        await loadSkills()
    }

    // MARK: - Execution

    /// Runs a skill in an existing terminal window
    /// - Parameters:
    ///   - skill: The skill to run
    ///   - windowId: Optional window ID to target
    ///   - pressEnter: Whether to press enter after typing (false for skills with params)
    func runInExistingTerminal(_ skill: Skill, windowId: String? = nil, pressEnter: Bool = true) async throws {
        logInfo("Running skill '\(skill.name)' (command: \(skill.slashCommand)) in existing terminal (window: \(windowId ?? "active"), pressEnter: \(pressEnter))", category: .execution)

        // For skills, we need to type into the Claude Code interactive prompt
        // Using typeText since Claude Code is an interactive process
        // (do script doesn't work for interactive programs)

        // First activate the specific window if provided
        if let windowId = windowId {
            let script = """
            tell application "Terminal"
                activate
                set frontmost of window id \(windowId) to true
            end tell
            """
            let appleScript = NSAppleScript(source: script)
            var error: NSDictionary?
            appleScript?.executeAndReturnError(&error)
        } else {
            try await TerminalService.shared.activateTerminal()
        }

        // Small delay for window focus
        try await Task.sleep(nanoseconds: 100_000_000)

        // Type the slash command (and optionally press enter)
        try await TerminalService.shared.typeText(skill.slashCommand, pressEnter: pressEnter)
    }

    /// Runs a skill in a new terminal window at the specified project path
    /// - Parameters:
    ///   - skill: The skill to run
    ///   - projectPath: The project directory to open terminal in (overrides skill's project path)
    ///   - pressEnter: Whether to press enter after typing the command (nil = auto-detect based on hasInputParameters)
    func runInNewTerminal(_ skill: Skill, projectPath: URL? = nil, pressEnter: Bool? = nil) async throws {
        // Use provided project path, fall back to skill's project path, then to home directory
        let workingDir = projectPath?.path ?? skill.projectPath?.path ?? FileManager.default.homeDirectoryForCurrentUser.path

        logInfo("Running skill '\(skill.name)' in new terminal at: \(workingDir)", category: .execution)

        // Open new terminal at the project path
        let window = try await TerminalService.shared.openNewWindow(at: workingDir)

        // Wait for terminal to initialize
        try await Task.sleep(nanoseconds: 500_000_000)

        // Start Claude Code
        try await TerminalService.shared.sendPrompt("claude --dangerously-skip-permissions", toWindowId: window.id)

        // Wait for Claude to start up (give it time to initialize)
        try await Task.sleep(nanoseconds: 2_000_000_000)  // 2 seconds

        // Type the slash command
        // Use provided pressEnter value, or fall back to auto-detect based on hasInputParameters
        let shouldPressEnter = pressEnter ?? !skill.hasInputParameters
        try await TerminalService.shared.typeText(skill.slashCommand, pressEnter: shouldPressEnter)

        if shouldPressEnter {
            logInfo("Skill '\(skill.name)' executed", category: .execution)
        } else {
            logInfo("Skill '\(skill.name)' typed - waiting for user input", category: .execution)
        }
    }
}

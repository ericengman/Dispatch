//
//  SessionStatusMonitor.swift
//  Dispatch
//
//  Monitors Claude Code JSONL session files for real-time status updates
//

import Foundation

/// Monitors Claude Code JSONL session files using DispatchSource
/// for real-time status updates including execution state and context usage
@Observable
@MainActor
final class SessionStatusMonitor {
    // MARK: - Published State

    private(set) var status: SessionStatus = .init()

    // MARK: - Private Properties

    private var fileDescriptor: Int32 = -1
    private var dispatchSource: DispatchSourceFileSystemObject?
    private var lastOffset: UInt64 = 0
    private var jsonlPath: String?
    private var retryTask: Task<Void, Never>?

    // MARK: - Public Methods

    /// Start monitoring JSONL file for a Claude Code session
    /// - Parameters:
    ///   - sessionId: The Claude Code session UUID
    ///   - workingDirectory: The project path (e.g., /Users/eric/Dispatch)
    func startMonitoring(sessionId: UUID, workingDirectory: String) {
        logInfo("Starting status monitoring for session: \(sessionId.uuidString)", category: .status)

        // Build JSONL path
        let path = resolveJSONLPath(sessionId: sessionId, workingDirectory: workingDirectory)
        jsonlPath = path

        logDebug("JSONL path: \(path)", category: .status)

        // Start monitoring (may retry if file doesn't exist yet)
        attemptMonitoring(path: path, remainingAttempts: 10)
    }

    /// Stop monitoring and clean up resources
    func stopMonitoring() {
        logInfo("Stopping status monitoring", category: .status)

        retryTask?.cancel()
        retryTask = nil

        dispatchSource?.cancel()
        dispatchSource = nil

        // File descriptor closed by cancel handler
        fileDescriptor = -1
        lastOffset = 0
        jsonlPath = nil
    }

    // MARK: - Private Methods

    private func resolveJSONLPath(sessionId: UUID, workingDirectory: String) -> String {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path

        // Claude Code encodes project path with dashes for slashes
        // Example: /Users/eric/Dispatch -> -Users-eric-Dispatch
        let encodedPath = workingDirectory.replacingOccurrences(of: "/", with: "-")

        return "\(homeDir)/.claude/projects/\(encodedPath)/\(sessionId.uuidString).jsonl"
    }

    private func attemptMonitoring(path: String, remainingAttempts: Int) {
        // Check if file exists
        if FileManager.default.fileExists(atPath: path) {
            logDebug("JSONL file found, starting DispatchSource", category: .status)
            startDispatchSource(path: path)
            return
        }

        // File doesn't exist yet - retry
        guard remainingAttempts > 0 else {
            logWarning("JSONL file not found after retries: \(path)", category: .status)
            return
        }

        logDebug("JSONL file not found, retrying (\(remainingAttempts) attempts left)", category: .status)

        retryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000) // 500ms

            guard !Task.isCancelled else { return }
            self?.attemptMonitoring(path: path, remainingAttempts: remainingAttempts - 1)
        }
    }

    private func startDispatchSource(path: String) {
        // Open file with O_EVTONLY (events only, no read/write)
        fileDescriptor = open(path, O_EVTONLY)
        guard fileDescriptor != -1 else {
            logError("Failed to open JSONL file: \(path)", category: .status)
            return
        }

        // Create DispatchSource for write/extend events
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .extend],
            queue: DispatchQueue.global(qos: .userInitiated)
        )

        source.setEventHandler { [weak self] in
            self?.handleFileUpdate()
        }

        source.setCancelHandler { [weak self] in
            if let fd = self?.fileDescriptor, fd != -1 {
                close(fd)
                logDebug("Closed JSONL file descriptor", category: .status)
            }
        }

        dispatchSource = source
        source.resume()

        logInfo("DispatchSource started for JSONL monitoring", category: .status)

        // Do initial read to catch existing content
        handleFileUpdate()
    }

    private func handleFileUpdate() {
        guard let path = jsonlPath else { return }

        guard let fileHandle = FileHandle(forReadingAtPath: path) else {
            logWarning("Cannot open file handle for reading: \(path)", category: .status)
            return
        }
        defer { try? fileHandle.close() }

        do {
            // Seek to last read position
            try fileHandle.seek(toOffset: lastOffset)

            // Read new data
            let data = fileHandle.readDataToEndOfFile()
            lastOffset = fileHandle.offsetInFile

            guard !data.isEmpty else { return }

            // Parse newline-delimited JSON entries
            if let content = String(data: data, encoding: .utf8) {
                let lines = content.split(separator: "\n", omittingEmptySubsequences: true)
                let entries = lines.compactMap { line -> JSONLEntry? in
                    guard let lineData = String(line).data(using: .utf8) else { return nil }
                    return try? JSONDecoder().decode(JSONLEntry.self, from: lineData)
                }

                if !entries.isEmpty {
                    logDebug("Parsed \(entries.count) JSONL entries", category: .status)
                    Task { @MainActor [weak self] in
                        self?.updateFromEntries(entries)
                    }
                }
            }
        } catch {
            logError("Error reading JSONL file: \(error)", category: .status)
        }
    }

    private func updateFromEntries(_ entries: [JSONLEntry]) {
        for entry in entries {
            // Hook-based detection (most reliable)
            if entry.type == "hook_progress",
               let hookEvent = entry.data?.hookEvent {
                switch hookEvent {
                case "Stop":
                    status.state = .idle
                    status.lastUpdated = Date()
                    logDebug("State -> idle (hook: Stop)", category: .status)
                case "SessionStart":
                    status.state = .idle
                    status.lastUpdated = Date()
                    logDebug("State -> idle (hook: SessionStart)", category: .status)
                default:
                    break
                }
            }

            // Message-based detection (only completed messages with stop_reason)
            if entry.type == "message",
               let message = entry.message,
               message.stop_reason != nil {
                if message.role == "assistant" {
                    // Check if message has tool_use
                    let hasToolUse = message.content?.contains { $0.type == "tool_use" } ?? false
                    status.state = hasToolUse ? .executing : .thinking
                    status.lastUpdated = Date()
                    logDebug("State -> \(status.state.displayName) (assistant message)", category: .status)
                } else if message.role == "user" {
                    // Check if message has tool_result
                    let hasToolResult = message.content?.contains { $0.type == "tool_result" } ?? false
                    status.state = hasToolResult ? .executing : .waiting
                    status.lastUpdated = Date()
                    logDebug("State -> \(status.state.displayName) (user message)", category: .status)
                }

                // Extract token usage
                if let usage = message.usage {
                    status.contextUsage = ContextUsage(
                        inputTokens: usage.input_tokens,
                        outputTokens: usage.output_tokens,
                        cacheTokens: usage.cache_read_input_tokens
                    )
                    logDebug("Context usage: \(usage.input_tokens) in, \(usage.output_tokens) out", category: .status)
                }
            }
        }
    }
}

// MARK: - JSONL Entry Models

/// Represents a single entry in Claude Code's JSONL session log
private struct JSONLEntry: Decodable {
    let type: String // "message", "progress", "hook_progress", "file-history-snapshot"
    let uuid: String?
    let parentUuid: String?
    let sessionId: String?
    let timestamp: String?
    let message: Message?
    let data: ProgressData?

    struct Message: Decodable {
        let role: String // "user", "assistant"
        let content: [Content]?
        let id: String?
        let stop_reason: String? // null while streaming, "end_turn" when done
        let usage: Usage?

        struct Content: Decodable {
            let type: String // "text", "tool_use", "tool_result"
            let text: String?
            let tool_use_id: String?
        }

        struct Usage: Decodable {
            let input_tokens: Int
            let output_tokens: Int
            let cache_creation_input_tokens: Int?
            let cache_read_input_tokens: Int?
        }
    }

    struct ProgressData: Decodable {
        let type: String? // "hook_progress", "agent_progress"
        let hookEvent: String? // "Stop", "SessionStart"
    }
}

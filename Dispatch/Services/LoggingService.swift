//
//  LoggingService.swift
//  Dispatch
//
//  Comprehensive logging service with categories, levels, and formatting
//

import Foundation
import os.log

// MARK: - Log Level

/// Severity levels for log messages
enum LogLevel: Int, Comparable, Sendable {
    case debug = 0      // Detailed debugging information
    case info = 1       // General informational messages
    case warning = 2    // Potential issues that don't prevent operation
    case error = 3      // Errors that affect functionality but app continues
    case critical = 4   // Critical failures that may require immediate attention

    var symbol: String {
        switch self {
        case .debug: return "🔍"
        case .info: return "ℹ️"
        case .warning: return "⚠️"
        case .error: return "❌"
        case .critical: return "🚨"
        }
    }

    var name: String {
        switch self {
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .warning: return "WARN"
        case .error: return "ERROR"
        case .critical: return "CRITICAL"
        }
    }

    var osLogType: OSLogType {
        switch self {
        case .debug: return .debug
        case .info: return .info
        case .warning: return .default
        case .error: return .error
        case .critical: return .fault
        }
    }

    static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Log Category

/// Categories for organizing log messages by subsystem
enum LogCategory: String, CaseIterable, Sendable {
    case app = "APP"                    // App lifecycle, general
    case data = "DATA"                  // SwiftData operations, persistence
    case terminal = "TERMINAL"          // Terminal integration, AppleScript
    case queue = "QUEUE"                // Queue operations
    case chain = "CHAIN"                // Chain execution
    case hooks = "HOOKS"                // Hook server, completion detection
    case hotkey = "HOTKEY"              // Global hotkey
    case placeholder = "PLACEHOLDER"    // Placeholder resolution
    case ui = "UI"                      // View updates, user interactions
    case settings = "SETTINGS"          // Settings changes
    case history = "HISTORY"            // History operations
    case execution = "EXECUTION"        // Execution state machine
    case network = "NETWORK"            // Network operations (hook server)

    var osLog: OSLog {
        OSLog(subsystem: "com.Eric.Dispatch", category: rawValue)
    }
}

// MARK: - Log Entry

/// Represents a single log entry with all metadata
struct LogEntry: Sendable {
    let timestamp: Date
    let level: LogLevel
    let category: LogCategory
    let message: String
    let file: String
    let function: String
    let line: Int
    let threadName: String
    let threadIsMain: Bool

    var formattedTimestamp: String {
        Self.timestampFormatter.string(from: timestamp)
    }

    var formattedMessage: String {
        let threadIndicator = threadIsMain ? "M" : "B"
        let fileName = (file as NSString).lastPathComponent
        return "\(formattedTimestamp) \(level.symbol) [\(level.name)] [\(category.rawValue)] [\(threadIndicator)] \(fileName):\(line) \(function) → \(message)"
    }

    var compactMessage: String {
        "\(level.symbol) [\(category.rawValue)] \(message)"
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()
}

// MARK: - Log Filter

/// Configuration for filtering log output
struct LogFilter: Sendable {
    var minimumLevel: LogLevel = .debug
    var enabledCategories: Set<LogCategory> = Set(LogCategory.allCases)
    var disabledCategories: Set<LogCategory> = []

    func shouldLog(level: LogLevel, category: LogCategory) -> Bool {
        guard level >= minimumLevel else { return false }
        guard enabledCategories.contains(category) else { return false }
        guard !disabledCategories.contains(category) else { return false }
        return true
    }
}

// MARK: - Log Destination Protocol

/// Protocol for log output destinations
protocol LogDestination: Sendable {
    func write(_ entry: LogEntry)
}

// MARK: - Console Destination

/// Outputs logs to the console/standard output
final class ConsoleLogDestination: LogDestination, @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.dispatch.logging.console", qos: .utility)
    private let useOSLog: Bool

    init(useOSLog: Bool = true) {
        self.useOSLog = useOSLog
    }

    func write(_ entry: LogEntry) {
        queue.async {
            if self.useOSLog {
                os_log("%{public}@", log: entry.category.osLog, type: entry.level.osLogType, entry.formattedMessage)
            } else {
                print(entry.formattedMessage)
            }
        }
    }
}

// MARK: - File Destination

/// Outputs logs to a file for persistent storage
final class FileLogDestination: LogDestination, @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.dispatch.logging.file", qos: .utility)
    private let fileURL: URL
    private let fileHandle: FileHandle?
    private let maxFileSize: UInt64

    init?(directory: URL? = nil, fileName: String = "dispatch.log", maxSizeMB: Double = 10) {
        let logDirectory = directory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("com.Eric.Dispatch/Logs", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
        } catch {
            print("Failed to create log directory: \(error)")
            return nil
        }

        self.fileURL = logDirectory.appendingPathComponent(fileName)
        self.maxFileSize = UInt64(maxSizeMB * 1024 * 1024)

        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }

        do {
            self.fileHandle = try FileHandle(forWritingTo: fileURL)
            self.fileHandle?.seekToEndOfFile()
        } catch {
            print("Failed to open log file: \(error)")
            return nil
        }
    }

    func write(_ entry: LogEntry) {
        queue.async { [weak self] in
            guard let self = self, let handle = self.fileHandle else { return }

            let line = entry.formattedMessage + "\n"
            if let data = line.data(using: .utf8) {
                handle.write(data)

                // Check file size and rotate if needed
                let currentSize = handle.offsetInFile
                if currentSize > self.maxFileSize {
                    self.rotateLog()
                }
            }
        }
    }

    private func rotateLog() {
        fileHandle?.closeFile()

        let rotatedURL = fileURL.deletingPathExtension()
            .appendingPathExtension("old.log")

        try? FileManager.default.removeItem(at: rotatedURL)
        try? FileManager.default.moveItem(at: fileURL, to: rotatedURL)

        FileManager.default.createFile(atPath: fileURL.path, contents: nil)
    }

    deinit {
        fileHandle?.closeFile()
    }
}

// MARK: - Logging Service (Actor)

/// Thread-safe logging service using Swift actors
actor LoggingService {
    static let shared = LoggingService()

    private var destinations: [LogDestination] = []
    private var filter = LogFilter()
    private var isEnabled = true
    private var entryBuffer: [LogEntry] = []
    private let maxBufferSize = 1000

    private init() {
        // Default: console logging enabled
        destinations.append(ConsoleLogDestination(useOSLog: true))

        // Add file logging in debug builds
        #if DEBUG
        if let fileDestination = FileLogDestination() {
            destinations.append(fileDestination)
        }
        #endif
    }

    // MARK: - Configuration

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
    }

    func setMinimumLevel(_ level: LogLevel) {
        filter.minimumLevel = level
    }

    func enableCategory(_ category: LogCategory) {
        filter.enabledCategories.insert(category)
        filter.disabledCategories.remove(category)
    }

    func disableCategory(_ category: LogCategory) {
        filter.disabledCategories.insert(category)
    }

    func enableAllCategories() {
        filter.enabledCategories = Set(LogCategory.allCases)
        filter.disabledCategories = []
    }

    func addDestination(_ destination: LogDestination) {
        destinations.append(destination)
    }

    // MARK: - Logging

    func log(
        _ message: String,
        level: LogLevel,
        category: LogCategory,
        file: String,
        function: String,
        line: Int
    ) {
        guard isEnabled else { return }
        guard filter.shouldLog(level: level, category: category) else { return }

        let entry = LogEntry(
            timestamp: Date(),
            level: level,
            category: category,
            message: message,
            file: file,
            function: function,
            line: line,
            threadName: Thread.current.name ?? "unknown",
            threadIsMain: Thread.isMainThread
        )

        // Buffer entry for potential retrieval
        entryBuffer.append(entry)
        if entryBuffer.count > maxBufferSize {
            entryBuffer.removeFirst(entryBuffer.count - maxBufferSize)
        }

        // Write to all destinations
        for destination in destinations {
            destination.write(entry)
        }
    }

    // MARK: - Retrieval

    func getRecentEntries(count: Int = 100, level: LogLevel? = nil, category: LogCategory? = nil) -> [LogEntry] {
        var entries = entryBuffer

        if let level = level {
            entries = entries.filter { $0.level >= level }
        }

        if let category = category {
            entries = entries.filter { $0.category == category }
        }

        return Array(entries.suffix(count))
    }

    func clearBuffer() {
        entryBuffer.removeAll()
    }
}

// MARK: - Global Logging Functions

/// Convenience functions for logging from any context
/// These are the primary interface for logging throughout the app

func logDebug(
    _ message: String,
    category: LogCategory = .app,
    file: String = #file,
    function: String = #function,
    line: Int = #line
) {
    Task {
        await LoggingService.shared.log(message, level: .debug, category: category, file: file, function: function, line: line)
    }
}

func logInfo(
    _ message: String,
    category: LogCategory = .app,
    file: String = #file,
    function: String = #function,
    line: Int = #line
) {
    Task {
        await LoggingService.shared.log(message, level: .info, category: category, file: file, function: function, line: line)
    }
}

func logWarning(
    _ message: String,
    category: LogCategory = .app,
    file: String = #file,
    function: String = #function,
    line: Int = #line
) {
    Task {
        await LoggingService.shared.log(message, level: .warning, category: category, file: file, function: function, line: line)
    }
}

func logError(
    _ message: String,
    category: LogCategory = .app,
    file: String = #file,
    function: String = #function,
    line: Int = #line
) {
    Task {
        await LoggingService.shared.log(message, level: .error, category: category, file: file, function: function, line: line)
    }
}

func logCritical(
    _ message: String,
    category: LogCategory = .app,
    file: String = #file,
    function: String = #function,
    line: Int = #line
) {
    Task {
        await LoggingService.shared.log(message, level: .critical, category: category, file: file, function: function, line: line)
    }
}

// MARK: - Error Logging Extension

extension Error {
    func log(
        as level: LogLevel = .error,
        category: LogCategory = .app,
        context: String = "",
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        let message = context.isEmpty ? "\(self)" : "\(context): \(self)"
        Task {
            await LoggingService.shared.log(message, level: level, category: category, file: file, function: function, line: line)
        }
    }
}

// MARK: - Performance Logging

/// Utility for measuring and logging operation durations
final class PerformanceLogger: @unchecked Sendable {
    private let name: String
    private let category: LogCategory
    private let startTime: CFAbsoluteTime
    private let file: String
    private let function: String
    private let line: Int

    init(
        _ name: String,
        category: LogCategory = .app,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        self.name = name
        self.category = category
        self.startTime = CFAbsoluteTimeGetCurrent()
        self.file = file
        self.function = function
        self.line = line

        Task {
            await LoggingService.shared.log(
                "⏱ START: \(name)",
                level: .debug,
                category: category,
                file: file,
                function: function,
                line: line
            )
        }
    }

    func end() {
        let duration = CFAbsoluteTimeGetCurrent() - startTime
        let formattedDuration = String(format: "%.3f", duration * 1000)

        Task {
            await LoggingService.shared.log(
                "⏱ END: \(name) - \(formattedDuration)ms",
                level: .debug,
                category: category,
                file: file,
                function: function,
                line: line
            )
        }
    }

    func checkpoint(_ label: String) {
        let duration = CFAbsoluteTimeGetCurrent() - startTime
        let formattedDuration = String(format: "%.3f", duration * 1000)

        Task {
            await LoggingService.shared.log(
                "⏱ CHECKPOINT: \(name) - \(label) at \(formattedDuration)ms",
                level: .debug,
                category: category,
                file: file,
                function: function,
                line: line
            )
        }
    }
}

/// Convenience function for scoped performance measurement
func measurePerformance<T>(
    _ name: String,
    category: LogCategory = .app,
    operation: () throws -> T
) rethrows -> T {
    let logger = PerformanceLogger(name, category: category)
    defer { logger.end() }
    return try operation()
}

func measurePerformance<T>(
    _ name: String,
    category: LogCategory = .app,
    operation: () async throws -> T
) async rethrows -> T {
    let logger = PerformanceLogger(name, category: category)
    defer { logger.end() }
    return try await operation()
}

//
//  HookServer.swift
//  Dispatch
//
//  Local HTTP server for receiving Claude Code hook notifications
//

import Combine
import Foundation
import Network

// MARK: - Hook Server Configuration

struct HookServerConfig: Sendable {
    let port: UInt16
    let host: String

    init(port: UInt16 = 19847, host: String = "127.0.0.1") {
        self.port = port
        self.host = host
    }

    var baseURL: String {
        "http://\(host):\(port)"
    }
}

// MARK: - Hook Payload

/// Payload received from Claude Code stop hook
struct HookPayload: Codable, Sendable {
    let session: String?
    let timestamp: String?

    enum CodingKeys: String, CodingKey {
        case session
        case timestamp
    }
}

// MARK: - Screenshot Request/Response Types

/// Request to create a new screenshot run
struct CreateScreenshotRunRequest: Codable, Sendable {
    let project: String
    let name: String
    let device: String?
}

/// Response with new run details
struct CreateScreenshotRunResponse: Codable, Sendable {
    let runId: String
    let path: String
}

/// Request to mark a run as complete
struct CompleteScreenshotRunRequest: Codable, Sendable {
    let runId: String
}

/// Response with screenshot save location
struct ScreenshotLocationResponse: Codable, Sendable {
    let path: String
}

// MARK: - Hook Server State

enum HookServerState: Sendable {
    case stopped
    case starting
    case running
    case error(String)

    var isRunning: Bool {
        if case .running = self { return true }
        return false
    }
}

// MARK: - Hook Server

/// Actor-based HTTP server for receiving Claude Code completion hooks
actor HookServer {
    static let shared = HookServer()

    // MARK: - Properties

    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private var config: HookServerConfig
    private var state: HookServerState = .stopped

    private var completionHandler: ((HookPayload) -> Void)?

    // MARK: - Initialization

    private init() {
        config = HookServerConfig()
    }

    // MARK: - Configuration

    func configure(port: UInt16) {
        guard !state.isRunning else {
            logWarning("Cannot reconfigure while running", category: .hooks)
            return
        }
        config = HookServerConfig(port: port)
        logInfo("HookServer configured with port: \(port)", category: .hooks)
    }

    func getConfig() -> HookServerConfig {
        config
    }

    func getState() -> HookServerState {
        state
    }

    // MARK: - Lifecycle

    /// Starts the hook server
    func start() async throws {
        guard !state.isRunning else {
            logDebug("Server already running", category: .hooks)
            return
        }

        state = .starting
        logInfo("Starting HookServer on port \(config.port)", category: .hooks)

        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true

            listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: config.port)!)

            listener?.stateUpdateHandler = { [weak self] newState in
                Task {
                    await self?.handleListenerStateChange(newState)
                }
            }

            listener?.newConnectionHandler = { [weak self] connection in
                Task {
                    await self?.handleNewConnection(connection)
                }
            }

            listener?.start(queue: .global(qos: .userInitiated))

            // Wait for server to start
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds

            if case let .error(message) = state {
                throw HookServerError.startFailed(message)
            }

        } catch {
            state = .error(error.localizedDescription)
            logError("Failed to start HookServer: \(error)", category: .hooks)
            throw error
        }
    }

    /// Stops the hook server
    func stop() {
        guard state.isRunning else {
            logDebug("Server not running", category: .hooks)
            return
        }

        logInfo("Stopping HookServer", category: .hooks)

        // Close all connections
        for connection in connections {
            connection.cancel()
        }
        connections.removeAll()

        // Stop listener
        listener?.cancel()
        listener = nil

        state = .stopped
        logInfo("HookServer stopped", category: .hooks)
    }

    /// Restarts the server
    func restart() async throws {
        stop()
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        try await start()
    }

    // MARK: - Event Handling

    /// Sets the handler for completion notifications
    func onCompletion(_ handler: @escaping (HookPayload) -> Void) {
        completionHandler = handler
    }

    // MARK: - Private Methods

    private func handleListenerStateChange(_ newState: NWListener.State) {
        switch newState {
        case .ready:
            state = .running
            logInfo("HookServer listening on port \(config.port)", category: .hooks)

        case let .failed(error):
            state = .error(error.localizedDescription)
            // Error will be logged by the start() caller, avoid duplicate logging

        case .cancelled:
            state = .stopped
            logDebug("HookServer cancelled", category: .hooks)

        case .setup:
            logDebug("HookServer setting up", category: .hooks)

        case let .waiting(error):
            logWarning("HookServer waiting: \(error)", category: .hooks)

        @unknown default:
            logWarning("HookServer unknown state", category: .hooks)
        }
    }

    private func handleNewConnection(_ connection: NWConnection) {
        logDebug("New connection received", category: .hooks)

        connections.append(connection)

        connection.stateUpdateHandler = { [weak self] state in
            Task {
                await self?.handleConnectionStateChange(connection, state: state)
            }
        }

        connection.start(queue: .global(qos: .userInitiated))
        receiveData(from: connection)
    }

    private func handleConnectionStateChange(_ connection: NWConnection, state: NWConnection.State) {
        switch state {
        case .ready:
            logDebug("Connection ready", category: .hooks)

        case let .failed(error):
            logError("Connection failed: \(error)", category: .hooks)
            removeConnection(connection)

        case .cancelled:
            logDebug("Connection cancelled", category: .hooks)
            removeConnection(connection)

        default:
            break
        }
    }

    private func removeConnection(_ connection: NWConnection) {
        connections.removeAll { $0 === connection }
    }

    private func receiveData(from connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            Task {
                if let error = error {
                    logError("Receive error: \(error)", category: .hooks)
                    return
                }

                if let data = data, !data.isEmpty {
                    await self?.handleReceivedData(data, from: connection)
                }

                if isComplete {
                    connection.cancel()
                } else {
                    await self?.receiveData(from: connection)
                }
            }
        }
    }

    private func handleReceivedData(_ data: Data, from connection: NWConnection) {
        guard let requestString = String(data: data, encoding: .utf8) else {
            logWarning("Could not decode request data", category: .hooks)
            sendErrorResponse(to: connection, status: 400, message: "Invalid request")
            return
        }

        logDebug("Received request: \(requestString.prefix(200))", category: .hooks)

        // Parse HTTP request
        let lines = requestString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            sendErrorResponse(to: connection, status: 400, message: "Empty request")
            return
        }

        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else {
            sendErrorResponse(to: connection, status: 400, message: "Malformed request line")
            return
        }

        let method = String(parts[0])
        let path = String(parts[1])

        // Parse query parameters if present
        let pathComponents = path.split(separator: "?", maxSplits: 1)
        let basePath = String(pathComponents[0])
        let queryString = pathComponents.count > 1 ? String(pathComponents[1]) : nil

        // Handle routes
        switch (method, basePath) {
        case ("POST", "/hook/complete"):
            handleCompletionHook(requestString, connection: connection)

        case ("GET", "/health"):
            sendSuccessResponse(to: connection, body: "{\"status\":\"ok\"}")

        case ("GET", "/"):
            sendSuccessResponse(to: connection, body: "{\"service\":\"Dispatch Hook Server\",\"version\":\"1.0\"}")

        case ("GET", "/screenshots/location"):
            handleScreenshotLocation(queryString: queryString, connection: connection)

        case ("POST", "/screenshots/run"):
            handleCreateScreenshotRun(requestString, connection: connection)

        case ("POST", "/screenshots/complete"):
            handleCompleteScreenshotRun(requestString, connection: connection)

        default:
            sendErrorResponse(to: connection, status: 404, message: "Not found")
        }
    }

    private func handleCompletionHook(_ request: String, connection: NWConnection) {
        logInfo("Received completion hook", category: .hooks)

        // Extract JSON body
        let parts = request.components(separatedBy: "\r\n\r\n")
        guard parts.count >= 2, let jsonData = parts[1].data(using: .utf8) else {
            logWarning("No JSON body in completion hook", category: .hooks)
            // Still treat as valid completion
            let payload = HookPayload(session: nil, timestamp: nil)
            notifyCompletion(payload)
            sendSuccessResponse(to: connection, body: "{\"received\":true}")
            return
        }

        do {
            let payload = try JSONDecoder().decode(HookPayload.self, from: jsonData)
            logInfo("Completion hook payload - session: \(payload.session ?? "unknown")", category: .hooks)
            notifyCompletion(payload)
            sendSuccessResponse(to: connection, body: "{\"received\":true}")
        } catch {
            logWarning("Failed to parse completion payload: \(error)", category: .hooks)
            // Still treat as valid completion
            let payload = HookPayload(session: nil, timestamp: nil)
            notifyCompletion(payload)
            sendSuccessResponse(to: connection, body: "{\"received\":true}")
        }
    }

    private func notifyCompletion(_ payload: HookPayload) {
        completionHandler?(payload)

        // Also notify the execution state machine
        Task { @MainActor in
            ExecutionStateMachine.shared.handleHookCompletion(sessionId: payload.session)
        }
    }

    // MARK: - Screenshot Endpoints

    private func handleScreenshotLocation(queryString: String?, connection: NWConnection) {
        logInfo("Received screenshot location request", category: .simulator)

        // Parse project name from query string
        var projectName = "default"
        if let query = queryString {
            let params = parseQueryString(query)
            if let name = params["project"], !name.isEmpty {
                projectName = name
            }
        }

        Task {
            let config = await ScreenshotWatcherService.shared.getConfig()
            let projectDir = config.projectDirectory(for: projectName)

            // Ensure directory exists
            do {
                try FileManager.default.createDirectory(
                    at: projectDir,
                    withIntermediateDirectories: true,
                    attributes: nil
                )
            } catch {
                logError("Failed to create screenshot directory: \(error)", category: .simulator)
                self.sendErrorResponse(to: connection, status: 500, message: "Failed to create directory")
                return
            }

            let response = ScreenshotLocationResponse(path: projectDir.path)
            if let jsonData = try? JSONEncoder().encode(response),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                self.sendSuccessResponse(to: connection, body: jsonString)
            } else {
                self.sendErrorResponse(to: connection, status: 500, message: "Failed to encode response")
            }
        }
    }

    private func handleCreateScreenshotRun(_ request: String, connection: NWConnection) {
        logInfo("Received create screenshot run request", category: .simulator)

        // Extract JSON body
        let parts = request.components(separatedBy: "\r\n\r\n")
        guard parts.count >= 2, let jsonData = parts[1].data(using: .utf8) else {
            sendErrorResponse(to: connection, status: 400, message: "Missing request body")
            return
        }

        do {
            let createRequest = try JSONDecoder().decode(CreateScreenshotRunRequest.self, from: jsonData)

            Task { @MainActor in
                if let result = await ScreenshotWatcherManager.shared.createRun(
                    projectName: createRequest.project,
                    runName: createRequest.name,
                    deviceInfo: createRequest.device
                ) {
                    let response = CreateScreenshotRunResponse(
                        runId: result.runId.uuidString,
                        path: result.path
                    )
                    if let jsonData = try? JSONEncoder().encode(response),
                       let jsonString = String(data: jsonData, encoding: .utf8) {
                        await self.sendSuccessResponseAsync(to: connection, body: jsonString)
                    } else {
                        await self.sendErrorResponseAsync(to: connection, status: 500, message: "Failed to encode response")
                    }
                } else {
                    await self.sendErrorResponseAsync(to: connection, status: 500, message: "Failed to create run")
                }
            }
        } catch {
            logError("Failed to parse create run request: \(error)", category: .simulator)
            sendErrorResponse(to: connection, status: 400, message: "Invalid request body")
        }
    }

    private func handleCompleteScreenshotRun(_ request: String, connection: NWConnection) {
        logInfo("Received complete screenshot run request", category: .simulator)

        // Extract JSON body
        let parts = request.components(separatedBy: "\r\n\r\n")
        guard parts.count >= 2, let jsonData = parts[1].data(using: .utf8) else {
            sendErrorResponse(to: connection, status: 400, message: "Missing request body")
            return
        }

        do {
            let completeRequest = try JSONDecoder().decode(CompleteScreenshotRunRequest.self, from: jsonData)

            // Trigger a scan to pick up any new screenshots
            Task {
                await ScreenshotWatcherService.shared.scanForNewRuns()
            }

            logInfo("Marked run \(completeRequest.runId) as complete", category: .simulator)
            sendSuccessResponse(to: connection, body: "{\"completed\":true}")

        } catch {
            logError("Failed to parse complete run request: \(error)", category: .simulator)
            sendErrorResponse(to: connection, status: 400, message: "Invalid request body")
        }
    }

    private func parseQueryString(_ query: String) -> [String: String] {
        var params: [String: String] = [:]
        let pairs = query.split(separator: "&")
        for pair in pairs {
            let keyValue = pair.split(separator: "=", maxSplits: 1)
            if keyValue.count == 2 {
                let key = String(keyValue[0]).removingPercentEncoding ?? String(keyValue[0])
                let value = String(keyValue[1]).removingPercentEncoding ?? String(keyValue[1])
                params[key] = value
            }
        }
        return params
    }

    // Async wrappers for sending responses from MainActor context
    private func sendSuccessResponseAsync(to connection: NWConnection, body: String) async {
        sendSuccessResponse(to: connection, body: body)
    }

    private func sendErrorResponseAsync(to connection: NWConnection, status: Int, message: String) async {
        sendErrorResponse(to: connection, status: status, message: message)
    }

    // MARK: - Response Helpers

    private func sendSuccessResponse(to connection: NWConnection, body: String) {
        let response = """
        HTTP/1.1 200 OK\r
        Content-Type: application/json\r
        Content-Length: \(body.utf8.count)\r
        Connection: close\r
        \r
        \(body)
        """

        sendResponse(response, to: connection)
    }

    private func sendErrorResponse(to connection: NWConnection, status: Int, message: String) {
        let body = "{\"error\":\"\(message)\"}"
        let statusText = status == 404 ? "Not Found" : "Bad Request"

        let response = """
        HTTP/1.1 \(status) \(statusText)\r
        Content-Type: application/json\r
        Content-Length: \(body.utf8.count)\r
        Connection: close\r
        \r
        \(body)
        """

        sendResponse(response, to: connection)
    }

    private func sendResponse(_ response: String, to connection: NWConnection) {
        guard let data = response.data(using: .utf8) else { return }

        connection.send(content: data, completion: .contentProcessed { error in
            if let error = error {
                logError("Send error: \(error)", category: .hooks)
            }
            connection.cancel()
        })
    }
}

// MARK: - Hook Server Errors

enum HookServerError: Error, LocalizedError {
    case startFailed(String)
    case portInUse
    case invalidPort

    var errorDescription: String? {
        switch self {
        case let .startFailed(message):
            return "Failed to start hook server: \(message)"
        case .portInUse:
            return "Port is already in use"
        case .invalidPort:
            return "Invalid port number"
        }
    }
}

// MARK: - Hook Server Manager (MainActor)

/// MainActor wrapper for UI integration
@MainActor
final class HookServerManager: ObservableObject {
    static let shared = HookServerManager()

    @Published private(set) var isRunning: Bool = false
    @Published private(set) var lastError: String?
    @Published private(set) var port: UInt16 = 19847

    private init() {}

    func start(port: UInt16? = nil) async {
        if let port = port {
            self.port = port
            await HookServer.shared.configure(port: port)
        }

        do {
            try await HookServer.shared.start()
            isRunning = true
            lastError = nil
        } catch {
            isRunning = false
            lastError = error.localizedDescription
            // Error already logged by HookServer.start()
        }
    }

    func stop() async {
        await HookServer.shared.stop()
        isRunning = false
        logInfo("Hook server stopped", category: .hooks)
    }

    func restart() async {
        do {
            try await HookServer.shared.restart()
            isRunning = true
            lastError = nil
        } catch {
            isRunning = false
            lastError = error.localizedDescription
        }
    }

    func testConnection() async -> Bool {
        guard isRunning else { return false }

        let config = await HookServer.shared.getConfig()
        let url = URL(string: "\(config.baseURL)/health")!

        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            if let httpResponse = response as? HTTPURLResponse {
                return httpResponse.statusCode == 200
            }
            return false
        } catch {
            logWarning("Hook server test failed: \(error)", category: .hooks)
            return false
        }
    }
}

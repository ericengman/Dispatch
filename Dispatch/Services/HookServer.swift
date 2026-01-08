//
//  HookServer.swift
//  Dispatch
//
//  Local HTTP server for receiving Claude Code hook notifications
//

import Foundation
import Network
import Combine

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
        self.config = HookServerConfig()
        logDebug("HookServer initialized with default config", category: .hooks)
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
            try await Task.sleep(nanoseconds: 100_000_000)  // 0.1 seconds

            if case .error(let message) = state {
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
        try await Task.sleep(nanoseconds: 500_000_000)  // 0.5 seconds
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

        case .failed(let error):
            state = .error(error.localizedDescription)
            logError("HookServer failed: \(error)", category: .hooks)

        case .cancelled:
            state = .stopped
            logDebug("HookServer cancelled", category: .hooks)

        case .setup:
            logDebug("HookServer setting up", category: .hooks)

        case .waiting(let error):
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

        case .failed(let error):
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

        // Handle routes
        switch (method, path) {
        case ("POST", "/hook/complete"):
            handleCompletionHook(requestString, connection: connection)

        case ("GET", "/health"):
            sendSuccessResponse(to: connection, body: "{\"status\":\"ok\"}")

        case ("GET", "/"):
            sendSuccessResponse(to: connection, body: "{\"service\":\"Dispatch Hook Server\",\"version\":\"1.0\"}")

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
        case .startFailed(let message):
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

    private init() {
        logDebug("HookServerManager initialized", category: .hooks)
    }

    func start(port: UInt16? = nil) async {
        if let port = port {
            self.port = port
            await HookServer.shared.configure(port: port)
        }

        do {
            try await HookServer.shared.start()
            isRunning = true
            lastError = nil
            logInfo("Hook server started on port \(self.port)", category: .hooks)
        } catch {
            isRunning = false
            lastError = error.localizedDescription
            logError("Failed to start hook server: \(error)", category: .hooks)
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

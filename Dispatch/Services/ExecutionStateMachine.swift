//
//  ExecutionStateMachine.swift
//  Dispatch
//
//  State machine for managing prompt execution lifecycle
//

import Foundation
import Combine

// MARK: - Execution State

/// Represents the current state of prompt execution
enum ExecutionState: String, Sendable {
    case idle           // No active execution
    case sending        // Prompt being sent to terminal
    case executing      // Waiting for completion signal
    case completed      // Ready for next action

    var description: String {
        switch self {
        case .idle: return "Idle"
        case .sending: return "Sending..."
        case .executing: return "Executing..."
        case .completed: return "Completed"
        }
    }

    var isActive: Bool {
        self == .sending || self == .executing
    }
}

// MARK: - Execution Context

/// Context information for the current execution
struct ExecutionContext: Sendable {
    let promptContent: String
    let promptTitle: String
    let targetWindowId: String?
    let targetWindowName: String?
    let isFromChain: Bool
    let chainName: String?
    let chainStepIndex: Int?
    let chainTotalSteps: Int?
    let startTime: Date

    init(
        promptContent: String,
        promptTitle: String,
        targetWindowId: String? = nil,
        targetWindowName: String? = nil,
        isFromChain: Bool = false,
        chainName: String? = nil,
        chainStepIndex: Int? = nil,
        chainTotalSteps: Int? = nil
    ) {
        self.promptContent = promptContent
        self.promptTitle = promptTitle
        self.targetWindowId = targetWindowId
        self.targetWindowName = targetWindowName
        self.isFromChain = isFromChain
        self.chainName = chainName
        self.chainStepIndex = chainStepIndex
        self.chainTotalSteps = chainTotalSteps
        self.startTime = Date()
    }

    var elapsedTime: TimeInterval {
        Date().timeIntervalSince(startTime)
    }
}

// MARK: - Execution Result

/// Result of an execution attempt
enum ExecutionResult: Sendable {
    case success
    case failure(Error)
    case cancelled

    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}

// MARK: - State Change Event

/// Event representing a state transition
struct StateChangeEvent: Sendable {
    let previousState: ExecutionState
    let newState: ExecutionState
    let context: ExecutionContext?
    let result: ExecutionResult?
    let timestamp: Date

    init(
        from previousState: ExecutionState,
        to newState: ExecutionState,
        context: ExecutionContext? = nil,
        result: ExecutionResult? = nil
    ) {
        self.previousState = previousState
        self.newState = newState
        self.context = context
        self.result = result
        self.timestamp = Date()
    }
}

// MARK: - Execution State Machine

/// Thread-safe state machine for managing execution lifecycle
@MainActor
final class ExecutionStateMachine: ObservableObject {
    // MARK: - Published State

    @Published private(set) var state: ExecutionState = .idle
    @Published private(set) var context: ExecutionContext?
    @Published private(set) var lastResult: ExecutionResult?
    @Published private(set) var isPaused: Bool = false

    // MARK: - Properties

    private var pollingTask: Task<Void, Never>?
    private var completionTimeout: Task<Void, Never>?
    private var stateChangeHandler: ((StateChangeEvent) -> Void)?
    private var completionHandler: ((ExecutionResult) -> Void)?

    private let completionTimeoutSeconds: TimeInterval = 300  // 5 minute timeout

    // MARK: - Singleton

    static let shared = ExecutionStateMachine()

    private init() {
    }

    // MARK: - State Transitions

    /// Transitions to sending state when starting to send a prompt
    func beginSending(context: ExecutionContext) {
        guard state == .idle else {
            logWarning("Cannot begin sending from state: \(state)", category: .execution)
            return
        }

        let previousState = state
        self.context = context
        state = .sending

        logInfo("State: \(previousState) → \(state) | Prompt: '\(context.promptTitle)'", category: .execution)
        notifyStateChange(from: previousState, to: state)
    }

    /// Transitions to executing state after prompt is sent
    func beginExecuting() {
        guard state == .sending else {
            logWarning("Cannot begin executing from state: \(state)", category: .execution)
            return
        }

        let previousState = state
        state = .executing

        logInfo("State: \(previousState) → \(state)", category: .execution)
        notifyStateChange(from: previousState, to: state)

        // Start completion timeout
        startCompletionTimeout()
    }

    /// Marks execution as completed
    func markCompleted(result: ExecutionResult = .success) {
        guard state == .executing || state == .sending else {
            logWarning("Cannot mark completed from state: \(state)", category: .execution)
            return
        }

        let previousState = state
        lastResult = result
        state = .completed

        // Cancel any pending tasks
        pollingTask?.cancel()
        completionTimeout?.cancel()

        let resultDescription: String
        switch result {
        case .success:
            resultDescription = "success"
        case .failure(let error):
            resultDescription = "failure: \(error.localizedDescription)"
        case .cancelled:
            resultDescription = "cancelled"
        }

        logInfo("State: \(previousState) → \(state) | Result: \(resultDescription)", category: .execution)
        notifyStateChange(from: previousState, to: state, result: result)

        // Notify completion handler
        completionHandler?(result)

        // Auto-transition to idle after brief delay
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000)  // 0.5 seconds
            await MainActor.run {
                self.transitionToIdle()
            }
        }
    }

    /// Transitions back to idle state
    func transitionToIdle() {
        guard state == .completed || state == .idle else {
            logDebug("Not transitioning to idle from state: \(state)", category: .execution)
            return
        }

        let previousState = state

        if previousState != .idle {
            context = nil
            isPaused = false
            state = .idle

            logDebug("State: \(previousState) → \(state)", category: .execution)
            notifyStateChange(from: previousState, to: state)
        }
    }

    /// Cancels the current execution
    func cancel() {
        guard state.isActive else {
            logDebug("Nothing to cancel in state: \(state)", category: .execution)
            return
        }

        logInfo("Cancelling execution", category: .execution)
        markCompleted(result: .cancelled)
    }

    /// Pauses chain execution after current prompt completes
    func pause() {
        guard state.isActive && context?.isFromChain == true else {
            logDebug("Cannot pause: not in chain execution", category: .execution)
            return
        }

        isPaused = true
        logInfo("Chain execution paused", category: .execution)
    }

    /// Resumes paused chain execution
    func resume() {
        guard isPaused else { return }

        isPaused = false
        logInfo("Chain execution resumed", category: .execution)
    }

    /// Resets to idle state (for error recovery)
    func reset() {
        pollingTask?.cancel()
        completionTimeout?.cancel()

        let previousState = state
        context = nil
        lastResult = nil
        isPaused = false
        state = .idle

        logWarning("State machine reset from: \(previousState)", category: .execution)
        notifyStateChange(from: previousState, to: .idle)
    }

    // MARK: - Event Handlers

    /// Sets a handler to be called on state changes
    func onStateChange(_ handler: @escaping (StateChangeEvent) -> Void) {
        stateChangeHandler = handler
    }

    /// Sets a handler to be called when execution completes
    func onCompletion(_ handler: @escaping (ExecutionResult) -> Void) {
        completionHandler = handler
    }

    // MARK: - Polling Support

    /// Starts polling for completion (fallback when hooks not available)
    func startPolling(windowId: String?, interval: TimeInterval = 2.0) {
        guard state == .executing else {
            logWarning("Cannot start polling from state: \(state)", category: .execution)
            return
        }

        logInfo("Starting completion polling (interval: \(interval)s)", category: .execution)

        pollingTask?.cancel()
        pollingTask = Task {
            while !Task.isCancelled && state == .executing {
                do {
                    try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))

                    guard !Task.isCancelled else { break }

                    let isPromptVisible = try await TerminalService.shared.isClaudeCodePromptVisible(windowId: windowId)

                    if isPromptVisible {
                        logInfo("Completion detected via polling", category: .execution)
                        await MainActor.run {
                            self.markCompleted(result: .success)
                        }
                        break
                    }
                } catch {
                    logError("Polling error: \(error)", category: .execution)
                    // Continue polling despite errors
                }
            }
        }
    }

    /// Stops polling
    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
        logDebug("Polling stopped", category: .execution)
    }

    // MARK: - Hook Notification

    /// Called when a completion hook is received
    func handleHookCompletion(sessionId: String?) {
        guard state == .executing else {
            logDebug("Ignoring hook completion in state: \(state)", category: .execution)
            return
        }

        logInfo("Completion detected via hook (session: \(sessionId ?? "unknown"))", category: .execution)
        markCompleted(result: .success)
    }

    // MARK: - Private Methods

    private func notifyStateChange(from previousState: ExecutionState, to newState: ExecutionState, result: ExecutionResult? = nil) {
        let event = StateChangeEvent(
            from: previousState,
            to: newState,
            context: context,
            result: result
        )
        stateChangeHandler?(event)
    }

    private func startCompletionTimeout() {
        completionTimeout?.cancel()
        completionTimeout = Task {
            do {
                try await Task.sleep(nanoseconds: UInt64(completionTimeoutSeconds * 1_000_000_000))

                guard !Task.isCancelled else { return }

                await MainActor.run {
                    if self.state == .executing {
                        logWarning("Execution timed out after \(self.completionTimeoutSeconds)s", category: .execution)
                        self.markCompleted(result: .failure(TerminalServiceError.timeout))
                    }
                }
            } catch {
                // Task was cancelled, which is fine
            }
        }
    }
}

// MARK: - Execution Manager

/// High-level manager for executing prompts, integrating queue and chain logic
@MainActor
final class ExecutionManager: ObservableObject {
    static let shared = ExecutionManager()

    @Published private(set) var isExecuting: Bool = false

    private let stateMachine = ExecutionStateMachine.shared
    private let terminalService = TerminalService.shared

    private init() {
        // Observe state machine
        stateMachine.onStateChange { [weak self] event in
            Task { @MainActor in
                self?.isExecuting = event.newState.isActive
            }
        }

    }

    // MARK: - Execute Prompt

    /// Executes a prompt, handling all the orchestration
    func execute(
        content: String,
        title: String = "Prompt",
        targetWindowId: String? = nil,
        targetWindowName: String? = nil,
        isFromChain: Bool = false,
        chainName: String? = nil,
        chainStepIndex: Int? = nil,
        chainTotalSteps: Int? = nil,
        useHooks: Bool = true,
        sendDelay: TimeInterval = 0.1
    ) async throws {
        guard !content.isEmpty else {
            throw TerminalServiceError.invalidPromptContent
        }

        guard stateMachine.state == .idle else {
            logWarning("Cannot execute: state machine not idle", category: .execution)
            throw ExecutionError.alreadyExecuting
        }

        let context = ExecutionContext(
            promptContent: content,
            promptTitle: title,
            targetWindowId: targetWindowId,
            targetWindowName: targetWindowName,
            isFromChain: isFromChain,
            chainName: chainName,
            chainStepIndex: chainStepIndex,
            chainTotalSteps: chainTotalSteps
        )

        logInfo("Executing prompt: '\(title)'", category: .execution)

        // Begin sending
        stateMachine.beginSending(context: context)

        do {
            // Ensure Terminal is running
            let isRunning = await terminalService.isTerminalRunning()
            if !isRunning {
                try await terminalService.launchTerminal()
            }

            // Send the prompt
            try await terminalService.sendPrompt(
                content,
                toWindowId: targetWindowId,
                delay: sendDelay
            )

            // Transition to executing
            stateMachine.beginExecuting()

            // Start completion detection
            if useHooks {
                // Hook server will call handleHookCompletion when done
                // Also start polling as fallback
                stateMachine.startPolling(windowId: targetWindowId, interval: 2.0)
            } else {
                // Only use polling
                stateMachine.startPolling(windowId: targetWindowId, interval: 2.0)
            }

        } catch {
            logError("Execution failed: \(error)", category: .execution)
            stateMachine.markCompleted(result: .failure(error))
            throw error
        }
    }

    /// Cancels the current execution
    func cancel() {
        stateMachine.cancel()
    }

    /// Pauses chain execution
    func pause() {
        stateMachine.pause()
    }

    /// Resumes chain execution
    func resume() {
        stateMachine.resume()
    }
}

// MARK: - Execution Errors

enum ExecutionError: Error, LocalizedError {
    case alreadyExecuting
    case queueEmpty
    case chainEmpty
    case chainItemInvalid

    var errorDescription: String? {
        switch self {
        case .alreadyExecuting:
            return "An execution is already in progress"
        case .queueEmpty:
            return "The queue is empty"
        case .chainEmpty:
            return "The chain has no items"
        case .chainItemInvalid:
            return "Chain item has no valid content"
        }
    }
}

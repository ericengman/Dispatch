//
//  DispatchApp.swift
//  Dispatch
//
//  Main application entry point
//

import SwiftData
import SwiftUI

@main
struct DispatchApp: App {
    // MARK: - Model Container

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Prompt.self,
            Project.self,
            PromptHistory.self,
            PromptChain.self,
            ChainItem.self,
            AppSettings.self,
            SimulatorRun.self,
            Screenshot.self,
            TerminalSession.self
        ])

        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true
        )

        do {
            let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
            logInfo("ModelContainer created successfully", category: .app)
            return container
        } catch {
            logCritical("Could not create ModelContainer: \(error)", category: .app)
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    // MARK: - App Delegate

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    // MARK: - State

    @StateObject private var hotkeyManager = HotkeyManager.shared
    @StateObject private var hookServerManager = HookServerManager.shared
    @StateObject private var screenshotWatcherManager = ScreenshotWatcherManager.shared

    // MARK: - Body

    var body: some Scene {
        // Main Window
        WindowGroup {
            MainView()
                .frame(minWidth: 800, minHeight: 600)
                .onAppear {
                    setupApp()
                }
        }
        .defaultSize(width: 1200, height: 800)
        .modelContainer(sharedModelContainer)
        .commands {
            appCommands
        }

        // Settings Window
        Settings {
            SettingsView()
        }

        // QuickCapture annotation window
        WindowGroup("Annotate Screenshot", for: QuickCapture.self) { $capture in
            if let capture = capture {
                QuickCaptureAnnotationView(capture: capture)
                    .frame(minWidth: 1000, minHeight: 700)
            }
        }
        .defaultSize(width: 1200, height: 800)

        // Menu Bar Extra (if enabled)
        // Note: This will be conditionally shown based on settings
    }

    // MARK: - Commands

    @CommandsBuilder
    private var appCommands: some Commands {
        // File Menu
        CommandGroup(replacing: .newItem) {
            Button("New Prompt") {
                NotificationCenter.default.post(name: .createNewPrompt, object: nil)
            }
            .keyboardShortcut("n", modifiers: .command)

            Button("New Chain") {
                NotificationCenter.default.post(name: .createNewChain, object: nil)
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Divider()

            Button("New Terminal Session") {
                NotificationCenter.default.post(name: .createNewTerminalSession, object: nil)
            }
            .keyboardShortcut("t", modifiers: .command)
        }

        // View Menu
        CommandGroup(after: .sidebar) {
            Divider()

            Button("Show All Prompts") {
                NotificationCenter.default.post(name: .showAllPrompts, object: nil)
            }
            .keyboardShortcut("1", modifiers: .command)

            Button("Show Starred") {
                NotificationCenter.default.post(name: .showStarred, object: nil)
            }
            .keyboardShortcut("2", modifiers: .command)

            Button("Show History") {
                NotificationCenter.default.post(name: .showHistory, object: nil)
            }
            .keyboardShortcut("3", modifiers: .command)
        }

        // Prompt Menu
        CommandMenu("Prompt") {
            Button("Send Selected") {
                NotificationCenter.default.post(name: .sendSelectedPrompt, object: nil)
            }
            .keyboardShortcut(.return, modifiers: .command)

            Divider()

            Button("Toggle Star") {
                NotificationCenter.default.post(name: .toggleStar, object: nil)
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
        }

        // Capture Menu (temporary for Phase 23-24)
        CommandMenu("Capture") {
            Button("Capture Region") {
                Task {
                    let result = await ScreenshotCaptureService.shared.captureRegion()
                    CaptureCoordinator.shared.handleCaptureResult(result)
                }
            }
            .keyboardShortcut("6", modifiers: [.command, .shift])

            Button("Capture Window") {
                Task {
                    let result = await ScreenshotCaptureService.shared.captureWindow()
                    CaptureCoordinator.shared.handleCaptureResult(result)
                }
            }
            .keyboardShortcut("7", modifiers: [.command, .shift])
        }
    }

    // MARK: - Setup

    private func setupApp() {
        logInfo("Dispatch app starting", category: .app)

        // Clean up orphaned terminal processes from previous session
        TerminalProcessRegistry.shared.cleanupOrphanedProcesses()

        // Configure settings manager
        SettingsManager.shared.configure(with: sharedModelContainer.mainContext)

        // Configure terminal session manager and restore persisted sessions
        TerminalSessionManager.shared.configure(modelContext: sharedModelContainer.mainContext)
        TerminalSessionManager.shared.restoreAllPersistedSessions()

        // Configure screenshot watcher
        screenshotWatcherManager.configure(with: sharedModelContainer.mainContext)

        // Start hook server
        Task {
            await hookServerManager.start()
        }

        // Start screenshot watcher
        Task {
            await screenshotWatcherManager.start()
        }

        // Run screenshot cleanup for all projects on launch
        Task {
            await runScreenshotCleanup()
        }

        // Register global hotkey
        hotkeyManager.registerFromSettings()

        // Register capture hotkeys
        hotkeyManager.registerCaptureHotkeys()

        // Install/update external files and refresh hook status
        Task {
            logInfo("Installing/updating external files...", category: .hooks)

            // Install library if needed (non-blocking)
            await HookInstallerManager.shared.installLibraryIfNeeded()

            // Install session start hook if needed (non-blocking)
            await HookInstallerManager.shared.installSessionStartHookIfNeeded()

            // Refresh hook status (existing)
            await HookInstallerManager.shared.refreshStatus()
        }

        logInfo("Dispatch app setup complete", category: .app)
    }

    /// Cleans up old screenshot runs for all projects
    private func runScreenshotCleanup() async {
        logInfo("Running screenshot cleanup on launch", category: .simulator)

        let context = sharedModelContainer.mainContext

        // Get all unique project names with runs
        let descriptor = FetchDescriptor<SimulatorRun>()

        do {
            let runs = try context.fetch(descriptor)
            let projectNames = Set(runs.compactMap { $0.project?.name })

            for projectName in projectNames {
                await ScreenshotWatcherService.shared.cleanupOldRuns(
                    for: projectName,
                    context: context
                )
            }

            logInfo("Screenshot cleanup complete for \(projectNames.count) projects", category: .simulator)
        } catch {
            error.log(category: .simulator, context: "Failed to run screenshot cleanup")
        }
    }
}

// MARK: - App Delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var closeTabMonitor: Any?
    private var cycleSessionMonitor: Any?

    func applicationDidFinishLaunching(_: Notification) {
        logInfo("Application did finish launching", category: .app)

        // Clear stale manual frame autosave that conflicts with SwiftUI's built-in
        // window frame persistence. SwiftUI's WindowGroup handles save/restore automatically.
        UserDefaults.standard.removeObject(forKey: "NSWindow Frame DispatchMainWindow")

        // Intercept Cmd+] (forward) / Cmd+[ (backward) to cycle terminal sessions
        cycleSessionMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard modifiers == .command,
                  let chars = event.charactersIgnoringModifiers
            else { return event }

            let forward: Bool
            if chars == "]" {
                forward = true
            } else if chars == "[" {
                forward = false
            } else {
                return event
            }

            MainActor.assumeIsolated {
                TerminalSessionManager.shared.cycleActiveSession(forward: forward)
            }
            return nil // Consume the event
        }

        // Intercept Cmd+W to close terminal sessions before closing the window
        closeTabMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Only match Cmd+W with no other modifiers (Shift, Option, Control)
            guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
                  event.charactersIgnoringModifiers == "w"
            else {
                return event
            }

            let manager = MainActor.assumeIsolated { TerminalSessionManager.shared }
            let activeId = MainActor.assumeIsolated { manager.activeSessionId }
            let hasSessions = MainActor.assumeIsolated { !manager.sessions.isEmpty }

            guard hasSessions, let sessionId = activeId else {
                return event // No sessions — let standard Cmd+W close the window
            }

            MainActor.assumeIsolated {
                logInfo("Cmd+W closing active terminal session", category: .terminal)
                manager.closeSession(sessionId)
            }
            return nil // Consume the event — window stays open
        }
    }

    func applicationWillTerminate(_: Notification) {
        logInfo("Application will terminate", category: .app)

        // Remove event monitors
        if let monitor = closeTabMonitor {
            NSEvent.removeMonitor(monitor)
            closeTabMonitor = nil
        }
        if let monitor = cycleSessionMonitor {
            NSEvent.removeMonitor(monitor)
            cycleSessionMonitor = nil
        }

        // Save all terminal sessions before anything else - ensures session data persists
        TerminalSessionManager.shared.saveAllSessions()

        // Stop hook server
        Task {
            await HookServerManager.shared.stop()
        }

        // Unregister all hotkeys
        HotkeyManager.shared.unregisterAll()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        // Keep running if menu bar mode is enabled
        return !(SettingsManager.shared.settings?.showInMenuBar ?? false)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            // Reopen main window
            for window in sender.windows {
                window.makeKeyAndOrderFront(self)
            }
        }
        return true
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let createNewPrompt = Notification.Name("createNewPrompt")
    static let createNewChain = Notification.Name("createNewChain")
    static let showAllPrompts = Notification.Name("showAllPrompts")
    static let showStarred = Notification.Name("showStarred")
    static let showHistory = Notification.Name("showHistory")
    static let sendSelectedPrompt = Notification.Name("sendSelectedPrompt")
    static let toggleStar = Notification.Name("toggleStar")
    static let createNewTerminalSession = Notification.Name("createNewTerminalSession")
}

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
            QueueItem.self,
            AppSettings.self,
            SimulatorRun.self,
            Screenshot.self
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
        .modelContainer(sharedModelContainer)
        .commands {
            appCommands
        }

        // Settings Window
        Settings {
            SettingsView()
        }

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

        // Queue Menu
        CommandMenu("Queue") {
            Button("Add Selected to Queue") {
                NotificationCenter.default.post(name: .addToQueue, object: nil)
            }
            .keyboardShortcut("q", modifiers: [.command, .shift])

            Divider()

            Button("Run Next") {
                Task {
                    await QueueViewModel.shared.runNext()
                }
            }
            .keyboardShortcut("r", modifiers: .command)

            Button("Run All") {
                Task {
                    await QueueViewModel.shared.runAll()
                }
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])

            Divider()

            Button("Clear Queue") {
                QueueViewModel.shared.clearQueue()
            }
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
    }

    // MARK: - Setup

    private func setupApp() {
        logInfo("Dispatch app starting", category: .app)

        // Configure settings manager
        SettingsManager.shared.configure(with: sharedModelContainer.mainContext)

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
    func applicationDidFinishLaunching(_: Notification) {
        logInfo("Application did finish launching", category: .app)
    }

    func applicationWillTerminate(_: Notification) {
        logInfo("Application will terminate", category: .app)

        // Stop hook server
        Task {
            await HookServerManager.shared.stop()
        }

        // Unregister hotkey
        HotkeyManager.shared.unregister()

        // Clear queue if configured
        if SettingsManager.shared.settings?.autoClearQueueOnQuit == true {
            QueueViewModel.shared.clearQueue()
        }
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
    static let addToQueue = Notification.Name("addToQueue")
    static let sendSelectedPrompt = Notification.Name("sendSelectedPrompt")
    static let toggleStar = Notification.Name("toggleStar")
}

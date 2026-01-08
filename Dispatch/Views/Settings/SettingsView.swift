//
//  SettingsView.swift
//  Dispatch
//
//  Main settings view with tabbed navigation
//

import SwiftUI
import SwiftData

struct SettingsView: View {
    // MARK: - State

    @State private var selectedTab: SettingsTab = .general

    // MARK: - Body

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }
                .tag(SettingsTab.general)

            HotkeySettingsView()
                .tabItem {
                    Label("Hotkey", systemImage: "keyboard")
                }
                .tag(SettingsTab.hotkey)

            TerminalSettingsView()
                .tabItem {
                    Label("Terminal", systemImage: "terminal")
                }
                .tag(SettingsTab.terminal)

            HookSettingsView()
                .tabItem {
                    Label("Hooks", systemImage: "link")
                }
                .tag(SettingsTab.hooks)

            ProjectDiscoverySettingsView()
                .tabItem {
                    Label("Projects", systemImage: "folder.badge.gearshape")
                }
                .tag(SettingsTab.projects)
        }
        .frame(width: 550, height: 450)
    }
}

// MARK: - Settings Tab

enum SettingsTab: String {
    case general
    case hotkey
    case terminal
    case hooks
    case projects
}

// MARK: - General Settings

struct GeneralSettingsView: View {
    @ObservedObject private var settingsManager = SettingsManager.shared

    var body: some View {
        Form {
            Section("Appearance") {
                Toggle("Launch at login", isOn: launchAtLoginBinding)
                Toggle("Show in menu bar", isOn: showInMenuBarBinding)
                Toggle("Show dock icon", isOn: showDockIconBinding)
                Toggle("Compact row height", isOn: compactRowHeightBinding)

                Picker("Editor font size", selection: editorFontSizeBinding) {
                    ForEach(12...18, id: \.self) { size in
                        Text("\(size) pt").tag(size)
                    }
                }
            }

            Section("Data") {
                Picker("History retention", selection: historyRetentionBinding) {
                    Text("7 days").tag(7)
                    Text("14 days").tag(14)
                    Text("30 days").tag(30)
                    Text("90 days").tag(90)
                    Text("1 year").tag(365)
                }

                Toggle("Clear queue on quit", isOn: autoClearQueueBinding)
            }

            Section {
                Button("Reset to Defaults") {
                    settingsManager.settings?.resetToDefaults()
                    settingsManager.save()
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - Bindings

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { settingsManager.settings?.launchAtLogin ?? false },
            set: {
                settingsManager.settings?.launchAtLogin = $0
                settingsManager.save()
            }
        )
    }

    private var showInMenuBarBinding: Binding<Bool> {
        Binding(
            get: { settingsManager.settings?.showInMenuBar ?? false },
            set: {
                settingsManager.settings?.showInMenuBar = $0
                settingsManager.save()
            }
        )
    }

    private var showDockIconBinding: Binding<Bool> {
        Binding(
            get: { settingsManager.settings?.showDockIcon ?? true },
            set: {
                settingsManager.settings?.showDockIcon = $0
                settingsManager.save()
            }
        )
    }

    private var compactRowHeightBinding: Binding<Bool> {
        Binding(
            get: { settingsManager.settings?.compactRowHeight ?? false },
            set: {
                settingsManager.settings?.compactRowHeight = $0
                settingsManager.save()
            }
        )
    }

    private var editorFontSizeBinding: Binding<Int> {
        Binding(
            get: { settingsManager.settings?.editorFontSize ?? 14 },
            set: {
                settingsManager.settings?.setEditorFontSize($0)
                settingsManager.save()
            }
        )
    }

    private var historyRetentionBinding: Binding<Int> {
        Binding(
            get: { settingsManager.settings?.historyRetentionDays ?? 30 },
            set: {
                settingsManager.settings?.setHistoryRetention(days: $0)
                settingsManager.save()
            }
        )
    }

    private var autoClearQueueBinding: Binding<Bool> {
        Binding(
            get: { settingsManager.settings?.autoClearQueueOnQuit ?? false },
            set: {
                settingsManager.settings?.autoClearQueueOnQuit = $0
                settingsManager.save()
            }
        )
    }
}

// MARK: - Hotkey Settings

struct HotkeySettingsView: View {
    @ObservedObject private var settingsManager = SettingsManager.shared

    var body: some View {
        Form {
            Section("Global Hotkey") {
                HStack {
                    Text("Current hotkey:")
                    Spacer()
                    Text(settingsManager.settings?.hotkeyDescription ?? "Not Set")
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                }

                Text("Press ⌘⇧D to toggle Dispatch visibility from any app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Reset to Default (⌘⇧D)") {
                    settingsManager.settings?.setHotkey(
                        keyCode: AppSettingsDefaults.globalHotkeyKeyCode,
                        modifiers: AppSettingsDefaults.globalHotkeyModifiers
                    )
                    settingsManager.save()
                }
            }

            Section("Options") {
                Toggle("Send clipboard on hotkey", isOn: sendClipboardBinding)

                Text("When enabled, holding an additional modifier with the hotkey will send the clipboard contents as a prompt.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var sendClipboardBinding: Binding<Bool> {
        Binding(
            get: { settingsManager.settings?.sendClipboardOnHotkey ?? false },
            set: {
                settingsManager.settings?.sendClipboardOnHotkey = $0
                settingsManager.save()
            }
        )
    }
}

// MARK: - Terminal Settings

struct TerminalSettingsView: View {
    @ObservedObject private var settingsManager = SettingsManager.shared

    var body: some View {
        Form {
            Section("Terminal Integration") {
                Toggle("Auto-detect active terminal", isOn: autoDetectBinding)

                Toggle("Auto-refresh terminal list", isOn: autoRefreshBinding)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Send delay: \(Int(settingsManager.settings?.sendDelayMs ?? 100))ms")

                    Slider(
                        value: sendDelayBinding,
                        in: 0...500,
                        step: 50
                    )
                }

                Text("Delay after focusing Terminal before sending text. Increase if prompts are being sent before Terminal is ready.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Permissions") {
                HStack {
                    Label("Terminal Control", systemImage: "terminal")

                    Spacer()

                    Button("Open System Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }

                Text("Dispatch requires permission to control Terminal.app. Grant access in System Settings > Privacy & Security > Automation.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var autoDetectBinding: Binding<Bool> {
        Binding(
            get: { settingsManager.settings?.autoDetectActiveTerminal ?? true },
            set: {
                settingsManager.settings?.autoDetectActiveTerminal = $0
                settingsManager.save()
            }
        )
    }

    private var autoRefreshBinding: Binding<Bool> {
        Binding(
            get: { settingsManager.settings?.autoRefreshTerminalList ?? true },
            set: {
                settingsManager.settings?.autoRefreshTerminalList = $0
                settingsManager.save()
            }
        )
    }

    private var sendDelayBinding: Binding<Double> {
        Binding(
            get: { settingsManager.settings?.sendDelayMs ?? 100 },
            set: {
                settingsManager.settings?.sendDelayMs = $0
                settingsManager.save()
            }
        )
    }
}

// MARK: - Hook Settings

struct HookSettingsView: View {
    @ObservedObject private var settingsManager = SettingsManager.shared
    @ObservedObject private var hookManager = HookInstallerManager.shared
    @ObservedObject private var serverManager = HookServerManager.shared

    @State private var testResult: String?

    var body: some View {
        Form {
            Section("Claude Code Hook") {
                HStack {
                    Text("Hook status:")
                    Spacer()
                    statusBadge
                }

                if hookManager.status.isInstalled {
                    Button("Uninstall Hook") {
                        Task {
                            await hookManager.uninstall()
                        }
                    }
                    .disabled(hookManager.isInstalling)
                } else {
                    Button("Install Hook") {
                        Task {
                            await hookManager.install(port: settingsManager.settings?.hookServerPort ?? 19847)
                        }
                    }
                    .disabled(hookManager.isInstalling)
                }

                Text("The hook notifies Dispatch when Claude Code completes a response, enabling automatic queue and chain progression.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Hook Server") {
                HStack {
                    Text("Server status:")
                    Spacer()
                    Text(serverManager.isRunning ? "Running" : "Stopped")
                        .foregroundStyle(serverManager.isRunning ? .green : .secondary)
                }

                HStack {
                    Text("Port:")
                    Spacer()
                    TextField("Port", value: portBinding, format: .number)
                        .frame(width: 80)
                        .textFieldStyle(.roundedBorder)
                }

                HStack {
                    Button("Test Hook") {
                        Task {
                            let result = await serverManager.testConnection()
                            testResult = result ? "Connection successful!" : "Connection failed"
                        }
                    }
                    .disabled(!serverManager.isRunning)

                    if let result = testResult {
                        Text(result)
                            .font(.caption)
                            .foregroundStyle(result.contains("successful") ? .green : .red)
                    }
                }
            }

            Section("Fallback") {
                Toggle("Use polling fallback", isOn: pollingFallbackBinding)

                Text("When hooks are unavailable, poll Terminal content to detect completion. Less reliable but works without hook setup.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch hookManager.status {
        case .installed:
            Label("Installed", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .notInstalled:
            Label("Not Installed", systemImage: "xmark.circle")
                .foregroundStyle(.secondary)
        case .outdated:
            Label("Outdated", systemImage: "exclamationmark.circle")
                .foregroundStyle(.orange)
        case .error(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
        }
    }

    private var portBinding: Binding<Int> {
        Binding(
            get: { settingsManager.settings?.hookServerPort ?? 19847 },
            set: {
                settingsManager.settings?.setHookServerPort($0)
                settingsManager.save()
            }
        )
    }

    private var pollingFallbackBinding: Binding<Bool> {
        Binding(
            get: { settingsManager.settings?.usePollingFallback ?? true },
            set: {
                settingsManager.settings?.usePollingFallback = $0
                settingsManager.save()
            }
        )
    }
}

// MARK: - Project Discovery Settings

struct ProjectDiscoverySettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var discoveryManager = ProjectDiscoveryManager.shared

    var body: some View {
        Form {
            Section("Discover Claude Code Projects") {
                Text("Scan your computer for directories containing CLAUDE.md files to automatically import them as projects.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Button {
                        Task {
                            await discoveryManager.scanForProjects()
                        }
                    } label: {
                        if discoveryManager.isScanning {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else {
                            Label("Scan for Projects", systemImage: "magnifyingglass")
                        }
                    }
                    .disabled(discoveryManager.isScanning)

                    Spacer()

                    if let lastScan = discoveryManager.lastScanDate {
                        Text("Last scan: \(lastScan.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if !discoveryManager.discoveredProjects.isEmpty {
                Section("Discovered Projects (\(discoveryManager.discoveredProjects.count))") {
                    List {
                        ForEach(discoveryManager.discoveredProjects) { project in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(project.name)
                                        .font(.body)

                                    Text(project.path.path)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }

                                Spacer()

                                if let lastModified = project.lastModified {
                                    Text(lastModified.formatted(date: .abbreviated, time: .omitted))
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .frame(height: 150)

                    Button {
                        Task {
                            await discoveryManager.syncToAppProjects(context: modelContext)
                        }
                    } label: {
                        Label("Import All to Projects", systemImage: "square.and.arrow.down")
                    }
                }
            }

            Section("Search Locations") {
                Text("The following directories are searched for Claude Code projects:")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 4) {
                    Text("~/Developer")
                    Text("~/Projects")
                    Text("~/Code")
                    Text("~/Documents")
                    Text("~/Desktop")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.vertical, 4)
            }

            if let error = discoveryManager.error {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
}

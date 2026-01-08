//
//  HotkeyManager.swift
//  Dispatch
//
//  Global hotkey registration and management
//

import Foundation
import Combine
import Carbon.HIToolbox
import AppKit

// MARK: - Hotkey Manager

@MainActor
final class HotkeyManager: ObservableObject {
    static let shared = HotkeyManager()

    // MARK: - Published Properties

    @Published private(set) var isRegistered: Bool = false
    @Published private(set) var currentKeyCode: Int?
    @Published private(set) var currentModifiers: Int?

    // MARK: - Private Properties

    private var eventHandler: EventHandlerRef?
    private var hotkeyId: EventHotKeyID
    private var hotkeyRef: EventHotKeyRef?
    private var onHotkeyPressed: (() -> Void)?

    // MARK: - Initialization

    private init() {
        self.hotkeyId = EventHotKeyID(signature: OSType(0x44495350), id: 1)  // "DISP"
        logDebug("HotkeyManager initialized", category: .hotkey)
    }

    // Note: deinit removed - this is a singleton that lives for the app's lifetime
    // Cleanup is handled explicitly via unregister() in AppDelegate.applicationWillTerminate

    // MARK: - Registration

    /// Registers a global hotkey
    func register(keyCode: Int, modifiers: Int, handler: @escaping () -> Void) -> Bool {
        // Unregister existing hotkey first
        if isRegistered {
            unregister()
        }

        logInfo("Registering hotkey: keyCode=\(keyCode), modifiers=\(modifiers)", category: .hotkey)

        self.onHotkeyPressed = handler
        self.currentKeyCode = keyCode
        self.currentModifiers = modifiers

        // Convert modifiers to Carbon format
        var carbonModifiers: UInt32 = 0
        if modifiers & Int(cmdKey) != 0 { carbonModifiers |= UInt32(cmdKey) }
        if modifiers & Int(shiftKey) != 0 { carbonModifiers |= UInt32(shiftKey) }
        if modifiers & Int(optionKey) != 0 { carbonModifiers |= UInt32(optionKey) }
        if modifiers & Int(controlKey) != 0 { carbonModifiers |= UInt32(controlKey) }

        // Install event handler
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

        let handlerResult = InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, userData) -> OSStatus in
                guard let userData = userData else { return OSStatus(eventNotHandledErr) }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()

                Task { @MainActor in
                    manager.handleHotkeyPressed()
                }

                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )

        guard handlerResult == noErr else {
            logError("Failed to install event handler: \(handlerResult)", category: .hotkey)
            return false
        }

        // Register the hotkey
        let registerResult = RegisterEventHotKey(
            UInt32(keyCode),
            carbonModifiers,
            hotkeyId,
            GetApplicationEventTarget(),
            0,
            &hotkeyRef
        )

        guard registerResult == noErr else {
            logError("Failed to register hotkey: \(registerResult)", category: .hotkey)
            RemoveEventHandler(eventHandler)
            eventHandler = nil
            return false
        }

        isRegistered = true
        logInfo("Hotkey registered successfully", category: .hotkey)
        return true
    }

    /// Unregisters the current hotkey
    func unregister() {
        guard isRegistered else { return }

        logInfo("Unregistering hotkey", category: .hotkey)

        if let hotkeyRef = hotkeyRef {
            UnregisterEventHotKey(hotkeyRef)
            self.hotkeyRef = nil
        }

        if let eventHandler = eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }

        isRegistered = false
        currentKeyCode = nil
        currentModifiers = nil
        onHotkeyPressed = nil

        logDebug("Hotkey unregistered", category: .hotkey)
    }

    /// Updates the hotkey with new key combination
    func update(keyCode: Int, modifiers: Int) -> Bool {
        guard let handler = onHotkeyPressed else {
            logWarning("No handler registered, cannot update hotkey", category: .hotkey)
            return false
        }

        return register(keyCode: keyCode, modifiers: modifiers, handler: handler)
    }

    // MARK: - Handler

    private func handleHotkeyPressed() {
        logDebug("Hotkey pressed", category: .hotkey)
        onHotkeyPressed?()
    }

    // MARK: - Default Registration

    /// Registers the default hotkey from settings
    func registerFromSettings() {
        guard let settings = SettingsManager.shared.settings,
              let keyCode = settings.globalHotkeyKeyCode,
              let modifiers = settings.globalHotkeyModifiers else {
            logDebug("No hotkey configured in settings", category: .hotkey)
            return
        }

        _ = register(keyCode: keyCode, modifiers: modifiers) {
            HotkeyManager.shared.handleDefaultHotkeyAction()
        }
    }

    /// Default action when hotkey is pressed
    private func handleDefaultHotkeyAction() {
        logDebug("Handling default hotkey action", category: .hotkey)

        // Toggle app visibility
        if NSApp.isActive {
            NSApp.hide(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)

            // Focus search bar in main window
            if let window = NSApp.mainWindow {
                window.makeKeyAndOrderFront(nil)
            }
        }
    }
}

// MARK: - Hotkey Conflict Detection

extension HotkeyManager {
    /// Checks if the proposed hotkey conflicts with system shortcuts
    func checkForConflicts(keyCode: Int, modifiers: Int) -> [String] {
        var conflicts: [String] = []

        // Common system shortcuts to check
        let systemShortcuts: [(keyCode: Int, modifiers: Int, name: String)] = [
            (kVK_ANSI_Q, Int(cmdKey), "Quit Application"),
            (kVK_ANSI_W, Int(cmdKey), "Close Window"),
            (kVK_ANSI_H, Int(cmdKey), "Hide Application"),
            (kVK_ANSI_M, Int(cmdKey), "Minimize Window"),
            (kVK_Tab, Int(cmdKey), "Switch Applications"),
            (kVK_Space, Int(cmdKey), "Spotlight"),
        ]

        for shortcut in systemShortcuts {
            if keyCode == shortcut.keyCode && modifiers == shortcut.modifiers {
                conflicts.append(shortcut.name)
            }
        }

        if !conflicts.isEmpty {
            logWarning("Hotkey conflicts detected: \(conflicts)", category: .hotkey)
        }

        return conflicts
    }
}

// MARK: - Key Code Utilities

extension HotkeyManager {
    /// Converts a key code to a displayable string
    static func keyCodeToString(_ keyCode: Int) -> String? {
        let keyMap: [Int: String] = [
            kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D",
            kVK_ANSI_E: "E", kVK_ANSI_F: "F", kVK_ANSI_G: "G", kVK_ANSI_H: "H",
            kVK_ANSI_I: "I", kVK_ANSI_J: "J", kVK_ANSI_K: "K", kVK_ANSI_L: "L",
            kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O", kVK_ANSI_P: "P",
            kVK_ANSI_Q: "Q", kVK_ANSI_R: "R", kVK_ANSI_S: "S", kVK_ANSI_T: "T",
            kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X",
            kVK_ANSI_Y: "Y", kVK_ANSI_Z: "Z",
            kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3",
            kVK_ANSI_4: "4", kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7",
            kVK_ANSI_8: "8", kVK_ANSI_9: "9",
            kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥",
            kVK_Delete: "⌫", kVK_Escape: "⎋",
            kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4",
            kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8",
            kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12"
        ]
        return keyMap[keyCode]
    }

    /// Converts modifiers to a symbol string
    static func modifiersToString(_ modifiers: Int) -> String {
        var parts: [String] = []

        if modifiers & Int(controlKey) != 0 { parts.append("⌃") }
        if modifiers & Int(optionKey) != 0 { parts.append("⌥") }
        if modifiers & Int(shiftKey) != 0 { parts.append("⇧") }
        if modifiers & Int(cmdKey) != 0 { parts.append("⌘") }

        return parts.joined()
    }

    /// Returns a full hotkey description
    static func hotkeyDescription(keyCode: Int, modifiers: Int) -> String {
        let modifierString = modifiersToString(modifiers)
        let keyString = keyCodeToString(keyCode) ?? "?"
        return modifierString + keyString
    }
}

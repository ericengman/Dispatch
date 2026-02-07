# Technology Stack

**Analysis Date:** 2026-02-03

## Languages

**Primary:**
- Swift 6 - Core application language (checked via Xcode 16.2 toolchain)
- AppleScript - Terminal.app automation via NSAppleScript

**Secondary:**
- Markdown - Skill definitions and documentation

## Runtime

**Environment:**
- macOS (Sonoma 14.0 or later)
- Xcode 16.2 (LastSwiftUpdateCheck = 2620)

**Architecture:**
- Native macOS app compiled to arm64 (Apple Silicon) and x86_64 (Intel)

## Frameworks

**Core UI:**
- SwiftUI - Primary UI framework (declarative UI)
- AppKit - Native macOS integration (Terminal.app automation, workspace, events)

**Data Persistence:**
- SwiftData - Modern Swift data persistence (replaces Core Data)
  - Configured with SQLite backend
  - Models: Prompt, Project, PromptHistory, PromptChain, ChainItem, QueueItem, AppSettings, SimulatorRun, Screenshot

**Networking:**
- Network framework (NWListener, NWConnection) - HTTP server via Dispatch's custom HookServer implementation
- Foundation URLSession - For webhook health checks and external API calls

**System Integration:**
- Carbon.HIToolbox - Global hotkey registration (Carbon Events API)
  - EventHotKeyID, RegisterEventHotKey, InstallEventHandler
- Foundation (file management, AppleScript execution)
- os.log - System unified logging

**Concurrency:**
- Swift Concurrency (async/await)
- Combine - For observable state management (@Published, @ObservableObject)

## Key Dependencies

**Critical:**
- SwiftUI - No external dependencies for UI
- SwiftData - No external dependencies for persistence
- Carbon Events - Native macOS C APIs for hotkey handling

**Infrastructure:**
- Network framework - Built-in macOS networking stack
- NSAppleScript - Built-in AppleScript executor
- FileManager - File system operations
- NSWorkspace - Application launching and management

## Configuration

**Build Settings:**
- `MACOSX_DEPLOYMENT_TARGET = 26.2` (macOS 15.2 / Sequoia) - Note: This is future version target, likely should be 14.0+
- `ENABLE_APP_SANDBOX = NO` - Sandbox disabled (required for Terminal.app automation)
- `ENABLE_HARDENED_RUNTIME = YES` - Hardened runtime enabled
- `CODE_SIGN_STYLE = Automatic` - Automatic code signing
- `DEVELOPMENT_TEAM = DDF5NR4F37` - Team ID for signing

**Entitlements:**
- `Dispatch/Dispatch.entitlements` - Configures required permissions (AppleScript automation)

**Info.plist:**
- `NSAppleEventsUsageDescription` - "Dispatch needs to control Terminal.app to send prompts to Claude Code."
- `LOCALIZATION_PREFERS_STRING_CATALOGS = YES` - Modern string localization

**Build Options:**
- `SWIFT_APPROACHABLE_CONCURRENCY = YES` - Enforces strict concurrency checking
- `ENABLE_PREVIEWS = YES` - SwiftUI previews enabled
- `ENABLE_USER_SELECTED_FILES = readonly` - File picker restricted to read-only

## Platform Requirements

**Development:**
- Xcode 16.2 or later
- macOS 14.0 (Sonoma) or later for building
- Apple silicon or Intel Mac

**Production:**
- macOS 14.0+ (Sonoma or later) for runtime
- AppleScript automation permission for Terminal.app
- Global event monitoring permission for hotkey registration
- Network binding permission for local HTTP server (port 19847)

## Testing Targets

**Test Frameworks:**
- XCTest (standard macOS testing)

**Test Bundles:**
- `DispatchTests` - Unit tests
- `DispatchUITests` - UI tests

---

*Stack analysis: 2026-02-03*

# Phase 10: Dispatch App Updates - Research

**Researched:** 2026-02-03
**Domain:** Swift app resource bundling and auto-installation to user directories
**Confidence:** HIGH

## Summary

Phase 10 extends Dispatch's HookInstaller service to auto-install two external files when the app launches: the dispatch.sh shared library (`~/.claude/lib/dispatch.sh`) and the SessionStart hook (`~/.claude/hooks/session-start.sh`). Both files were created in Phases 8 and 9 and are currently installed manually.

The research examined HookInstaller.swift's existing patterns for hook management, investigated Swift Bundle resource bundling for embedding the library and hook scripts, explored version tracking mechanisms using `CFBundleShortVersionString`, and reviewed FileManager best practices for atomic writes with executable permissions.

**Key findings:**
- HookInstaller.swift already provides complete hook installation infrastructure (install, uninstall, checkStatus, verify)
- Current implementation only installs post-tool-use.sh hook, not session-start.sh or library
- Swift Bundle.main can embed text files as resources, accessed via `Bundle.main.url(forResource:withExtension:)`
- Version tracking via `Bundle.main.infoDictionary?["CFBundleShortVersionString"]` is standard (currently "1.0")
- FileManager pattern: write atomically, then setAttributes for 0o755 permissions (already used in HookInstaller)
- Installation timing: app launch is ideal (DispatchApp.swift setupApp() already calls HookInstallerManager.refreshStatus())

**Primary recommendation:** Extend HookInstaller with installLibrary() and installSessionStartHook() methods, bundle dispatch.sh and session-start.sh as app resources, trigger installation on app launch with version checking, handle errors gracefully without blocking app usage.

## Standard Stack

The established tools/patterns for Swift macOS resource bundling and file installation:

### Core
| Library/Tool | Version | Purpose | Why Standard |
|--------------|---------|---------|--------------|
| Foundation.Bundle | macOS 14+ | Resource access | Official Apple API for bundled resources |
| FileManager | macOS 14+ | File operations | Standard Swift file I/O with atomic writes |
| SwiftData | Latest | Settings persistence | Already used for AppSettings version tracking |
| FileManager.setAttributes | macOS 14+ | Set permissions | Official API for chmod operations |

### Supporting
| Library/Tool | Version | Purpose | When to Use |
|--------------|---------|---------|-------------|
| Bundle.main.infoDictionary | macOS 14+ | Version info | Access CFBundleShortVersionString |
| FileManager.createDirectory | macOS 14+ | Directory creation | withIntermediateDirectories: true pattern |
| String.write(to:atomically:) | macOS 14+ | File writing | atomically: true for concurrency safety |
| FileManager.fileExists | macOS 14+ | Existence checks | Before installation/update decisions |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Bundle resources | Hardcoded strings | Resources allow easier updates, version tracking |
| CFBundleShortVersionString | Custom version file | CFBundleShortVersionString is standard, Xcode-managed |
| Atomic writes | Direct write | Atomic prevents partial files on crash/interruption |
| FileManager.setAttributes | Process.run("chmod") | Native API is safer, platform-agnostic |

**Installation:**
None required - all APIs are part of Foundation framework included with Swift.

## Architecture Patterns

### Recommended Code Structure
```
Dispatch/
├── Resources/
│   ├── dispatch-lib.sh         # Bundled library content
│   └── session-start-hook.sh   # Bundled hook content
├── Services/
│   └── HookInstaller.swift     # Extended with library installation
└── DispatchApp.swift           # Calls installation on setupApp()
```

### Pattern 1: Bundle Resource Access
**What:** Embed bash scripts as app resources, access via Bundle.main
**When to use:** Files that must be installed to user directories
**Example:**
```swift
// Source: https://www.hackingwithswift.com/books/ios-swiftui/loading-resources-from-your-app-bundle
// Access bundled resource
guard let resourceURL = Bundle.main.url(forResource: "dispatch-lib", withExtension: "sh") else {
    throw HookInstallerError.resourceNotFound("dispatch-lib.sh")
}

let content = try String(contentsOf: resourceURL, encoding: .utf8)
```

### Pattern 2: Version-Based Update Detection
**What:** Compare installed file version with app bundle version
**When to use:** Deciding whether to update installed files
**Example:**
```swift
// Source: https://blog.rampatra.com/how-to-display-the-app-version-in-a-macos-ios-swiftui-app
// Get current app version
let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String

// Check installed library version
let installedContent = try? String(contentsOf: libraryURL, encoding: .utf8)
let installedVersion = installedContent?.firstMatch(of: /DISPATCH_LIB_VERSION="([^"]*)"/)

if appVersion != installedVersion {
    // Update needed
}
```

### Pattern 3: Atomic File Installation
**What:** Write to temp location, then move atomically to final location
**When to use:** Installing files that other processes might read
**Example:**
```swift
// Source: https://medium.com/swlh/file-handling-using-swift-f27895b19e22
// Write with atomic flag
try content.write(to: targetURL, atomically: true, encoding: .utf8)

// Set executable permissions (pattern from HookInstaller.swift line 118)
try FileManager.default.setAttributes(
    [.posixPermissions: 0o755],
    ofItemAtPath: targetURL.path
)
```

### Pattern 4: Installation on App Launch
**What:** Trigger installation during app startup, handle errors gracefully
**When to use:** Ensuring external files are always current
**Example:**
```swift
// Source: DispatchApp.swift lines 164-196
private func setupApp() {
    // ... existing setup ...

    // Install/update external files
    Task {
        await HookInstallerManager.shared.installLibraryIfNeeded()
        await HookInstallerManager.shared.installSessionStartHookIfNeeded()
    }
}
```

### Pattern 5: Directory Creation with Intermediate Directories
**What:** Create parent directories if they don't exist
**When to use:** Installing files to paths like ~/.claude/lib/ that might not exist
**Example:**
```swift
// Source: https://medium.com/@shashidj206/mastering-filemanager-in-swift-and-swiftui-7f29d6247644
let libraryDir = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".claude/lib", isDirectory: true)

try FileManager.default.createDirectory(
    at: libraryDir,
    withIntermediateDirectories: true,
    attributes: nil
)
```

### Anti-Patterns to Avoid
- **Writing without atomic flag:** Can corrupt files if interrupted (use atomically: true)
- **Setting permissions before writing:** String.write() overrides permissions, set after write
- **Hardcoding file content:** Embed as resources for version tracking and easier updates
- **Blocking app launch on installation failure:** Log error, allow app to continue
- **Not checking existing file version:** Could overwrite user modifications unnecessarily
- **Using single > redirect from Swift:** Use FileManager APIs, not shell redirects

## Don't Hand-Roll

Problems that look simple but have existing solutions:

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| File permissions | Process.run("chmod 755") | FileManager.setAttributes with .posixPermissions | Native API, proper error handling, no shell escaping |
| Atomic file writes | Write then rename | String.write(atomically: true) | Handles concurrency, temp file cleanup automatic |
| Version comparison | String parsing and logic | String.compare(options: .numeric) | Handles semantic version ordering correctly |
| Resource bundling | Embed strings in code | Bundle.main.url(forResource:) | Xcode manages, easier to update, keeps code clean |
| Directory creation | Recursive mkdir | createDirectory(withIntermediateDirectories: true) | Error handling, permissions, thread-safe |

**Key insight:** Swift Foundation provides complete file system abstractions. Using native APIs instead of shell commands improves error handling, avoids escaping issues, and provides better integration with Swift concurrency.

## Common Pitfalls

### Pitfall 1: String.write() Overrides Permissions
**What goes wrong:** Setting chmod 755 before writing file results in non-executable file
**Why it happens:** String.write() resets file permissions to default (644)
**How to avoid:** Always set executable permissions AFTER writing file content
**Warning signs:** Hook or library file exists but isn't executable, "permission denied" errors

### Pitfall 2: Non-Atomic Writes During Update
**What goes wrong:** App crashes during library update, leaving partial/corrupt file
**Why it happens:** Using atomically: false or direct writes without temp file
**How to avoid:** Always use atomically: true flag on write operations
**Warning signs:** Skills report "syntax error" after Dispatch crash during update

### Pitfall 3: Blocking App Launch on Installation Failure
**What goes wrong:** Dispatch won't start because ~/.claude/lib/ has permission issues
**Why it happens:** Installation errors throw exceptions that crash app startup
**How to avoid:** Wrap installation in do-catch, log errors, continue app launch
**Warning signs:** App crashes on launch with "permission denied" in logs

### Pitfall 4: Overwriting User Modifications
**What goes wrong:** User customized dispatch.sh, app update overwrites without warning
**Why it happens:** Not checking if file has been modified or has custom content
**How to avoid:** Check version marker in file, only update if version differs
**Warning signs:** Users report lost customizations after app updates

### Pitfall 5: Missing Bundle Resources in Build
**What goes wrong:** App builds but can't find dispatch-lib.sh resource
**Why it happens:** Resource file not added to Xcode project target membership
**How to avoid:** Verify resource appears in "Copy Bundle Resources" build phase
**Warning signs:** Bundle.main.url(forResource:) returns nil at runtime

### Pitfall 6: Wrong Directory Path Construction
**What goes wrong:** Library installed to /Users/eric/.claude/lib/dispatch.sh instead of ~/.claude/lib/dispatch.sh
**Why it happens:** Hardcoding username or not using FileManager.homeDirectoryForCurrentUser
**How to avoid:** Use FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/lib")
**Warning signs:** Works on developer machine, fails on other users' machines

## Code Examples

Verified patterns from official sources and existing codebase:

### Access App Version
```swift
// Source: https://blog.rampatra.com/how-to-display-the-app-version-in-a-macos-ios-swiftui-app
// Get marketing version (1.0, 1.1, etc.)
let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String

// Get build number (internal)
let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String

// Example: "1.0" (marketing) and "42" (build)
```

### Load Bundled Resource
```swift
// Source: https://www.hackingwithswift.com/example-code/system/how-to-find-the-path-to-a-file-in-your-bundle
// Load bash script from app bundle
guard let scriptURL = Bundle.main.url(forResource: "dispatch-lib", withExtension: "sh") else {
    throw HookInstallerError.resourceNotFound("dispatch-lib.sh")
}

let scriptContent = try String(contentsOf: scriptURL, encoding: .utf8)
```

### Install Library with Version Check
```swift
// Pattern derived from HookInstaller.swift existing patterns
actor LibraryInstaller {
    private let libraryDirectory: URL
    private let libraryFileName = "dispatch.sh"
    private let versionMarker = "DISPATCH_LIB_VERSION="

    func installIfNeeded() throws {
        let libraryPath = libraryDirectory.appendingPathComponent(libraryFileName)

        // Check if update needed
        let needsInstall = try checkIfInstallNeeded(at: libraryPath)

        if needsInstall {
            try install()
        }
    }

    private func checkIfInstallNeeded(at path: URL) throws -> Bool {
        guard FileManager.default.fileExists(atPath: path.path) else {
            // Not installed
            return true
        }

        // Check version
        let installedContent = try String(contentsOf: path, encoding: .utf8)
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String

        // Extract version from installed file
        if let versionLine = installedContent.components(separatedBy: .newlines)
            .first(where: { $0.contains(versionMarker) }),
           let installedVersion = versionLine.components(separatedBy: "\"").dropFirst().first {
            return installedVersion != appVersion
        }

        // Can't determine version - reinstall
        return true
    }

    private func install() throws {
        // Load from bundle
        guard let resourceURL = Bundle.main.url(forResource: "dispatch-lib", withExtension: "sh") else {
            throw HookInstallerError.resourceNotFound("dispatch-lib.sh")
        }

        let content = try String(contentsOf: resourceURL, encoding: .utf8)

        // Create directory if needed
        try FileManager.default.createDirectory(
            at: libraryDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )

        // Write atomically
        let targetPath = libraryDirectory.appendingPathComponent(libraryFileName)
        try content.write(to: targetPath, atomically: true, encoding: .utf8)

        // Set permissions (must be AFTER write)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: targetPath.path
        )

        logInfo("Library installed at \(targetPath.path)", category: .hooks)
    }
}
```

### Create Directory with Intermediate Paths
```swift
// Source: https://www.swiftyplace.com/blog/file-manager-in-swift-reading-writing-and-deleting-files-and-directories
let libraryDir = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".claude/lib", isDirectory: true)

do {
    try FileManager.default.createDirectory(
        at: libraryDir,
        withIntermediateDirectories: true,  // Creates ~/.claude/ and ~/.claude/lib/
        attributes: nil
    )
} catch {
    logError("Failed to create directory: \(error)", category: .hooks)
}
```

### Write File Atomically with Permissions
```swift
// Source: HookInstaller.swift lines 97-123 (existing pattern)
let targetPath = libraryDirectory.appendingPathComponent("dispatch.sh")

// Write atomically (creates temp file, renames on success)
try content.write(to: targetPath, atomically: true, encoding: .utf8)

// Set executable permissions (MUST be after write)
try FileManager.default.setAttributes(
    [.posixPermissions: 0o755],  // rwxr-xr-x
    ofItemAtPath: targetPath.path
)
```

### Version String Comparison
```swift
// Source: https://sarunw.com/posts/how-to-compare-two-app-version-strings-in-swift/
// Compare version strings numerically
let version1 = "1.0"
let version2 = "1.1"

let result = version1.compare(version2, options: .numeric)
// result is .orderedAscending (1.0 < 1.1)

switch result {
case .orderedAscending:
    print("version1 is older")
case .orderedSame:
    print("versions are equal")
case .orderedDescending:
    print("version1 is newer")
}
```

### Installation Status Enum Extension
```swift
// Extend existing HookInstallationStatus enum (lines 13-23)
enum LibraryInstallationStatus: Sendable {
    case installed
    case notInstalled
    case outdated
    case error(String)

    var needsInstallation: Bool {
        switch self {
        case .installed: return false
        case .notInstalled, .outdated: return true
        case .error: return false  // Don't retry on error
        }
    }
}
```

### Integration with DispatchApp Launch
```swift
// Source: DispatchApp.swift lines 164-196 (extend existing setupApp)
private func setupApp() {
    // ... existing setup code ...

    // Install/update external files (non-blocking)
    Task {
        do {
            try await HookInstallerManager.shared.installLibraryIfNeeded()
            try await HookInstallerManager.shared.installSessionStartHookIfNeeded()
            logInfo("External files up to date", category: .hooks)
        } catch {
            // Log but don't block app
            logError("Failed to install external files: \(error)", category: .hooks)
        }
    }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Manual bash script installation | App auto-installs on launch | Phase 10 (2026) | Users get latest library automatically |
| Hardcoded strings in Swift | Bundle resources | Modern Swift | Easier updates, version tracking |
| Shell commands for chmod | FileManager.setAttributes | Swift 3+ | Better error handling, type safety |
| `/tmp/myfile.$$` temp files | atomically: true flag | Modern Foundation | Built-in atomic writes |
| Manual version tracking | CFBundleShortVersionString | Standard | Xcode manages, consistent with app versioning |

**Deprecated/outdated:**
- **Hardcoded script content in code:** Bundle as resources instead
- **Process.run("chmod +x"):** Use FileManager.setAttributes with .posixPermissions
- **Non-atomic file writes:** Always use atomically: true for config files
- **Blocking installation:** Use async Task, log errors, continue app launch

## Open Questions

Things that couldn't be fully resolved:

1. **User customization preservation**
   - What we know: Users might customize dispatch.sh library
   - What's unclear: How to detect and preserve custom modifications vs. outdated versions
   - Recommendation: Check version marker only, warn users in docs that library is auto-updated

2. **Installation failure recovery**
   - What we know: Installation can fail (permissions, disk full, etc.)
   - What's unclear: Should app retry on next launch or require manual intervention
   - Recommendation: Retry on each launch (checkStatus → install), show status in settings UI

3. **Multiple Dispatch versions sharing ~/.claude/**
   - What we know: Users might run multiple Dispatch versions for testing
   - What's unclear: How to prevent version conflicts when different versions update library
   - Recommendation: Use app version in marker, newer version wins (semantic version comparison)

4. **Hook coexistence with other installers**
   - What we know: Other apps/tools might install to ~/.claude/hooks/
   - What's unclear: Whether to preserve or overwrite session-start.sh if it exists but wasn't created by Dispatch
   - Recommendation: Check for marker comment, only update if marker present OR file doesn't exist

## Sources

### Primary (HIGH confidence)
- `/Users/eric/Dispatch/Dispatch/Services/HookInstaller.swift` - Existing hook installation patterns
- `/Users/eric/Dispatch/Dispatch/DispatchApp.swift` - App launch lifecycle
- `/Users/eric/Dispatch/Dispatch.xcodeproj/project.pbxproj` - Current version: MARKETING_VERSION = 1.0
- `~/.claude/lib/dispatch.sh` - Library content (208 lines, version 1.0.0)
- `~/.claude/hooks/session-start.sh` - Hook content (40 lines)
- [Loading resources from your app bundle](https://www.hackingwithswift.com/books/ios-swiftui/loading-resources-from-your-app-bundle) - Official pattern
- [CFBundleShortVersionString Documentation](https://developer.apple.com/documentation/bundleresources/information-property-list/cfbundleshortversionstring) - Apple official

### Secondary (MEDIUM confidence)
- [How to display the app version in a macOS/iOS SwiftUI app](https://blog.rampatra.com/how-to-display-the-app-version-in-a-macos-ios-swiftui-app) - Version access patterns
- [Mastering FileManager in Swift and SwiftUI](https://medium.com/@shashidj206/mastering-filemanager-in-swift-and-swiftui-7f29d6247644) - Directory creation patterns
- [File handling with Swift - Atomic operations](https://medium.com/swlh/file-handling-using-swift-f27895b19e22) - Atomic write rationale
- [Working with files and folders in Swift](https://www.swiftbysundell.com/articles/working-with-files-and-folders-in-swift/) - Best practices
- [How to compare two app version strings in Swift](https://sarunw.com/posts/how-to-compare-two-app-version-strings-in-swift/) - Version comparison

### Tertiary (LOW confidence)
- [Where to Put Application Files](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPFileSystem/Articles/WhereToPutFiles.html) - Apple guideline (archived)
- [String.write() not respecting Unix permissions](https://forums.swift.org/t/string-write-not-respecting-unix-permissions/44224) - Known limitation

## Metadata

**Confidence breakdown:**
- Resource bundling: HIGH - Standard Swift Bundle API, well-documented
- Version tracking: HIGH - CFBundleShortVersionString is established standard
- File operations: HIGH - FileManager patterns verified in existing HookInstaller
- Installation timing: HIGH - DispatchApp.swift setupApp() is clear integration point
- Atomic writes: HIGH - String.write(atomically: true) is documented Foundation API

**Research date:** 2026-02-03
**Valid until:** 90 days (stable Swift APIs, but app architecture might evolve)

**Key risks mitigated:**
- ✅ Verified HookInstaller provides complete installation infrastructure
- ✅ Confirmed Bundle.main resource access pattern for bash scripts
- ✅ Validated FileManager.setAttributes for executable permissions (already used)
- ✅ Identified app launch as ideal installation timing (setupApp() exists)
- ✅ Researched version comparison for update detection
- ⚠️  User customization preservation strategy needs design decision
- ⚠️  Retry logic for failed installations needs specification

**Ready for planning:** Yes - all technical patterns verified, existing infrastructure identified, clear integration points documented.

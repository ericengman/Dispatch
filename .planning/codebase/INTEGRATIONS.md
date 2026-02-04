# External Integrations

**Analysis Date:** 2026-02-03

## APIs & External Services

**Terminal.app Control:**
- Service: Terminal.app (native macOS)
  - SDK/Client: NSAppleScript (Foundation framework)
  - Integration: `Dispatch/Services/TerminalService.swift`
  - Purpose: Send prompts, detect active window, enumerate windows
  - Auth: AppleScript automation permission (user-granted via System Settings)

**Claude Code Integration:**
- Service: Claude Code (runs in Terminal.app)
  - Integration: Hook-based webhook + polling fallback
  - Purpose: Detect execution completion, track session state
  - Methods:
    - Primary: HTTP POST to local hook server
    - Fallback: Poll terminal content for Claude prompt pattern (`╭─`)

## Data Storage

**Databases:**
- SwiftData (SQLite backed)
  - Location: System-determined (typically ~/Library/Application Support/com.Eric.Dispatch/)
  - Client: SwiftData @Model framework
  - Schema: Prompt, Project, PromptHistory, PromptChain, ChainItem, QueueItem, AppSettings, SimulatorRun, Screenshot
  - Connection: Local file-based, no network access

**File Storage:**
- Local filesystem only
  - Prompts: SwiftData persistence
  - Screenshots: `~/Library/Application Support/Dispatch/screenshots/` (configurable via `AppSettings.screenshotDirectory`)
  - Skills: `~/.claude/skills/` (system-wide), `./.claude/skills/` (project-level)
  - Hooks: `~/.claude/hooks/stop.sh` (stop hook script)

**Caching:**
- In-memory window cache (2-second TTL) in `TerminalService`
- No external cache service

## Authentication & Identity

**Auth Provider:**
- None - Local-only application
- No user accounts or cloud sync
- AppleScript automation requires explicit OS-level permission grant

## Monitoring & Observability

**Error Tracking:**
- None - No external error tracking service

**Logs:**
- Native os.log (unified logging) to macOS system logger
  - Subsystem: `com.Eric.Dispatch`
  - Categories: APP, DATA, TERMINAL, QUEUE, CHAIN, HOOKS, HOTKEY, PLACEHOLDER, UI, SETTINGS, HISTORY, EXECUTION, NETWORK, SIMULATOR
  - Log levels: DEBUG, INFO, WARN, ERROR, CRITICAL
  - Integration: `Dispatch/Services/LoggingService.swift`

## CI/CD & Deployment

**Hosting:**
- None - Native macOS application distributed as .app bundle
- Development: Built locally with Xcode
- Distribution: Standalone executable (not App Store)

**CI Pipeline:**
- None detected - No GitHub Actions or external CI service integration

## Local HTTP Server

**Hook Server:**
- Implementation: `Dispatch/Services/HookServer.swift`
- Framework: Network.framework (NWListener + NWConnection)
- Host/Port: 127.0.0.1:19847 (configurable via `AppSettings.hookServerPort`)
- Purpose: Receive Claude Code completion webhooks

**Endpoints:**
- `POST /hook/complete` - Completion notification from Claude Code
- `GET /health` - Health check
- `GET /` - Service info
- `GET /screenshots/location` - Screenshot directory location request
- `POST /screenshots/run` - Create new screenshot run
- `POST /screenshots/complete` - Mark run as complete

**Request/Response:**
- Format: JSON with UTF-8 encoding
- Completion payload: `{ session: string?, timestamp: string? }`
- No authentication (localhost only)

## External File Monitoring

**Screenshot Watcher:**
- Service: `Dispatch/Services/ScreenshotWatcherService.swift`
- Source: Monitors filesystem for simulator screenshot directories
- Trigger: Filesystem events on screenshot directory
- Purpose: Track Xcode simulator runs and associate screenshots

## Environment Configuration

**Required env vars:**
- None - Configuration stored in SwiftData AppSettings model

**Secrets location:**
- None - No external secrets required
- AppleScript permissions managed via macOS System Settings privacy controls

## Webhooks & Callbacks

**Incoming:**
- `POST /hook/complete` from Claude Code stop hook (`~/.claude/hooks/stop.sh`)
  - Body: `{ "session": "optional-session-id", "timestamp": "ISO-8601-timestamp" }`
  - Response: `{ "received": true }` (JSON)

**Outgoing:**
- None - No outbound webhooks sent by Dispatch

## macOS System Services Used

**Global Hotkey:**
- Carbon Events API (Carbon.HIToolbox)
- Purpose: Register ⌘⇧D global hotkey for bringing up Dispatch
- Integration: `Dispatch/Services/HotkeyManager.swift`

**Workspace & Application Management:**
- NSWorkspace - Enumerate running apps, launch applications
- NSApplication - App lifecycle, dock/menu bar integration
- Purpose: Detect if Terminal.app is running, launch new terminal windows

**Accessibility:**
- EventHotKeyID, InstallEventHandler, RegisterEventHotKey - Global event handling
- Purpose: Intercept hotkey presses system-wide

---

*Integration audit: 2026-02-03*

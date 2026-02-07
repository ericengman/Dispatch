# Codebase Concerns

**Analysis Date:** 2026-02-03

## Tech Debt

**Large Service Files - Complexity and Maintenance Risk:**
- Issue: `TerminalService.swift` (923 lines), `SkillsSidePanel.swift` (823 lines), `PromptEditorView.swift` (680 lines), and `HookServer.swift` (636 lines) are complex monoliths combining multiple responsibilities
- Files: `Dispatch/Services/TerminalService.swift`, `Dispatch/Views/Skills/SkillsSidePanel.swift`, `Dispatch/Views/Prompts/PromptEditorView.swift`, `Dispatch/Services/HookServer.swift`
- Impact: Difficult to test, maintain, and modify without side effects. Changes require understanding large portions of code. Risk of introducing bugs when refactoring.
- Fix approach: Break into smaller, single-responsibility modules. `TerminalService` could split into `TerminalWindowManager`, `TerminalScriptExecutor`, `AppleScriptEscaper`. `SkillsSidePanel` could extract skills display, memory display, and screenshot runs into separate views.

**Incomplete TODO Marker:**
- Issue: Unimplemented feature request in history list view
- Files: `Dispatch/Views/History/HistoryListView.swift:122`
- Impact: Users cannot save executed prompts back to library with custom titles, limiting workflow efficiency
- Fix approach: Implement sheet-based dialog for capturing new title when saving history item to library

**Manual String Parsing - AppleScript Results:**
- Issue: AppleScript list results are parsed manually with delimiter splitting (`|||` and `;;;`) in multiple places instead of using structured serialization
- Files: `Dispatch/Services/TerminalService.swift` (lines 219-232, 268-272, 393-398, 434-439) - uses string splitting with hardcoded delimiters
- Impact: Fragile to AppleScript output changes, no validation of format, difficult to extend with new fields
- Fix approach: Consider using JSON for AppleScript return values or implement proper result type validation with clear error messages

**Silent Error Handling with Optional Chains:**
- Issue: Multiple `try?` patterns throughout codebase silently discard errors without logging, making debugging difficult
- Files: `Dispatch/Services/TerminalService.swift` (lines 124, 533, 705), `Dispatch/Services/ProjectDiscoveryService.swift` (lines 27, 101, 192-195, 250)
- Impact: Failures are hidden from logging; when features don't work, root cause is unclear. Errors cannot be bubbled to user UI.
- Fix approach: Replace `try?` with explicit `do/catch` blocks that log errors. Only use `try?` when failure is genuinely ignorable and should be logged at debug level.

**Window Caching Without Invalidation Strategy:**
- Issue: Terminal window cache in `TerminalService` has 2-second TTL but invalidation is manual; cache can become stale if windows close/open between cache checks
- Files: `Dispatch/Services/TerminalService.swift` (lines 70-72, 174-182, 234-236)
- Impact: User sees phantom windows or misses new windows when switching between apps. Tab/window titles may be outdated.
- Fix approach: Add event listener for Terminal window changes, implement opportunistic cache invalidation on cache miss, or reduce TTL to 500ms for more responsiveness

## Known Bugs

**Clipboard Restoration Race Condition:**
- Symptoms: User's clipboard content may be lost or corrupted after sending prompts, especially if multiple prompts are sent in quick succession
- Files: `Dispatch/Services/TerminalService.swift:532-538` (clipboard restoration in background Task)
- Trigger: Send multiple prompts rapidly; switch apps immediately after sending
- Cause: Clipboard is restored asynchronously in a 500ms background Task. If user copies something new before restoration completes, the new content is overwritten.
- Workaround: Wait 1 second after sending before using clipboard

**AppleScript Newline Handling Edge Case:**
- Symptoms: Multi-line prompts containing newlines may send to Terminal with escaped sequences visible instead of actual line breaks
- Files: `Dispatch/Services/TerminalService.swift:588` (newline replacement to `\" & return & \"`)
- Trigger: Send prompt with newlines using `sendPrompt()` method
- Cause: Escape replacement `\n → \" & return & \"` assumes proper context in AppleScript string; if prompt already contains quotes, result becomes malformed
- Workaround: Avoid mixing newlines with quote marks in single prompt; use `typeText()` instead of `sendPrompt()` which uses clipboard (avoids escaping)

**File Descriptor Leak in ScreenshotWatcherService:**
- Symptoms: File descriptor usage accumulates over time; system may run out of open file descriptors after extended app usage
- Files: `Dispatch/Services/ScreenshotWatcherService.swift:160-210`
- Trigger: Repeatedly start/stop watching for screenshots
- Cause: If `dispatchSource?.cancel()` completes before `close(fileDescriptor)` executes in `cleanupWatcher()`, or if exception occurs between `open()` and handler setup, descriptor remains open
- Fix: Add `try/catch` in `stopWatching()` to guarantee `close()` call; consider using `defer` block

**Duplicate File Watcher in SkillsSidePanel:**
- Symptoms: Screenshot runs UI may freeze or become unresponsive when switching projects
- Files: `Dispatch/Views/Skills/SkillsSidePanel.swift:451-469` (manual file descriptor/DispatchSource setup alongside ScreenshotWatcherService)
- Trigger: Switch between projects with screenshot runs; observed UI lag
- Cause: SkillsSidePanel creates its own file system watcher in addition to the ScreenshotWatcherService, duplicating work and potentially competing for file descriptor resources
- Fix: Remove manual watcher from SkillsSidePanel; subscribe to notifications from ScreenshotWatcherService instead

## Security Considerations

**AppleScript Injection Vulnerability - Partial Mitigation:**
- Risk: User-controlled prompt content is embedded in AppleScript strings; inadequate escaping could allow script injection
- Files: `Dispatch/Services/TerminalService.swift:312-334` (script generation), `Dispatch/Services/TerminalService.swift:577-594` (escaping logic)
- Current mitigation: Escaping implemented for `\`, `"`, `\n`, `\t`; however, other AppleScript special sequences (comments `--`, line continuations) may not be fully handled
- Recommendations:
  - Add escaping for `--` sequences to prevent comment injection
  - Consider using `NSAppleScript` parameter passing if available instead of string interpolation
  - Add unit tests for AppleScript escaping with attack payloads
  - Document which characters are safe/unsafe in prompts

**Cleartext Local HTTP Server - Hook Notifications:**
- Risk: HookServer receives completion notifications over unencrypted HTTP on localhost; vulnerability if malicious process on same machine can access port 19847
- Files: `Dispatch/Services/HookServer.swift` (lines 83-320)
- Current mitigation: Bound to `127.0.0.1` localhost only, port hardcoded
- Recommendations:
  - Add optional HTTPS/mTLS support with self-signed certificate
  - Add request signature verification using HMAC-SHA256
  - Validate incoming requests to only accept from expected Claude Code session
  - Document security assumptions (assumes trusted local environment only)

**Clipboard Access Without User Confirmation:**
- Risk: App reads clipboard content to auto-fill `{{clipboard}}` placeholder without prompting user; could leak sensitive data from clipboard
- Files: `Dispatch/Services/PlaceholderResolver.swift:88-89` (auto-fill from clipboard)
- Current mitigation: Only auto-fills if user explicitly uses `{{clipboard}}` placeholder; feature is optional
- Recommendations:
  - Add setting to enable/disable clipboard auto-fill
  - Show preview of clipboard content before sending prompt
  - Consider requiring user confirmation dialog when `{{clipboard}}` is resolved
  - Log when clipboard is accessed

**Hardcoded Hook Installation in User Home:**
- Risk: Hook installer writes to `~/.claude/hooks/post-tool-use.sh` without verifying file ownership or existing hooks from other sources
- Files: `Dispatch/Services/HookInstaller.swift:40-42, 86-124`
- Current mitigation: Checks for Dispatch marker in existing file before appending
- Recommendations:
  - Verify `.claude` directory ownership before writing
  - Add file permission verification (should be user-readable/writable only)
  - Consider backing up existing hook before modification
  - Warn user if other hook installations are detected

## Performance Bottlenecks

**Terminal Window Enumeration Blocking UI:**
- Problem: `TerminalService.getWindows()` executes AppleScript synchronously on main thread during UI rendering, can cause 100-500ms UI freezes
- Files: `Dispatch/Services/TerminalService.swift:174-237`, called from `Dispatch/Views/Prompts/PromptEditorView.swift:56-61` (onAppear)`
- Cause: Terminal window list fetching is not debounced; every project change or editor appearance triggers fresh enumeration
- Improvement path:
  - Move window enumeration to background actor
  - Implement aggressive caching (5-10 second TTL)
  - Debounce terminal list requests when multiple change events fire
  - Add loading state in UI rather than blocking

**Search Filtering on Every Character Input:**
- Problem: Full prompt list scan occurs on every search text change without debouncing
- Files: `Dispatch/ViewModels/PromptViewModel.swift:129-136` (filter/search logic applied synchronously)
- Cause: Search fires immediately without delay; on large prompt libraries (1000+ items) this causes perceptible lag
- Improvement path:
  - Add 300ms debounce to search text changes
  - Consider background Task for filtering
  - Implement indexed search for content

**File System Scanning Without Depth Limit Protection:**
- Problem: Project discovery recursively scans directories without hard depth limit protection; could scan deep directory trees
- Files: `Dispatch/Services/ProjectDiscoveryService.swift:118-171` (recursive scan with `maxDepth` parameter)
- Cause: Even with `maxDepth = 5`, scanning very deep project hierarchies or loop symlinks can consume resources
- Improvement path:
  - Add early exit when file count exceeds threshold (e.g., 10,000 files scanned)
  - Implement timeout (max 5 seconds per search path)
  - Cache project list and only rescan on manual refresh
  - Add progress reporting for UI

**Unoptimized Database Queries in Views:**
- Problem: ViewModels fetch all items then filter in memory rather than using SwiftData predicates
- Files: `Dispatch/ViewModels/QueueViewModel.swift:56-58` (fetches with `.pending` status check), `Dispatch/ViewModels/SimulatorViewModel.swift:65-67` (filters by project ID)
- Cause: Simpler to write but scales poorly; all database rows must be loaded before filtering
- Improvement path:
  - Move filter predicates into SwiftData FetchDescriptor
  - Add indexes on frequently filtered columns (status, project ID)
  - Measure query performance with large datasets (10,000+ items)

## Fragile Areas

**AppleScript Parsing of Terminal State:**
- Files: `Dispatch/Services/TerminalService.swift:218-232, 268-272`
- Why fragile: Manual delimiter parsing (`|||` for field separation, `;;;` for list items) assumes exact output format from AppleScript. Any change in Terminal OS version or macOS behavior could break parsing.
- Safe modification: Add validation that parsed fields contain expected content; add logging of raw AppleScript output when parsing fails. Consider unit tests with mocked AppleScript responses.
- Test coverage: No explicit tests for AppleScript result parsing

**Complex View Hierarchy in SkillsSidePanel:**
- Files: `Dispatch/Views/Skills/SkillsSidePanel.swift` (823 lines)
- Why fragile: Single view manages three independent collapsible sections (runs, memory, skills), file watching, terminal loading, and permission alerts. Adding a feature requires understanding interactions between sections.
- Safe modification: Extract each section into separate views (`ScreenshotRunsSection`, `MemorySection`, `SkillsSection`). Use separate @State containers for each. Test section independence.
- Test coverage: No unit tests for individual sections

**ExecutionStateMachine State Transitions:**
- Files: `Dispatch/Services/ExecutionStateMachine.swift` (511 lines)
- Why fragile: IDLE → SENDING → EXECUTING → COMPLETED is linear; no guard against double-triggering or out-of-order transitions. State observers (closures) can become inconsistent if exception occurs during transition.
- Safe modification: Add state invariant checks before each transition. Consider using Result type to handle transition failures atomically. Document which states are re-entrant.
- Test coverage: Gaps in testing edge cases (concurrent state change attempts, transition during error handling)

**HookServer Connection Handling:**
- Files: `Dispatch/Services/HookServer.swift:235-310` (connection state handlers with closures)
- Why fragile: Multiple weak self references; if HookServer deallocates during active connections, handlers may fail silently. Connection cleanup relies on proper cancellation sequence.
- Safe modification: Add explicit connection lifecycle tracking. Ensure all connections are cleaned up in deinit or explicit stop() method. Add timeout for stalled connections.
- Test coverage: No tests for connection cleanup scenarios

## Scaling Limits

**History Retention Without Cleanup:**
- Current capacity: `historyRetentionDays` defaults to 30 days; no automatic cleanup implemented
- Limit: With average 10 prompts/day, 30-day retention = 300 history records per user. At 1-2KB per record, approaches 500KB per month; over years could exceed reasonable database size
- Scaling path:
  - Implement automatic history cleanup in app startup/weekly background task
  - Add index on `createdAt` for efficient old-record deletion
  - Consider archival strategy (export and compress old history)

**Screenshot Runs Storage:**
- Current capacity: Default 10 runs per project; each run may contain 5-20 screenshots (10-50MB per run)
- Limit: 10 runs × 50MB = 500MB per project; unlimited projects means storage can grow to GB range
- Scaling path:
  - Implement disk usage monitoring
  - Add quota enforcement (max 5GB total for screenshots)
  - Implement LRU eviction when quota exceeded
  - Add UI warning when disk usage exceeds 80% of quota

**Terminal Window Enumeration with Many Windows:**
- Current capacity: AppleScript enumeration works smoothly with <50 Terminal windows
- Limit: With 100+ windows, AppleScript enumeration can take 1-2 seconds, causing UI freezes
- Scaling path:
  - Cache aggressively when window count is high
  - Add pagination/filtering in terminal selection UI
  - Consider limiting enumeration to workspace/screen boundaries
  - Profile AppleScript performance with high window counts

**Prompt Search on Large Libraries:**
- Current capacity: Smooth filtering with <500 prompts
- Limit: With 2000+ prompts, in-memory filtering and sort becomes noticeably slow (>500ms)
- Scaling path:
  - Implement full-text search using SQLite FTS if SwiftData allows
  - Add pagination/virtualization in prompt list view
  - Cache search results with invalidation on prompt modification
  - Profile filtering performance with realistic dataset

## Dependencies at Risk

**AppleScript API Stability:**
- Risk: NSAppleScript is deprecated in favor of newer scripting frameworks; Terminal.app AppleScript interface could change or be removed in future macOS versions
- Impact: Core prompt dispatch feature would break
- Migration plan:
  - Monitor Apple documentation for Terminal automation alternatives
  - Consider switch to shell scripting via `Process` if Terminal API changes
  - Evaluate JXA (JavaScript for Automation) as AppleScript replacement
  - Start testing on latest macOS beta versions early

**HotKey Package Maintenance:**
- Risk: Third-party SPM dependency `soffes/HotKey` (0.2.0) has limited maintenance; may not support future macOS/Swift versions
- Impact: Global hotkey feature could break on major macOS upgrades
- Migration plan:
  - Evaluate in-house implementation using `NSEvent.addGlobalMonitorForEvents`
  - Check for alternative maintained hotkey libraries
  - Implement fallback if HotKey becomes unavailable (menu-based only)

## Test Coverage Gaps

**Untested AppleScript String Escaping:**
- What's not tested: Edge cases in `escapeForAppleScript()` - strings containing combinations of `\n`, `"`, `\`, special unicode, control characters
- Files: `Dispatch/Services/TerminalService.swift:577-594`
- Risk: Injection attacks or malformed scripts sent to Terminal without detection
- Priority: High - security-relevant

**Untested State Machine Transitions:**
- What's not tested: Concurrent state change requests, state transitions during error conditions, timeout handling in EXECUTING state
- Files: `Dispatch/Services/ExecutionStateMachine.swift`
- Risk: Execution may become hung or inconsistent if edge cases occur in production
- Priority: High - core functionality

**Untested File System Watcher:**
- What's not tested: File descriptor cleanup under error conditions, behavior with rapid file system changes, symlink handling
- Files: `Dispatch/Services/ScreenshotWatcherService.swift:152-210`
- Risk: File descriptor leaks accumulate; missing screenshots if events fire too quickly
- Priority: Medium - resource leak risk

**Untested Database Transaction Rollback:**
- What's not tested: SwiftData context save failures, partial updates when adding items to queue, history, chains
- Files: `Dispatch/ViewModels/QueueViewModel.swift:84-86` (insert & save), `Dispatch/ViewModels/PromptViewModel.swift:200+` (edit operations)
- Risk: Database corruption or inconsistency if save fails mid-operation
- Priority: Medium - data integrity

**Untested Hook Installation Conflicts:**
- What's not tested: Behavior when `.claude/hooks/post-tool-use.sh` already exists with incompatible hooks, permission issues on restrictive filesystems
- Files: `Dispatch/Services/HookInstaller.swift:99-124`
- Risk: Silent failure to install hooks; user unaware that completion detection won't work
- Priority: Medium - user-facing feature

---

*Concerns audit: 2026-02-03*

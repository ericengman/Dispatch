# Feature Research: Skill to Dispatch Screenshot Integration

**Domain:** CLI-to-macOS-app communication for iOS simulator screenshot management
**Researched:** 2026-02-03
**Confidence:** HIGH (based on existing codebase and skill implementations)

## Feature Landscape

### Table Stakes (Users Expect These)

Features skills assume exist. Missing these = integration broken or confusing.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Health check endpoint | Skills check if Dispatch is running before calling other APIs | LOW | Already exists: GET `/health` returns `{"status":"ok"}` |
| Create run with path response | Skills need to know WHERE to save files before capturing | LOW | Already exists: POST `/screenshots/run` returns `{"runId":"...", "path":"..."}` |
| Complete run endpoint | Skills signal when capture session is done | LOW | Already exists: POST `/screenshots/complete` triggers directory scan |
| Graceful degradation when Dispatch offline | Skills should work without Dispatch; screenshots go to fallback location | MEDIUM | Skills implement this client-side; Dispatch can't help when offline |
| Immediate path availability | Return path is writable immediately (directory pre-created) | LOW | HookServer already creates directory in `handleScreenshotLocation` |
| JSON API responses | Skills parse with basic shell tools (grep, cut, jq) | LOW | Already uses JSON; keep responses simple and flat |
| Consistent error responses | Skills need to know when something failed and why | LOW | Currently returns `{"error":"..."}` on failure |

### Differentiators (Competitive Advantage)

Features that improve DX but aren't strictly required for integration to work.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Run naming with feature context | Descriptive names like "QA: Settings" help user identify runs in Dispatch UI | LOW | Already supported: `name` field in create request |
| Device info tracking | Knowing which simulator was used helps correlate screenshots | LOW | Already supported: `device` field in create request |
| Run metadata in manifest | Store skill name, test parameters for later reference | LOW | RunManifest already captures basic metadata |
| Auto-cleanup of old runs | Prevent disk bloat from accumulated screenshot runs | LOW | Already implemented: `maxRunsPerProject` in config |
| Filename conventions documentation | Skills benefit from guidance on naming (e.g., `{screen}_{state}.png`) | LOW | Documentation exists in skills; could standardize |
| Batch screenshot registration | Register multiple screenshots in one call instead of relying on filesystem scan | MEDIUM | Not implemented; would reduce race conditions |
| Screenshot annotations via API | Skills could add labels/notes during capture, not just after in UI | MEDIUM | Not implemented; Screenshot model has `label` field |
| Progress notifications | Dispatch could show real-time capture progress | HIGH | Would require WebSocket or polling; overkill for MVP |

### Anti-Features (Commonly Requested, Often Problematic)

Features that seem good but create problems.

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| Automatic screenshot capture | "Dispatch should watch simulator and capture automatically" | Noisy; captures unwanted states; skills know WHEN to capture | Let skills control timing; Dispatch just stores/displays |
| Screenshot diff/comparison | "Detect visual regressions automatically" | Complex ML/image processing; many false positives; scope creep | Manual review in Dispatch UI; future separate tool |
| Direct file upload to Dispatch | "POST screenshot bytes to API instead of saving to path" | Large payloads over HTTP; complicates error handling; skills already have file access | Path-based approach is simpler and more reliable |
| Bidirectional communication | "Skills should wait for user feedback before continuing" | Breaks skill execution flow; user may not be watching Dispatch | Skills complete independently; user reviews async |
| Screenshot editing in Dispatch | "Crop, annotate, markup in-app" | Scope creep; macOS Preview does this well | Export to Preview; focus on organization/dispatch |
| Automatic project detection | "Dispatch should know which project based on process/window" | Unreliable; multiple projects open; Terminal doesn't expose this cleanly | Skills explicitly pass project name (already works) |

## Feature Dependencies

```
[Health Check]
    └──enables──> [Create Run] (skills check health first)
                      │
                      └──provides──> [Screenshot Path]
                                         │
                                         └──used by──> [Skill Screenshot Capture]
                                                           │
                                                           └──followed by──> [Complete Run]
                                                                                 │
                                                                                 └──triggers──> [Filesystem Scan]
                                                                                                    │
                                                                                                    └──creates──> [SwiftData Records]
```

### Dependency Notes

- **Health Check enables Create Run:** Skills must verify Dispatch is running before calling other endpoints; if offline, they fall back to local storage
- **Create Run provides Screenshot Path:** The returned `path` is where skills save files; this is the critical handoff point
- **Complete Run triggers Filesystem Scan:** Calling `/complete` tells Dispatch to scan the run directory and import screenshots into the database
- **Filesystem Scan creates SwiftData Records:** Imported screenshots become SimulatorRun and Screenshot model instances for UI display

## MVP Definition

### Launch With (v1)

The current implementation already covers MVP. Validation needed:

- [x] Health check endpoint works - Skills can detect Dispatch running
- [x] Create run returns usable path - Skills can save screenshots
- [x] Complete run triggers import - Screenshots appear in Dispatch UI
- [x] Graceful offline fallback - Skills document default location behavior
- [ ] **Fix screenshot path routing** - This is the milestone's core issue; ensure path is actually usable

### Add After Validation (v1.x)

Features to add once core path is working and validated by real skill usage:

- [ ] **Screenshot labels via API** - POST `/screenshots/{id}/label` to set label without UI
  - Trigger: Skills want to add context during capture, not just after
- [ ] **Bulk screenshot registration** - POST `/screenshots/bulk` with array of paths
  - Trigger: Large test runs with many screenshots; reduce race conditions with filesystem watcher
- [ ] **Run status query** - GET `/screenshots/run/{id}` to check if run is complete, screenshot count
  - Trigger: Skills want to verify completion or debug why screenshots aren't appearing

### Future Consideration (v2+)

Features to defer until integration is proven stable:

- [ ] **WebSocket for real-time updates** - Dispatch pushes screenshot notifications to listeners
  - Why defer: Adds complexity; current polling/scan approach works
- [ ] **Screenshot metadata API** - Store arbitrary key-value pairs per screenshot
  - Why defer: Label field covers most use cases; metadata scope creep
- [ ] **Multi-run comparison** - Compare screenshots across different runs
  - Why defer: UI complexity; separate feature from basic capture/display

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| Fix path routing (milestone core) | HIGH | LOW | P1 |
| Verify health check reliability | HIGH | LOW | P1 |
| Verify create/complete cycle works | HIGH | LOW | P1 |
| Document graceful degradation clearly | MEDIUM | LOW | P1 |
| Screenshot labels via API | MEDIUM | LOW | P2 |
| Bulk screenshot registration | MEDIUM | MEDIUM | P2 |
| Run status query | LOW | LOW | P3 |
| WebSocket notifications | LOW | HIGH | P3 |

**Priority key:**
- P1: Must work for integration to function
- P2: Should have, improves reliability/DX
- P3: Nice to have, future consideration

## Error Handling Specifications

### Skill-Side Error Handling

Skills must handle these scenarios:

| Scenario | Detection | Behavior |
|----------|-----------|----------|
| Dispatch not running | Health check fails (connection refused/timeout) | Use fallback path (`.screenshots/` or project-specific location) |
| Create run fails | HTTP error or missing `runId`/`path` in response | Log warning, use fallback path, continue testing |
| Path not writable | Screenshot save fails | Log error, attempt fallback location |
| Complete run fails | HTTP error | Log warning, screenshots may not appear in Dispatch UI immediately |

### Dispatch-Side Error Handling

Dispatch should handle these scenarios:

| Scenario | Detection | Behavior |
|----------|-----------|----------|
| Invalid JSON in request | JSON decode failure | Return 400 with `{"error":"Invalid request body"}` |
| Missing required fields | Field validation | Return 400 with `{"error":"Missing required field: {field}"}` |
| Directory creation fails | FileManager error | Return 500 with `{"error":"Failed to create directory"}` |
| Run ID not found (on complete) | UUID lookup fails | Return 404 with `{"error":"Run not found"}` |
| Disk full | Write failure | Return 500 with `{"error":"Disk full or write failed"}` |

### Graceful Degradation Protocol

When Dispatch is unavailable, skills should:

1. **Detect early:** Check health endpoint at start of test session (not per-screenshot)
2. **Fallback immediately:** Don't retry Dispatch if initial health check fails
3. **Use consistent fallback path:** `.screenshots/{project}/{timestamp}/` in project root
4. **Log clearly:** "Dispatch not available, screenshots saved to {path}"
5. **Continue normally:** Test execution should not be blocked by Dispatch availability

## API Contract Summary

### Existing Endpoints (Verified Working)

```
GET /health
Response: {"status":"ok"}

GET /screenshots/location?project={name}
Response: {"path":"/absolute/path/to/project/screenshots"}

POST /screenshots/run
Body: {"project":"AppName", "name":"Run Label", "device":"iPhone 15 Pro"}
Response: {"runId":"UUID", "path":"/absolute/path/to/run/directory"}

POST /screenshots/complete
Body: {"runId":"UUID"}
Response: {"completed":true}
```

### Response Format Conventions

- All responses are JSON with `Content-Type: application/json`
- Success responses have the requested data at root level
- Error responses have `{"error":"Human-readable message"}`
- HTTP status codes: 200 (success), 400 (bad request), 404 (not found), 500 (server error)
- Paths in responses are always absolute, not relative
- UUIDs are uppercase strings (Swift's default `UUID().uuidString` format)

## Sources

- Existing codebase: `/Users/eric/Dispatch/Dispatch/Services/HookServer.swift`
- Existing codebase: `/Users/eric/Dispatch/Dispatch/Services/ScreenshotWatcherService.swift`
- Skill implementations: `~/.claude/skills/qa-feature/SKILL.md`, `~/.claude/skills/explore-app/SKILL.md`, `~/.claude/skills/test-feature/SKILL.md`
- SwiftData models: `/Users/eric/Dispatch/Dispatch/Models/SimulatorRun.swift`, `/Users/eric/Dispatch/Dispatch/Models/Screenshot.swift`

---
*Feature research for: Skill to Dispatch screenshot integration*
*Researched: 2026-02-03*

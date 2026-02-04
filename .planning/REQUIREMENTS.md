# Requirements: Dispatch v1.1

**Defined:** 2026-02-03
**Core Value:** Users can dispatch prompts (including annotated simulator screenshots) to Claude Code with zero friction

## v1.1 Requirements

Requirements for milestone v1.1 Screenshot Integration Fix. Each maps to roadmap phases.

### Foundation (Shared Library)

- [x] **FNDTN-01**: Create shared bash library at `~/.claude/lib/dispatch.sh` with Dispatch integration functions
- [x] **FNDTN-02**: Library provides `dispatch_init` function to check Dispatch availability and create screenshot run
- [x] **FNDTN-03**: Library provides `dispatch_finalize` function to mark run complete with proper delay
- [x] **FNDTN-04**: Library uses temp files (`/tmp/dispatch-*.txt`) for state persistence between bash calls
- [x] **FNDTN-05**: Library provides graceful fallback path when Dispatch not running with clear output message
- [x] **FNDTN-06**: Library derives project name from git root, not current directory

### Hook Integration

- [ ] **HOOK-01**: Create SessionStart hook at `~/.claude/hooks/session-start.sh` for early Dispatch detection
- [ ] **HOOK-02**: SessionStart hook sets environment variables via `CLAUDE_ENV_FILE` for session-wide access
- [ ] **HOOK-03**: Hook performs health check against Dispatch API at session start

### Dispatch App Updates

- [ ] **APP-01**: HookInstaller auto-installs shared library to `~/.claude/lib/dispatch.sh`
- [ ] **APP-02**: HookInstaller updates library on Dispatch version upgrade
- [ ] **APP-03**: HookInstaller installs SessionStart hook for Dispatch detection

### Skill Migration

- [ ] **SKILL-01**: Audit all skills in `~/.claude/skills/` to identify which take screenshots
- [ ] **SKILL-02**: Update `test-feature` skill to source shared library instead of inline integration
- [ ] **SKILL-03**: Update `explore-app` skill to source shared library
- [ ] **SKILL-04**: Update `test-dynamic-type` skill to source shared library
- [ ] **SKILL-05**: Update all other screenshot-taking skills to source shared library
- [ ] **SKILL-06**: Remove duplicated Dispatch integration code from all migrated skills

### Verification

- [ ] **VERIFY-01**: End-to-end test: skill captures screenshots, appear in Dispatch UI
- [ ] **VERIFY-02**: Test graceful degradation when Dispatch not running
- [ ] **VERIFY-03**: Test screenshot routing from at least 3 different skills
- [ ] **VERIFY-04**: Update skill documentation with new integration pattern

### Polish (Settings & UI)

- [ ] **POLISH-01**: Add Settings UI section for screenshot configuration (directory, max runs)
- [ ] **POLISH-02**: Add tooltip hints for annotation tools in Annotation Window
- [ ] **POLISH-03**: Display user-visible error when dispatch fails (not just log)
- [ ] **POLISH-04**: Show integration status indicator in Dispatch UI (library installed, hook active)

## Future Requirements

Deferred to v1.2 or later.

### Enhanced API

- **API-01**: Screenshot labels via API — POST `/screenshots/{id}/label` during capture
- **API-02**: Bulk screenshot registration — POST `/screenshots/bulk` to reduce race conditions
- **API-03**: Run status query — GET `/screenshots/run/{id}` for verification

### Deferred Polish

- **POLISH-05**: Drag to reorder images in send queue
- **POLISH-06**: Auto-focus prompt text field when annotation window opens
- **POLISH-07**: PromptHistory entries include image references
- **POLISH-08**: Auto-resize large images before dispatch

## Out of Scope

Explicitly excluded. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| Automatic screenshot capture | Too noisy; skills know when to capture |
| Screenshot diff/comparison | Complex ML, many false positives; separate tool |
| Direct file upload to API | Path-based approach simpler and more reliable |
| Bidirectional skill communication | Breaks skill execution flow |
| In-app screenshot editing | macOS Preview handles this; focus on organization |
| WebSocket notifications | Overkill for current scale |
| Video recording | High complexity, out of scope |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| FNDTN-01 | Phase 8 | Complete |
| FNDTN-02 | Phase 8 | Complete |
| FNDTN-03 | Phase 8 | Complete |
| FNDTN-04 | Phase 8 | Complete |
| FNDTN-05 | Phase 8 | Complete |
| FNDTN-06 | Phase 8 | Complete |
| HOOK-01 | Phase 9 | Pending |
| HOOK-02 | Phase 9 | Pending |
| HOOK-03 | Phase 9 | Pending |
| APP-01 | Phase 10 | Pending |
| APP-02 | Phase 10 | Pending |
| APP-03 | Phase 10 | Pending |
| SKILL-01 | Phase 11 | Pending |
| SKILL-02 | Phase 11 | Pending |
| SKILL-03 | Phase 11 | Pending |
| SKILL-04 | Phase 11 | Pending |
| SKILL-05 | Phase 11 | Pending |
| SKILL-06 | Phase 11 | Pending |
| VERIFY-01 | Phase 12 | Pending |
| VERIFY-02 | Phase 12 | Pending |
| VERIFY-03 | Phase 12 | Pending |
| VERIFY-04 | Phase 12 | Pending |
| POLISH-01 | Phase 13 | Pending |
| POLISH-02 | Phase 13 | Pending |
| POLISH-03 | Phase 13 | Pending |
| POLISH-04 | Phase 13 | Pending |

**Coverage:**
- v1.1 requirements: 26 total
- Mapped to phases: 26
- Unmapped: 0

---
*Requirements defined: 2026-02-03*
*Last updated: 2026-02-03 after roadmap creation*

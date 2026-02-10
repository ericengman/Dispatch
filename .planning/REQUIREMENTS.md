# Requirements: Dispatch

**Defined:** 2026-02-09
**Core Value:** Users can dispatch prompts (including annotated screenshots) to Claude Code with zero friction

## v3.0 Requirements

Requirements for Screenshot Capture milestone. Each maps to roadmap phases.

### Capture Modes

- [x] **CAPT-01**: User can invoke cross-hair region selection via native macOS screencapture
- [x] **CAPT-02**: User can select and capture any window via interactive hover-highlight
- [x] **CAPT-03**: User sees iOS Simulator windows prominently (system UI filtered out)
- [x] **CAPT-04**: User can re-capture recently captured windows from MRU list

### Annotation Pipeline

- [x] **ANNOT-01**: Captured screenshot opens directly in annotation UI for markup
- [x] **ANNOT-02**: User can queue multiple screenshots before dispatching
- [x] **ANNOT-03**: User can select which Claude session receives the dispatched screenshot

### UI Integration

- [x] **UI-01**: Quick Capture section appears in sidebar with capture action buttons
- [ ] **UI-02**: User can trigger capture modes via keyboard shortcuts
- [ ] **UI-03**: User sees live thumbnail previews of capturable windows in picker
- [x] **UI-04**: User sees recent captures strip showing last few captures in sidebar

## Future Requirements

Deferred to post-v3.0 release. Tracked but not in current roadmap.

### Polish

- **POLISH-01**: Timer/delayed capture (3-5 second countdown)
- **POLISH-02**: Quick capture mode (skip annotation, direct to clipboard/dispatch)
- **POLISH-03**: Fullscreen display capture

## Out of Scope

Explicitly excluded. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| OCR/text extraction | Claude IS the OCR - sending screenshot to Claude extracts text better than local OCR |
| Video/GIF recording | Scope creep - Dispatch is for static screenshots to Claude |
| Scrolling capture | High complexity - Claude can handle multiple screenshots |
| Cloud upload/sharing | Dispatch sends to Claude, not to the internet - privacy concern |
| Background beautification | Screenshots are for debugging/development, not social media |
| Color picker/measurements | Designer tools, not debugging tools - use Shottr for this |
| Custom cross-hair selection UI | Native screencapture -i provides this for free with perfect UX |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| CAPT-01 | Phase 23 | Complete |
| CAPT-02 | Phase 24 | Complete |
| CAPT-03 | Phase 24 | Complete |
| CAPT-04 | Phase 26 | Complete |
| ANNOT-01 | Phase 25 | Complete |
| ANNOT-02 | Phase 25 | Complete |
| ANNOT-03 | Phase 25 | Complete |
| UI-01 | Phase 26 | Complete |
| UI-02 | Phase 27 | Pending |
| UI-03 | Phase 26 | Pending |
| UI-04 | Phase 26 | Complete |

**Coverage:**
- v3.0 requirements: 11 total
- Mapped to phases: 11
- Unmapped: 0

---
*Requirements defined: 2026-02-09*
*Last updated: 2026-02-10 after Phase 26 completion*

# Pitfalls Research

**Domain:** Skill to App Integration (Screenshot Routing)
**Researched:** 2026-02-03
**Confidence:** HIGH

## Critical Pitfalls

### Pitfall 1: Skills Don't Remember State Between Bash Calls

**What goes wrong:**
Skills instruct Claude Code to run bash commands, but Claude Code's shell state resets between calls. Variables set in one bash block (like `DISPATCH_RUN_ID` or `DISPATCH_SCREENSHOT_PATH`) are lost before the next block executes.

**Why it happens:**
Skills are markdown files that instruct Claude Code - they're not actual programs. Claude Code executes bash commands in separate subshells. Developers write skill documentation assuming persistent shell state, but each `bash` block in the skill is a new invocation.

**How to avoid:**
1. Write values to temp files instead of environment variables:
   ```bash
   # Store in temp file
   echo "$DISPATCH_RUN_ID" > /tmp/dispatch-current-run-id
   echo "$DISPATCH_SCREENSHOT_PATH" > /tmp/dispatch-screenshot-path

   # Read in later block
   DISPATCH_RUN_ID=$(cat /tmp/dispatch-current-run-id)
   DISPATCH_SCREENSHOT_PATH=$(cat /tmp/dispatch-screenshot-path)
   ```
2. Use consistent temp file locations documented in skill
3. Clean up temp files in Phase 8 (cleanup phase)

**Warning signs:**
- Skill executes Dispatch API calls but screenshots go to wrong location
- `DISPATCH_SCREENSHOT_PATH` appears empty in later phases
- "Variable not set" errors in bash output

**Phase to address:**
Phase 1 (API Contract) - Define temp file storage pattern as part of the skill contract

---

### Pitfall 2: Dispatch Not Running - Silent Failure

**What goes wrong:**
Skills check `curl localhost:19847/health` and silently fall back to default behavior, but then later phases assume Dispatch IS running. Screenshots end up in random locations, run completion never fires, Dispatch UI shows nothing.

**Why it happens:**
The graceful fallback pattern in existing skills sets `DISPATCH_RUN_ID=""` on failure but subsequent phases don't consistently check this before calling Dispatch APIs. Also, Claude Code may not notice the fallback happened because the skill doesn't clearly communicate it.

**How to avoid:**
1. Make fallback explicit and visible:
   ```bash
   if echo "$DISPATCH_HEALTH" | grep -q '"status":"ok"'; then
       DISPATCH_MODE="active"
       # ... create run ...
   else
       DISPATCH_MODE="fallback"
       echo "WARNING: Dispatch not running - screenshots will use /tmp/skill-screenshots/"
       DISPATCH_SCREENSHOT_PATH="/tmp/skill-screenshots/$(date +%Y%m%d-%H%M%S)"
       mkdir -p "$DISPATCH_SCREENSHOT_PATH"
   fi
   # Store mode for later checks
   echo "$DISPATCH_MODE" > /tmp/dispatch-mode
   ```
2. Check mode before calling Dispatch-specific APIs in later phases
3. Provide user notification if in fallback mode

**Warning signs:**
- Screenshots exist in `/tmp/` or `.screenshots/` but not in Dispatch
- Dispatch shows no runs for the project
- `POST /screenshots/complete` errors in logs

**Phase to address:**
Phase 1 (API Contract) - Define clear fallback behavior with user notification

---

### Pitfall 3: Inconsistent Screenshot Path Usage Across Skills

**What goes wrong:**
Some skills save to `$DISPATCH_SCREENSHOT_PATH/{name}.png`, others to `.screenshots/`, others to absolute paths. When migrating skills, some get updated correctly, others are missed. Result: screenshots scattered across filesystem.

**Why it happens:**
- 39 skill files exist (from grep results)
- Only 4 currently have Dispatch integration
- Different developers wrote different skills with different conventions
- No centralized "screenshot saving" pattern

**How to avoid:**
1. Create a canonical helper pattern:
   ```bash
   # save_screenshot.sh - Source this in all skills
   save_screenshot() {
       local NAME="$1"
       local UUID="${2:-}"

       # Get path from temp file (set during Phase 1)
       local PATH=$(cat /tmp/dispatch-screenshot-path 2>/dev/null)

       if [[ -z "$PATH" ]]; then
           PATH="/tmp/skill-screenshots"
           mkdir -p "$PATH"
       fi

       if [[ -n "$UUID" ]]; then
           idb screenshot --udid "$UUID" "${PATH}/${NAME}.png"
       else
           # MCP tool variant
           echo "Use mcp__ios-simulator__screenshot with output_path: ${PATH}/${NAME}.png"
       fi
   }
   ```
2. Add helper to `helpers.sh` in `create-parallel-test-skill`
3. Update all skills to use the helper

**Warning signs:**
- Different skills produce screenshots in different locations
- Some skills work with Dispatch, others don't
- Screenshots can't be found after skill runs

**Phase to address:**
Phase 2 (Skill Updates) - Implement helper pattern, then update all skills consistently

---

### Pitfall 4: Race Condition Between Screenshot Save and Run Completion

**What goes wrong:**
Skill calls `POST /screenshots/complete` immediately after the last screenshot, but filesystem operations are async. Dispatch scans the directory before screenshots are fully flushed to disk. Result: Dispatch shows incomplete run.

**Why it happens:**
- Screenshot tools return "success" before file is fully written
- File system caching may delay writes
- Dispatch `scanForNewRuns()` runs immediately on completion API call

**How to avoid:**
1. Add delay before completion:
   ```bash
   # Wait for filesystem to flush
   sleep 1

   # Then mark complete
   curl -s -X POST http://localhost:19847/screenshots/complete \
     -H "Content-Type: application/json" \
     -d "{\"runId\":\"$DISPATCH_RUN_ID\"}"
   ```
2. Or verify screenshots exist before completing:
   ```bash
   # Count expected screenshots
   EXPECTED_COUNT=5
   ACTUAL_COUNT=$(ls -1 "$DISPATCH_SCREENSHOT_PATH"/*.png 2>/dev/null | wc -l)

   if [[ $ACTUAL_COUNT -lt $EXPECTED_COUNT ]]; then
       echo "WARNING: Expected $EXPECTED_COUNT screenshots, found $ACTUAL_COUNT"
       sleep 2  # Extra wait
   fi
   ```

**Warning signs:**
- Dispatch shows fewer screenshots than skill reported taking
- Screenshots appear in folder after Dispatch scan completed
- "0 screenshots" shown for runs that definitely took screenshots

**Phase to address:**
Phase 1 (API Contract) - Document required delay, or implement polling in Dispatch

---

### Pitfall 5: Project Name Mismatch Between Skill and Dispatch

**What goes wrong:**
Skill uses `$(basename "$(pwd)")` for project name, but user ran skill from subdirectory. Or project name has special characters that get mangled. Dispatch creates run under wrong/unexpected project.

**Why it happens:**
- `pwd` is unreliable - depends on where Claude Code was invoked
- Project names can contain spaces, special chars
- No validation of project name in API

**How to avoid:**
1. Use git root instead of pwd:
   ```bash
   PROJECT_NAME=$(basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")
   ```
2. Sanitize project name:
   ```bash
   PROJECT_NAME=$(echo "$PROJECT_NAME" | tr -cd '[:alnum:]_-')
   ```
3. Or let Dispatch derive project name from other sources (e.g., Xcode project file)

**Warning signs:**
- Dispatch shows runs under project names like "src" or "features"
- Multiple projects with similar names
- Can't find runs for expected project

**Phase to address:**
Phase 1 (API Contract) - Document project name derivation, or add validation

---

### Pitfall 6: Forgetting to Update Skills After API Changes

**What goes wrong:**
Dispatch API evolves (new fields, renamed endpoints, changed response format), but skills reference old API. Skills break silently because curl calls still "succeed" but Dispatch ignores malformed requests.

**Why it happens:**
- 39 skill files, only a few actively maintained
- No automated testing of skill -> Dispatch integration
- API changes in Dispatch don't automatically update skills

**How to avoid:**
1. Version the API and require version header:
   ```bash
   curl -X POST http://localhost:19847/screenshots/run \
     -H "Content-Type: application/json" \
     -H "X-Dispatch-API-Version: 1" \
     -d '...'
   ```
2. Return clear errors for deprecated/malformed requests
3. Keep API changelog that maps skill versions to API versions
4. Create a skill update checklist when API changes

**Warning signs:**
- Skills that "used to work" stop working after Dispatch update
- `{"error":"..."}` responses from Dispatch that skills ignore
- Missing required fields in API calls

**Phase to address:**
Phase 1 (API Contract) - Define versioning strategy upfront

---

## Technical Debt Patterns

Shortcuts that seem reasonable but create long-term problems.

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Copy-paste Dispatch integration into each skill | Quick to implement | 39 places to update when API changes | Never - use shared helper |
| Ignore Dispatch health check result | Skill runs without errors | Screenshots lost, user confused | MVP only - fix in Phase 2 |
| Hardcode port 19847 in skills | Simple | Can't run multiple Dispatch instances, port conflicts | Acceptable if documented |
| Store run ID in bash variable | Simple | Lost between bash blocks | Never - use temp file |
| Skip `sleep` before completion | Faster skill execution | Race condition with scan | Never - always sleep 1s |

## Integration Gotchas

Common mistakes when connecting to external services.

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| Dispatch Health Check | Only check once at start | Check before each API call, or at least before completion |
| Screenshot Path | Use relative path | Always use absolute path from Dispatch response |
| Run Completion | Fire and forget | Verify response, retry on failure |
| JSON Parsing | Use grep/sed/cut | Use `jq` or proper JSON parsing |
| Error Handling | Ignore curl errors | Check exit code and response body |

## Performance Traps

Patterns that work at small scale but fail as usage grows.

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Scanning all screenshots on every completion | Slow UI response | Index only new run directory | >100 screenshots |
| Not cleaning up old runs | Disk fills up | Enforce maxRunsPerProject | >1000 runs |
| Synchronous screenshot saves | Skill blocks | Use async/background save | >10 screenshots/run |
| Polling for screenshots | CPU usage | Use file system events | Continuous usage |

## Security Mistakes

Domain-specific security issues beyond general web security.

| Mistake | Risk | Prevention |
|---------|------|------------|
| Skills can read any file path | Information disclosure | Validate paths are under screenshot directory |
| No auth on Dispatch API | Any local process can inject | Acceptable for localhost-only, document limitation |
| Screenshot paths can contain `..` | Path traversal | Sanitize paths in Dispatch |

## UX Pitfalls

Common user experience mistakes in this domain.

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| Silent fallback to non-Dispatch mode | User thinks Dispatch is broken | Explicit notification in skill output |
| Screenshots in unexpected location | User can't find results | Always output final screenshot path |
| Run created but never completed | "Incomplete" runs clutter UI | Auto-complete after timeout |
| Project names don't match expectations | Can't find runs | Show project name in skill output |
| No feedback during long screenshot captures | User thinks skill is stuck | Progress output for each screenshot |

## "Looks Done But Isn't" Checklist

Things that appear complete but are missing critical pieces.

- [ ] **Skill updated:** Does it use temp files for state instead of env vars?
- [ ] **Skill updated:** Does it check Dispatch mode before calling APIs?
- [ ] **Skill updated:** Does it sleep before calling completion?
- [ ] **Helper shared:** Is screenshot save pattern in helpers.sh?
- [ ] **All skills:** Have ALL 39 skills been reviewed for screenshot usage?
- [ ] **Dispatch API:** Does it handle malformed requests gracefully?
- [ ] **Dispatch scan:** Does it handle filesystem race conditions?
- [ ] **User notification:** Does skill output where screenshots went?

## Recovery Strategies

When pitfalls occur despite prevention, how to recover.

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Screenshots in wrong location | LOW | Find screenshots manually, move to Dispatch directory |
| Run never completed | LOW | Delete incomplete run, re-run skill |
| State lost between bash blocks | MEDIUM | Update skill, re-run |
| API version mismatch | MEDIUM | Update skill to match current API |
| Project name mismatch | LOW | Rename in Dispatch UI or re-run with correct pwd |
| Race condition lost screenshots | LOW | Re-run skill with added delay |

## Pitfall-to-Phase Mapping

How roadmap phases should address these pitfalls.

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| State lost between bash blocks | Phase 1 (API Contract) | Test skill with multi-phase execution |
| Dispatch not running fallback | Phase 1 (API Contract) | Test with Dispatch stopped |
| Inconsistent screenshot paths | Phase 2 (Skill Updates) | Audit all 39 skills |
| Race condition on completion | Phase 1 (API Contract) | Test rapid screenshot + complete |
| Project name mismatch | Phase 1 (API Contract) | Test from subdirectory |
| API version mismatch | Phase 1 (API Contract) | Document versioning strategy |

## Sources

- Analysis of existing skill files in `/Users/eric/.claude/skills/`
- Review of `test-feature/SKILL.md`, `qa-feature/SKILL.md`, `explore-app/SKILL.md` Dispatch integration
- Review of `HookServer.swift` and `ScreenshotWatcherService.swift` in Dispatch
- Review of `create-parallel-test-skill/helpers.sh` helper pattern
- Analysis of skill execution model (Claude Code bash state behavior)
- Personal experience with multi-skill ecosystems and integration maintenance

---
*Pitfalls research for: Skill to App Integration (Screenshot Routing)*
*Researched: 2026-02-03*

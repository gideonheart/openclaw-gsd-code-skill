---
phase: 01-cleanup
plan: 02
subsystem: infra
tags: [node, esm, tmux, registry, config, launcher]

# Dependency graph
requires:
  - phase: 01-01
    provides: Clean repository with zero v1-v3 artifacts, bin/ directory established
provides:
  - config/agent-registry.json with v4.0 simplified schema (agents array, no hook_settings)
  - config/agent-registry.example.json with documented example entries
  - bin/launch-session.mjs ESM session launcher reading agent-registry.json
  - package.json declaring gsd-code-skill as ESM (type:module) with no dependencies
  - Updated .gitignore referencing agent-registry.json
affects: [02-stop-event, 03-notification-event, 04-session-end-event, 05-pre-post-tool-use-event]

# Tech tracking
tech-stack:
  added:
    - Node.js ESM (import.meta.url, fileURLToPath, node:fs, node:path, node:child_process)
  patterns:
    - "package.json with type:module establishes ESM as the module system for all .mjs files"
    - "import.meta.url + fileURLToPath for script-relative path resolution in ESM"
    - "config/ files: .json for secrets (gitignored), .example.json for documentation (committed)"
    - "execSync for tmux automation from Node.js — wrap each tmux command in its own function"

key-files:
  created:
    - bin/launch-session.mjs
    - config/agent-registry.example.json
  modified:
    - .gitignore
    - config/agent-registry.json (regenerated with v4.0 schema)
    - config/default-system-prompt.md (renamed from .txt)

key-decisions:
  - "v4.0 agent-registry schema: top-level {agents:[]} only — no hook_settings, no global_status_* fields"
  - "system_prompt_file as file reference (not inline string) — agents share config/default-system-prompt.md"
  - "launch-session.mjs exits 0 if session already exists (idempotent) rather than erroring"
  - "disabled agents throw error on launch attempt — fail loudly rather than silently skipping"
  - "system_prompt_file extension updated to .md to match actual file on disk"

patterns-established:
  - "ESM launchers: use import.meta.url + dirname(fileURLToPath()) for SKILL_ROOT resolution"
  - "All Node.js scripts in bin/: self-explanatory naming, no abbreviations, logWithTimestamp() pattern"
  - "Registry pattern: .json gitignored (secrets), .example.json committed (documentation)"

requirements-completed: [CLEAN-08]

# Metrics
duration: 3min
completed: 2026-02-19
---

# Phase 1 Plan 2: Cleanup Summary

**v4.0 agent-registry.json with simplified schema, bin/launch-session.mjs ESM tmux launcher, and package.json establishing Node.js ESM as the module system**

## Performance

- **Duration:** 3 min
- **Started:** 2026-02-19T22:58:23Z
- **Completed:** 2026-02-19T23:01:23Z
- **Tasks:** 2
- **Files modified:** 3 modified, 3 created, 2 deleted

## Accomplishments

- Replaced recovery-registry.json with agent-registry.json using the v4.0 simplified schema (6 fields per agent, no hook_settings, no global_status_* fields)
- Created config/agent-registry.example.json with 2 documented example agents showing every field with comments
- Created bin/launch-session.mjs: full ESM Node.js session launcher (191 lines) that reads agent-registry.json, creates tmux session, starts Claude Code with system prompt, optionally sends first command
- Updated .gitignore to reference agent-registry.json (not recovery-registry.json), removed lock file entry
- package.json already existed with correct content (type:module, version 4.0.0, no dependencies)

## Task Commits

Each task was committed atomically:

1. **Task 1: Rename registry to agent-registry with v4.0 schema and update .gitignore** - `910bf1b` (chore)
2. **Task 2: Create package.json and session launcher** - `1b349ac` (feat)

**Plan metadata:** (docs commit follows)

## Files Created/Modified

- `config/agent-registry.json` - v4.0 agent registry with 2 agents (forge, warden); simplified schema with agent_id, enabled, session_name, working_directory, openclaw_session_id, system_prompt_file
- `config/agent-registry.example.json` - Example registry with 2 agents (gideon, warden) and field-level _comment documentation
- `config/default-system-prompt.md` - Renamed from .txt (content unchanged; pre-existing filesystem state)
- `.gitignore` - Updated to reference agent-registry.json, removed recovery-registry.json and lock file entries, added explanatory comments
- `bin/launch-session.mjs` - ESM session launcher: parses CLI args, reads registry, finds agent, creates tmux session, launches Claude Code, sends optional first command; self-explanatory naming throughout

## Decisions Made

- v4.0 agent-registry schema drops all v1-v3 fields: auto_wake, topic_id, claude_resume_target, claude_launch_command, claude_post_launch_mode, system_prompt (inline), hook_settings, and top-level global_status_* fields
- system_prompt_file as a file reference rather than inline string — future agents can have custom prompts by pointing to different files
- launch-session.mjs exits 0 (not error) when session already exists — idempotent behavior allows safe re-invocation
- Disabled agents (enabled: false) throw an explicit error on launch attempt — loud failure is safer than silent skip
- system_prompt_file references .md extension to match actual file on disk (default-system-prompt.txt was renamed to .md as a pre-existing state)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Updated system_prompt_file extension from .txt to .md**
- **Found during:** Task 1 (registry creation)
- **Issue:** config/default-system-prompt.txt was renamed to config/default-system-prompt.md on disk before this plan ran; referencing .txt would cause launch-session.mjs to fail at runtime
- **Fix:** Set system_prompt_file to "config/default-system-prompt.md" in both agent-registry.json and agent-registry.example.json; staged the rename in git
- **Files modified:** config/agent-registry.json, config/agent-registry.example.json, config/default-system-prompt.md (git rename of .txt)
- **Verification:** File exists on disk, verified by ls; launcher would resolve it correctly
- **Committed in:** 910bf1b (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (Rule 1 - pre-existing file rename)
**Impact on plan:** Necessary for correctness — launcher would have thrown at runtime without the fix. No scope creep.

## Issues Encountered

- Node.js v22 on this system runs node -e scripts as TypeScript and escapes `!` in the shell, causing `!==` comparisons in inline node -e snippets to fail with SyntaxError. Worked around by writing verification as temporary .mjs script files and running them via `node script.mjs`.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- v4.0 agent-registry.json schema is established and gitignored
- bin/launch-session.mjs provides the session launcher replacing spawn.sh
- package.json declares ESM — all future .mjs handlers in events/ and lib/ will work without configuration
- Phase 2 (Shared Library) can now build lib/ utilities that import each other as ESM modules
- Ready for Phase 2 (Shared Library) immediately

## Self-Check: PASSED

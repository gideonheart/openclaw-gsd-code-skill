# Phase 1: Cleanup - Context

**Gathered:** 2026-02-19
**Status:** Ready for planning

<domain>
## Phase Boundary

Delete all v1-v3 hook artifacts (scripts, lib, prompts, docs, tests, systemd) and rename recovery-registry to agent-registry. Create a clean slate for v4.0 event-driven architecture. Includes a fresh Node.js session launcher (replacing spawn.sh) and minimal package.json to declare the project as ESM.

</domain>

<decisions>
## Implementation Decisions

### What gets deleted
- All seven old hook bash scripts (stop-hook.sh, pre-tool-use-hook.sh, post-tool-use-hook.sh, pre-compact-hook.sh, notification-idle-hook.sh, notification-permission-hook.sh, session-end-hook.sh)
- The entire scripts/ directory (including prompts/ subdirectory, menu-driver.sh, diagnose-hooks.sh, register-hooks.sh, register-all-hooks-logger.sh, sync-recovery-registry-session-ids.sh, recover-openclaw-agents.sh, test-hook-prompts.sh, install.sh, spawn.sh)
- lib/hook-preamble.sh and lib/hook-utils.sh (entire old lib contents)
- PRD.md at project root
- docs/v3-retrospective.md and docs/hooks.md (contents of docs/)
- tests/test-deliver-async-with-logging.sh and tests/test-write-hook-event-record.sh (contents of tests/)
- systemd/ directory entirely
- config/recovery-registry.json.lock (no lock file in v4.0)

### What survives (with modifications)
- hook-event-logger.sh — kept as-is (bash), relocated to new directory structure. Claude evaluates if internal references need cleanup but it currently works
- config/default-system-prompt.txt — kept as shared fallback prompt. Agents reference this file rather than inlining prompts in JSON
- config/ directory — survives with renamed registry files
- SKILL.md — stripped to skeleton with valid YAML frontmatter updated for v4.0, brief architecture overview
- README.md — stripped to skeleton with brief v4.0 architecture overview
- docs/ — kept as empty directory (placeholder for v4.0 docs)
- tests/ — kept as empty directory (placeholder for v4.0 tests)
- logs/ — untouched (gitignored runtime data)
- .planning/ — untouched (project planning docs are historical record)

### Registry rename
- Full rename: recovery-registry.json -> agent-registry.json everywhere
- Rename config file, example file, .gitignore references
- .planning/ docs left as-is (historical record of the decision to rename)
- Schema improved during rename — Claude designs the v4.0 schema based on what event handlers need
- Agent entries should reference prompt files (alongside agent workspaces) instead of inlining system_prompt strings
- Default fallback: config/default-system-prompt.txt
- No lock file mechanism — v4.0 event-driven handlers don't need concurrent write protection
- Example file (agent-registry.example.json) updated to reflect new schema
- Global status fields: Claude evaluates whether needed in v4.0
- Agent entry fields: Claude simplifies to what event handlers actually need
- Config separation (agents vs hook settings): Claude decides based on v4.0 architecture

### Session launcher
- Fresh Node.js (.mjs) session launcher written from scratch (not a rewrite of spawn.sh)
- Self-descriptive name (not "spawn")
- Location: Claude picks best-practice location for the v4.0 directory structure
- DRY, SRP, lean, self-explanatory variable and function names

### Module system
- ESM everywhere — all Node.js files use .mjs extension
- Minimal package.json created in Phase 1 (name, version, type:module)

### Directory structure
- Claude designs the optimal v4.0 directory structure based on best OpenClaw and Claude Code practices
- Key directories: bin/ (executables), lib/ (shared library), events/ (event handlers), config/ (runtime config)
- Scaffolding approach: Claude decides whether to scaffold all dirs upfront or let them grow organically
- Directory naming convention: Claude decides (snake_case vs kebab-case) based on Claude Code hook system alignment
- File naming convention for .mjs: Claude decides what's most consistent

### Hook registration (architectural note for Phase 5)
- Registration script should auto-detect hooks from events/ folder structure — no manual manifest to maintain
- Convention-based discovery over configuration

### Claude's Discretion
- Optimal post-cleanup directory structure (improve on what existed before)
- Agent-registry.json schema design for v4.0 event handlers
- Which agent entry fields to keep vs remove
- Whether to separate agent config from hook/event config
- Global status fields retention
- Logger cleanup (scrub dead references or leave working as-is)
- Scaffolding strategy (upfront skeleton vs organic growth)
- Directory naming convention (match Claude Code hook events)
- File naming convention for .mjs files
- Session launcher name and location

</decisions>

<specifics>
## Specific Ideas

- "We do not want files with wrong patterns, lets start fresh" — user explicitly wants clean slate, not incremental fixes
- "Remember all code needs to be DRY, SRP, best OpenClaw and Claude code practices, and no legacy or dead code or unused functions, all variable names and function names should be self-explanatory"
- "Think of what you would do better than before knowing all you know now" — Claude should leverage v1-v3 learnings to design a better structure
- Agent system prompts should link to files (alongside agent workspaces), not inline in config — keeps config lean
- Registration script (Phase 5) should scan folder structure to discover hooks automatically — convention over configuration
- ESM (.mjs) is the clear default in 2026 — user specifically chose this over CJS

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope. All architectural notes for later phases (shared lib design, registration auto-discovery) are captured as informational context, not Phase 1 work items.

</deferred>

---

*Phase: 01-cleanup*
*Context gathered: 2026-02-19*

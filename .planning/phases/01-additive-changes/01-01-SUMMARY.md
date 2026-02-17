---
phase: 01-additive-changes
plan: 01
subsystem: configuration
tags: [foundation, schema, registry, config, menu-driver]
requires: []
provides: [CONFIG-01, CONFIG-02, CONFIG-04, CONFIG-05, CONFIG-06, CONFIG-07, CONFIG-08, MENU-01]
affects: [recovery-registry, hook-scripts, spawn-script]
tech_stack:
  added: []
  patterns: [three-tier-fallback, per-field-merge, append-only-prompts]
key_files:
  created:
    - config/default-system-prompt.txt
  modified:
    - config/recovery-registry.example.json
    - scripts/menu-driver.sh
decisions:
  - decision: "Use comment fields in JSON for schema documentation"
    rationale: "JSON doesn't support comments, but _comment_* fields provide in-file documentation"
    impact: "Self-documenting registry schema without external docs"
  - decision: "Default system prompt focuses only on GSD workflow"
    rationale: "Role/personality comes from SOUL.md and AGENTS.md, prompt should be additive not prescriptive"
    impact: "Cleaner separation of concerns, minimal token overhead"
  - decision: "tmux send-keys -l flag for type action"
    rationale: "Prevents shell expansion of special characters in user input"
    impact: "Safe literal text input for wake messages and freeform responses"
metrics:
  duration_minutes: 1
  completed_date: 2026-02-17
  task_count: 2
  file_count: 3
  commits: 2
---

# Phase 01 Plan 01: Foundation Config and Schema Summary

**One-liner:** Established registry schema with hook_settings three-tier fallback, per-agent system prompts, and menu-driver type action for literal text input.

## What Was Built

Created the foundational configuration layer that all hook scripts depend on:

1. **Updated recovery-registry.example.json** with complete schema documentation:
   - Global `hook_settings` with 4 strict fields (pane_capture_lines, context_pressure_threshold, autocompact_pct, hook_mode)
   - Per-agent `system_prompt` field (appends to default-system-prompt.txt, never replaces)
   - Per-agent `hook_settings` overrides demonstrating three-tier fallback
   - Three realistic agents (Gideon, Warden, Forge) with different override patterns
   - Comment fields explaining append-only prompts and auto-populate defaults

2. **Created config/default-system-prompt.txt** with minimal GSD workflow guidance:
   - Documents GSD commands (/gsd:resume-work, /gsd:new-project, /gsd:help, /gsd:execute-plan, /gsd:research-phase)
   - Documents context management commands (/clear, /compact, /resume)
   - Pure workflow guidance, no role/personality content (16 lines total)

3. **Added type action to menu-driver.sh** for freeform text input:
   - Uses `tmux send-keys -l` flag for literal mode (no shell expansion)
   - Clears input line, sends text, presses Enter
   - Updated usage documentation

## Requirements Fulfilled

| Requirement | Status | Evidence |
|-------------|--------|----------|
| CONFIG-01 | ✓ | recovery-registry.example.json documents complete schema |
| CONFIG-02 | ✓ | Global hook_settings with 4 strict fields |
| CONFIG-04 | ✓ | Per-agent hook_settings overrides with three-tier fallback |
| CONFIG-05 | ✓ | Per-agent system_prompt field (append-only) |
| CONFIG-06 | ✓ | Three agents (Gideon, Warden, Forge) with different patterns |
| CONFIG-07 | ✓ | Comment field explains append-only system_prompt behavior |
| CONFIG-08 | ✓ | Comment field explains auto-populate hook_settings defaults |
| MENU-01 | ✓ | menu-driver.sh type action with -l flag |

## Must-Haves Verification

**Truths:**
- ✓ recovery-registry.example.json documents system_prompt field per agent and hook_settings nested object with all four strict fields
- ✓ recovery-registry.example.json shows global hook_settings at root level and per-agent overrides for three-tier fallback
- ✓ recovery-registry.example.json contains realistic multi-agent setup with Gideon, Warden, and Forge agents each with different hook_settings
- ✓ config/default-system-prompt.txt contains minimal GSD workflow guidance (slash commands) with no role/personality content
- ✓ menu-driver.sh type action sends literal freeform text via tmux send-keys -l without shell expansion

**Artifacts:**
- ✓ config/recovery-registry.example.json provides full schema documentation (contains "hook_settings")
- ✓ config/default-system-prompt.txt exists with 16 lines (min 5 required)
- ✓ scripts/menu-driver.sh contains "send-keys.*-l" pattern

**Key Links:**
- ✓ recovery-registry.example.json → recovery-registry.json (schema template with "hook_settings" pattern)
- ✓ default-system-prompt.txt → spawn.sh (will be read in Phase 3, pattern: "default-system-prompt")

## Deviations from Plan

None - plan executed exactly as written. All tasks completed without requiring auto-fixes, blocking issues, or architectural decisions.

## Commits

| Hash | Type | Description |
|------|------|-------------|
| 7cf662c | feat | Add complete registry schema with hook_settings and system_prompt |
| eeecdce | feat | Add default system prompt and type action to menu driver |

## Technical Notes

**Three-tier fallback implementation:**
- Each hook_settings field resolves independently through: per-agent > global > hardcoded
- Gideon: empty object `{}` (inherits all from global)
- Warden: overrides 2 fields (pane_capture_lines, hook_mode)
- Forge: overrides 1 field (context_pressure_threshold)

**System prompt composition:**
- Default prompt (config/default-system-prompt.txt): GSD workflow guidance
- Per-agent prompt (registry system_prompt field): Role/personality additive content
- Final prompt = default + per-agent (append, never replace)

**Menu driver type action:**
- `tmux send-keys -l` flag prevents expansion of $, `, \, and other shell metacharacters
- Enables safe freeform user input for wake messages and responses
- Added between choose and submit actions in case statement

## Next Steps

Phase 01 Plan 02 will implement the hook scripts that consume this schema (stop-hook.sh, notification hooks, session-end-hook.sh, pre-compact-hook.sh).

## Self-Check

Verifying all claimed files and commits exist.

**Files created:**
- config/default-system-prompt.txt: FOUND
- config/recovery-registry.example.json: FOUND (modified)
- scripts/menu-driver.sh: FOUND (modified)

**Commits:**
- 7cf662c: FOUND
- eeecdce: FOUND

## Self-Check: PASSED

All files exist, all commits verified, all must-haves satisfied.

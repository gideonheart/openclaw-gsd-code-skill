# Phase 4: Cleanup - Research

**Researched:** 2026-02-17
**Domain:** File deletion, reference cleanup, git operations
**Confidence:** HIGH

## Summary

Phase 4 is a focused cleanup operation to remove three obsolete polling scripts that have been replaced by the event-driven hook system implemented in Phases 1-3. The phase involves deleting git-tracked files (autoresponder.sh, hook-watcher.sh) and an untracked file (gsd-session-hook.sh), then systematically finding and fixing all dangling references across the codebase.

The user has explicitly chosen a minimal approach: use `git rm` for tracked files, simple `rm` for untracked files, no process termination (let old processes die naturally), no temp file cleanup (let them disappear on reboot), and comprehensive grep-based verification to ensure no broken references remain.

**Primary recommendation:** Execute deletions sequentially (tracked files first with `git rm`, then untracked file), immediately grep for all references to deleted script names, and fix stale references in-place with context-appropriate updates or removals.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Deletion method:**
- Use `git rm` for all git-tracked scripts (autoresponder.sh, hook-watcher.sh, gsd-session-hook.sh)
- Do NOT clean up /tmp watcher state files — let them disappear on reboot naturally
- No custom cleanup scripts for temp files

**Process termination:**
- Do NOT kill running hook-watcher or autoresponder processes
- Let old processes die naturally when their sessions end or on reboot
- No pkill commands in the cleanup phase

**Transition safety:**
- No pre-check that Phase 2+3 are complete — GSD enforces execution order
- If Phase 4 is running, prior phases are guaranteed done
- No verification scripts or dependency checks

**Post-cleanup verification:**
- Grep the codebase for any remaining references to deleted script names (autoresponder.sh, hook-watcher.sh, gsd-session-hook.sh)
- Fix stale references in-place — remove or update them, don't just log
- Complete cleanup: no broken pointers left behind after this phase

### Claude's Discretion

- Exact grep patterns for finding references
- Whether to update or remove stale references (context-dependent)
- Order of file deletions

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope

</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| CLEAN-01 | autoresponder.sh deleted | Git tracking confirmed; file exists at scripts/autoresponder.sh; use `git rm` for deletion |
| CLEAN-02 | hook-watcher.sh deleted | Git tracking confirmed; file exists at scripts/hook-watcher.sh; use `git rm` for deletion |
| CLEAN-03 | gsd-session-hook.sh deleted | File exists at /home/forge/.claude/hooks/gsd-session-hook.sh; NOT git-tracked in this repo; use `rm` for deletion |

</phase_requirements>

## Current State

### Files to Delete

**Git-tracked files in skill repo:**
1. `/home/forge/.openclaw/workspace/skills/gsd-code-skill/scripts/autoresponder.sh` (113 lines)
   - Purpose: 1s polling loop that auto-picks menu options
   - Replaced by: Event-driven hooks in Phase 1 + intelligent agent decisions

2. `/home/forge/.openclaw/workspace/skills/gsd-code-skill/scripts/hook-watcher.sh` (51 lines)
   - Purpose: 1s polling loop watching for menu prompts, broadcasts to all agents
   - Replaced by: stop-hook.sh and notification-idle-hook.sh in Phase 1

**Untracked file outside skill repo:**
3. `/home/forge/.claude/hooks/gsd-session-hook.sh` (33 lines)
   - Purpose: SessionStart hook that launched hook-watcher.sh for GSD sessions
   - Replaced by: Direct hook registration in settings.json (Phase 2)
   - Status: Already removed from settings.json in Phase 2 verification (criterion 6)
   - Location: Global Claude Code hooks directory (NOT in git repo)

### Reference Locations

**Documentation files with references (15 files):**
- `.planning/phases/04-cleanup/04-CONTEXT.md` - This phase's context (expected)
- `.planning/ROADMAP.md` - Success criteria mention scripts
- `.planning/REQUIREMENTS.md` - CLEAN-01, CLEAN-02, CLEAN-03 requirements
- `.planning/phases/02-hook-wiring/02-VERIFICATION.md` - Documents gsd-session-hook.sh removal from settings.json
- `.planning/phases/02-hook-wiring/02-01-SUMMARY.md` - Phase 2 summary
- `.planning/phases/02-hook-wiring/02-01-PLAN.md` - Phase 2 plan
- `.planning/phases/02-hook-wiring/02-RESEARCH.md` - Phase 2 research
- `.planning/phases/02-hook-wiring/02-CONTEXT.md` - Phase 2 context
- `.planning/phases/01-additive-changes/01-RESEARCH.md` - Phase 1 research
- `PRD.md` - Original requirements and architecture sections
- `.planning/quick/1-fix-prd-md-to-match-updated-project-goal/1-PLAN.md` - Quick fix plan
- `.planning/research/SUMMARY.md` - Research summary
- `.planning/research/FEATURES.md` - Feature descriptions
- `.planning/research/ARCHITECTURE.md` - Architecture documentation
- `.planning/research/STACK.md` - Stack documentation
- `.planning/research/PITFALLS.md` - Pitfall documentation
- `.planning/PROJECT.md` - Project overview
- `.planning/debug/resolved/warden-idle-and-code-audit.md` - Debug notes
- `SKILL.md` - Skill documentation (line 42: mentions --autoresponder flag)

**No references found in active scripts:**
- `scripts/spawn.sh` - NO references (already cleaned up in Phase 3)
- `scripts/recover-openclaw-agents.sh` - NO references (already cleaned up in Phase 3)

### Running Processes

User decision: Do NOT kill running processes. Let them die naturally.

Rationale from CONTEXT.md:
- Old hook-watcher and autoresponder processes will terminate when their sessions end
- System reboot will clear all /tmp state files naturally
- No need for aggressive cleanup — event-driven hooks already active for new sessions

## Standard Stack

### Core Tools

| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| git | 2.x | Version control operations | Native git commands for tracked file deletion |
| grep | GNU grep 3.x | Pattern matching for reference search | Standard POSIX text processing |
| bash | 5.x | Shell scripting | Project standard for all scripts |

### Supporting Tools

| Tool | Version | Purpose | When to Use |
|------|---------|---------|-------------|
| ripgrep (rg) | Latest | Fast recursive search | Available via Grep tool for reference finding |
| rm | coreutils | File deletion | Only for untracked files (gsd-session-hook.sh) |

### Operation Commands

**File deletion:**
```bash
# Git-tracked files (autoresponder.sh, hook-watcher.sh)
git rm scripts/autoresponder.sh
git rm scripts/hook-watcher.sh

# Untracked file (gsd-session-hook.sh)
rm /home/forge/.claude/hooks/gsd-session-hook.sh
```

**Reference search patterns:**
```bash
# Find all references to deleted scripts
grep -r "autoresponder\.sh" .
grep -r "hook-watcher\.sh" .
grep -r "gsd-session-hook\.sh" .

# More precise patterns (avoid partial matches)
grep -r "\bautoresponder\.sh\b" .
grep -r "\bhook-watcher\.sh\b" .
grep -r "\bgsd-session-hook\b" .
```

## Architecture Patterns

### Recommended Execution Order

```
1. Delete git-tracked files
   ├── git rm scripts/autoresponder.sh
   └── git rm scripts/hook-watcher.sh

2. Delete untracked file
   └── rm /home/forge/.claude/hooks/gsd-session-hook.sh

3. Search for references
   ├── Grep for autoresponder.sh references
   ├── Grep for hook-watcher.sh references
   └── Grep for gsd-session-hook references

4. Fix stale references
   ├── Planning docs: Keep historical context, update with "REMOVED in Phase 4" notes
   ├── PRD.md: Update architecture section, remove obsolete examples
   ├── SKILL.md: Remove --autoresponder flag from usage
   ├── README.md: Update if any references exist
   └── ROADMAP.md: Update Phase 4 success criteria once complete

5. Verify cleanup
   └── Re-run grep to confirm zero references in active code
```

### Reference Classification

**Historical documentation (keep with annotation):**
- Phase planning docs (01-RESEARCH.md, 02-CONTEXT.md, etc.) - These document what WAS replaced
- Migration rationale in PRD.md - Explains WHY hooks replaced polling
- Research pitfalls - Documents the OLD approach for learning

**Active documentation (update or remove):**
- SKILL.md - Remove --autoresponder flag, update architecture section
- README.md - Ensure no references to deleted scripts in current flow
- ROADMAP.md - Success criteria should reflect actual state after cleanup

**Code files (should have zero references):**
- scripts/*.sh - Already verified clean in spawn.sh and recover-openclaw-agents.sh
- config/*.json - No script references expected

### Pattern: In-Place Reference Fixes

**For historical documentation:**
```markdown
<!-- BEFORE -->
autoresponder.sh — 1s polling loop that picks option 1/recommended

<!-- AFTER -->
autoresponder.sh — REMOVED in Phase 4 (replaced by event-driven hooks)
```

**For active documentation:**
```markdown
<!-- BEFORE -->
- optional: `--autoresponder` starts local deterministic responder loop

<!-- AFTER -->
(remove entire line — flag no longer exists)
```

**For architecture sections:**
```markdown
<!-- BEFORE -->
Problems:
- Polling overhead: Two 1s polling loops per session (autoresponder, hook-watcher)

<!-- AFTER -->
Problems (SOLVED in v1.0):
- Polling overhead: Two 1s polling loops per session (replaced by event-driven hooks)
```

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Reference finding | Custom script parsing | Grep tool with regex patterns | Built-in, fast, reliable, handles all file types |
| File tracking status | Custom git parser | `git ls-files <path>` | Native git command, handles edge cases |
| In-place edits | sed scripts | Edit tool or manual review | Context-aware decisions needed |

**Key insight:** File deletion is trivial; reference cleanup requires judgment. Grep finds references; human decides whether to update, remove, or annotate based on document purpose.

## Common Pitfalls

### Pitfall 1: Deleting Files Before Finding References

**What goes wrong:** Once files are deleted, harder to understand what references meant.

**Why it happens:** Eagerness to "clean up" without documentation pass.

**How to avoid:** Delete first (files are in git history), but document what each script DID before grepping for references. This research document serves that purpose.

**Warning signs:** Grep results with no context for what the reference was pointing to.

### Pitfall 2: Overly Aggressive Reference Removal

**What goes wrong:** Historical planning docs lose context, making future decisions harder.

**Why it happens:** Treating all references equally instead of by document purpose.

**How to avoid:** Classify references by document type:
- Historical/planning: Annotate with "REMOVED in Phase 4" but keep context
- Active code: Remove completely
- Active docs: Update or remove based on relevance

**Warning signs:** Phase planning docs that no longer explain what was replaced.

### Pitfall 3: Partial String Matches

**What goes wrong:** Grep matches "autoresponder" in unrelated context (variable names, comments about concept).

**Why it happens:** Simple pattern without word boundaries or file extension.

**How to avoid:** Use precise patterns:
- `autoresponder\.sh` not just `autoresponder`
- `\bhook-watcher\.sh\b` with word boundaries
- Review matches manually before bulk operations

**Warning signs:** Grep returning matches in unrelated documentation.

### Pitfall 4: Forgetting Untracked Files

**What goes wrong:** `git rm` on untracked file fails; file remains.

**Why it happens:** Assumption all scripts are in repo.

**How to avoid:** Verify tracking status first: `git ls-files <path>`. Use `rm` for untracked files.

**Warning signs:** Error: "pathspec 'file' did not match any files" from git rm.

### Pitfall 5: Not Verifying settings.json State

**What goes wrong:** Deleting gsd-session-hook.sh before confirming it's removed from settings.json.

**Why it happens:** Phase isolation — not checking Phase 2 completion.

**How to avoid:** User decision says trust GSD phase order. Phase 2 verification confirms removal already done.

**Warning signs:** None in this case — Phase 2 verification report confirms clean state.

## Code Examples

### Example 1: Git-Tracked File Deletion

```bash
# Verify file is tracked
git ls-files scripts/autoresponder.sh
# Output: scripts/autoresponder.sh

# Delete with git rm
git rm scripts/autoresponder.sh
# Output: rm 'scripts/autoresponder.sh'

# Verify deletion staged
git status
# Output: deleted: scripts/autoresponder.sh
```

### Example 2: Untracked File Deletion

```bash
# Verify file exists
ls -la /home/forge/.claude/hooks/gsd-session-hook.sh
# Output: -rwxrwxr-x 1 forge forge 819 Feb 16 08:02 gsd-session-hook.sh

# Check if tracked (will error - expected)
git ls-files /home/forge/.claude/hooks/gsd-session-hook.sh
# Output: fatal: '/home/forge/.claude/hooks/gsd-session-hook.sh' is outside repository

# Delete with rm
rm /home/forge/.claude/hooks/gsd-session-hook.sh

# Verify deletion
ls -la /home/forge/.claude/hooks/gsd-session-hook.sh
# Output: ls: cannot access '...': No such file or directory
```

### Example 3: Finding References with Grep

```bash
# Find all autoresponder.sh references
grep -r "autoresponder\.sh" /home/forge/.openclaw/workspace/skills/gsd-code-skill

# More precise with word boundaries
grep -rE '\bautoresponder\.sh\b' .

# Count references per file
grep -rc "autoresponder\.sh" . | grep -v ':0$'

# Show context (2 lines before/after)
grep -rC 2 "autoresponder\.sh" .
```

### Example 4: Reference Fix Decision Tree

```bash
# For each grep match, ask:

# 1. Is this historical documentation (phase plans, research)?
#    → Keep reference, add "REMOVED in Phase 4" annotation

# 2. Is this active code (scripts/*.sh)?
#    → Should be zero — spawn.sh and recover already clean

# 3. Is this active documentation (SKILL.md, README.md)?
#    → Remove if obsolete, update if contextual

# 4. Is this success criteria (ROADMAP.md)?
#    → Update criteria to reflect completed state

# 5. Is this requirement definition (REQUIREMENTS.md)?
#    → Keep — requirements remain valid, track completion
```

## State of the Art

### Migration Context

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Polling-based menu detection (autoresponder, hook-watcher) | Event-driven hooks (Stop, Notification, SessionEnd, PreCompact) | Phase 1-2 (2026-02-17) | Zero polling overhead, precise agent targeting, full context in wake messages |
| Global SessionStart hook launches watchers | Direct hook registration in settings.json | Phase 2 (2026-02-17) | No watcher startup delay, hooks active from session start |
| Hardcoded spawn logic | Registry-driven configuration | Phase 3 (2026-02-17) | Per-agent system prompts, jq-based operations |

### Obsolescence Timeline

**Phase 1 (Additive):** Created hook scripts alongside old polling scripts
**Phase 2 (Wiring):** Registered hooks in settings.json, removed gsd-session-hook.sh from SessionStart array
**Phase 3 (Launcher Updates):** Removed autoresponder launch logic from spawn.sh, removed hook-watcher references from recovery
**Phase 4 (Cleanup):** Delete obsolete files that are no longer referenced or launched

### Why These Scripts Are Safe to Delete

1. **autoresponder.sh:**
   - Never launched by spawn.sh after Phase 3 (--autoresponder flag removed)
   - Never launched by recovery script after Phase 3
   - Functionality replaced by intelligent agent decisions via menu-driver.sh

2. **hook-watcher.sh:**
   - Never launched by gsd-session-hook.sh after Phase 2 (removed from settings.json)
   - Functionality replaced by stop-hook.sh and notification-idle-hook.sh
   - Both grepped in spawn.sh and recovery: zero references

3. **gsd-session-hook.sh:**
   - Removed from settings.json SessionStart array in Phase 2
   - Verified in Phase 2 verification report (criterion 6): absent from SessionStart
   - No longer fires on new Claude Code sessions

## Open Questions

None. All information needed for planning is available from:
1. File locations verified via Glob
2. Git tracking status verified via `git ls-files`
3. Reference locations identified via Grep
4. Phase 2 verification confirms settings.json cleanup
5. User decisions clearly documented in CONTEXT.md

## Sources

### Primary (HIGH confidence)

- **Direct file inspection:**
  - `/home/forge/.openclaw/workspace/skills/gsd-code-skill/scripts/autoresponder.sh` (Read tool)
  - `/home/forge/.openclaw/workspace/skills/gsd-code-skill/scripts/hook-watcher.sh` (Read tool)
  - `/home/forge/.claude/hooks/gsd-session-hook.sh` (Read tool)

- **Git tracking verification:**
  - `git ls-files scripts/autoresponder.sh scripts/hook-watcher.sh` (Bash tool)
  - Confirmed both are tracked in skill repo

- **Phase 2 verification:**
  - `.planning/phases/02-hook-wiring/02-VERIFICATION.md` (Read tool)
  - Criterion 6 verified: gsd-session-hook.sh removed from SessionStart

- **User decisions:**
  - `.planning/phases/04-cleanup/04-CONTEXT.md` (Read tool)
  - Locked decisions on deletion method, process handling, verification

- **Reference search:**
  - Grep tool results for all three script names
  - 15 files with references identified

### Secondary (MEDIUM confidence)

- **Active script verification:**
  - Grep on spawn.sh and recover-openclaw-agents.sh showed zero references
  - Confirms Phase 3 cleanup complete

### Tertiary (LOW confidence)

None. All findings verified through direct inspection or git operations.

## Metadata

**Confidence breakdown:**
- File locations and tracking status: HIGH - Direct verification via git and filesystem
- Reference locations: HIGH - Exhaustive grep across codebase
- Deletion safety: HIGH - Phase 2 verification + Phase 3 completion + no active references
- Reference fix strategy: MEDIUM - Requires judgment calls per file, but classification patterns clear

**Research date:** 2026-02-17
**Valid until:** 2026-03-17 (30 days - stable architecture, unlikely to change)

**Key findings:**
1. Three files to delete: two git-tracked, one untracked
2. Zero references in active scripts (spawn.sh, recover-openclaw-agents.sh already clean)
3. 15+ documentation files with references requiring classification and fix
4. Phase 2 verification confirms settings.json cleanup (gsd-session-hook.sh already removed)
5. User prefers minimal cleanup: no process killing, no temp file cleanup
6. Grep-based verification doubles as work discovery for reference fixes

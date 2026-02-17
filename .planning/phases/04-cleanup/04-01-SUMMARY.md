---
phase: 04-cleanup
plan: 01
subsystem: cleanup
tags: [cleanup, documentation, deletion]
dependency_graph:
  requires: []
  provides: [clean-codebase, no-obsolete-scripts, no-stale-references]
  affects: [scripts, documentation]
tech_stack:
  added: []
  patterns: [file-deletion, reference-cleanup]
key_files:
  created: []
  modified:
    - SKILL.md
    - PRD.md
    - .planning/PROJECT.md
    - .planning/ROADMAP.md
  deleted:
    - scripts/autoresponder.sh
    - scripts/hook-watcher.sh
    - /home/forge/.claude/hooks/gsd-session-hook.sh
decisions:
  - Let old hook-watcher processes die naturally (no pkill)
  - Let /tmp watcher state files disappear on reboot (no manual cleanup)
  - Mark deleted scripts as removed in active documentation with strikethrough
metrics:
  duration_minutes: 2
  tasks_completed: 2
  files_modified: 4
  files_deleted: 3
  completed_date: 2026-02-17
---

# Phase 04 Plan 01: Delete Obsolete Polling Scripts Summary

**One-liner:** Deleted three obsolete polling scripts (autoresponder.sh, hook-watcher.sh, gsd-session-hook.sh) and fixed all dangling references in active documentation.

## What Was Built

Removed three obsolete scripts that have been replaced by the event-driven hook system implemented in Phases 1-3:

1. **scripts/autoresponder.sh** - Polling-based menu responder (1s loop, picks option 1 blindly)
2. **scripts/hook-watcher.sh** - Polling-based menu detector (1s loop, broadcasts to all agents)
3. **~/.claude/hooks/gsd-session-hook.sh** - SessionStart hook that launched hook-watcher.sh

Fixed all dangling references in active documentation:
- **SKILL.md**: Removed `--autoresponder` flag from spawn.sh signature, replaced autoresponder references with hook-driven event system description
- **PRD.md**: Marked DELETE sections 13-15 as "COMPLETED — deleted in Phase 4", updated Phase 4 scope to reflect user decisions (no pkill, no /tmp cleanup)
- **PROJECT.md**: Marked autoresponder.sh and hook-watcher.sh as removed with strikethrough notation
- **ROADMAP.md**: Updated Phase 4 success criteria 4 and 5 to reflect user decisions about natural process cleanup

## Deviations from Plan

None - plan executed exactly as written.

## Key Decisions

1. **Natural process death over pkill** - Per user decision, old hook-watcher processes left to die naturally when sessions end or on reboot (no pkill commands)
2. **Natural /tmp cleanup** - Per user decision, watcher state files in /tmp left to disappear naturally on reboot (no manual cleanup)
3. **Strikethrough notation** - Used `~~script.sh~~` in PROJECT.md to clearly mark removed scripts while maintaining historical context

## Technical Details

### File Deletions

**Git-tracked scripts (removed via git rm):**
- scripts/autoresponder.sh (162 lines deleted)
- scripts/hook-watcher.sh

**Untracked script (removed via rm):**
- /home/forge/.claude/hooks/gsd-session-hook.sh

### Documentation Updates

**SKILL.md:**
- Line 26: Removed `[--autoresponder]` from spawn.sh signature
- Lines 42-43: Replaced two-line autoresponder description with single hook-driven event system description

**PRD.md:**
- Lines 237, 241, 245: Added "(COMPLETED — deleted in Phase 4)" to DELETE section headings
- Line 448: Updated Phase 4 scope to match user decisions (no pkill, no /tmp cleanup)

**PROJECT.md:**
- Lines 33-34: Marked autoresponder.sh and hook-watcher.sh as removed with strikethrough and "Removed in Phase 4" annotation

**ROADMAP.md:**
- Lines 94-95: Updated Phase 4 success criteria to reflect natural cleanup approach

### Verification Results

All verification checks passed:
1. ✓ All three scripts report "No such file or directory"
2. ✓ Zero autoresponder references in SKILL.md
3. ✓ All remaining references in active documentation are properly annotated as "Removed in Phase 4"
4. ✓ No script files reference deleted scripts

## Testing

Manual verification:
- `ls scripts/autoresponder.sh scripts/hook-watcher.sh /home/forge/.claude/hooks/gsd-session-hook.sh 2>&1` → All report "No such file or directory"
- `grep -r "autoresponder" SKILL.md` → No matches
- `grep -rn "autoresponder\|hook-watcher\|gsd-session-hook" SKILL.md .planning/PROJECT.md` → Only historical or annotated references remain

## Integration

No integration work required. This is a cleanup phase with zero runtime impact. The scripts were already not being launched by spawn.sh or recover-openclaw-agents.sh (updated in Phase 3).

## Documentation Impact

Updated 4 documentation files to remove stale references and properly annotate deleted scripts. Historical documentation in `.planning/phases/01-*/`, `02-*/`, `03-*/`, research, and debug directories preserved unchanged as historical records.

## Next Steps

Phase 5 (Documentation) will update SKILL.md and README.md with comprehensive hook architecture documentation including all 5 hook scripts, hybrid mode, hook_settings configuration, and system_prompt usage.

## Commits

1. **1733f40** - `chore(04-01): delete obsolete polling scripts`
   - Deleted scripts/autoresponder.sh via git rm
   - Deleted scripts/hook-watcher.sh via git rm
   - Deleted /home/forge/.claude/hooks/gsd-session-hook.sh via rm

2. **2b22e88** - `docs(04-01): fix dangling references to deleted scripts`
   - Updated SKILL.md spawn.sh signature and hook description
   - Marked PRD.md DELETE sections as completed
   - Annotated PROJECT.md with removed script markers
   - Updated ROADMAP.md Phase 4 success criteria

## Self-Check: PASSED

Verified all claimed artifacts exist and commits are present:

**Documentation files:**
- FOUND: SKILL.md
- FOUND: PRD.md
- FOUND: .planning/PROJECT.md
- FOUND: .planning/ROADMAP.md

**Deleted scripts:**
- VERIFIED: autoresponder.sh deleted
- VERIFIED: hook-watcher.sh deleted
- VERIFIED: gsd-session-hook.sh deleted

**Commits:**
- FOUND: 1733f40
- FOUND: 2b22e88

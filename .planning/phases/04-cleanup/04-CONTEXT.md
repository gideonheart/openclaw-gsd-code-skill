# Phase 4: Cleanup - Context

**Gathered:** 2026-02-17
**Status:** Ready for planning

<domain>
## Phase Boundary

Remove obsolete polling scripts (autoresponder.sh, hook-watcher.sh, gsd-session-hook.sh) now that spawn and recovery use the hook system. Fix any dangling references to deleted scripts across the codebase.

</domain>

<decisions>
## Implementation Decisions

### Deletion method
- Use `git rm` for all git-tracked scripts (autoresponder.sh, hook-watcher.sh, gsd-session-hook.sh)
- Do NOT clean up /tmp watcher state files — let them disappear on reboot naturally
- No custom cleanup scripts for temp files

### Process termination
- Do NOT kill running hook-watcher or autoresponder processes
- Let old processes die naturally when their sessions end or on reboot
- No pkill commands in the cleanup phase

### Transition safety
- No pre-check that Phase 2+3 are complete — GSD enforces execution order
- If Phase 4 is running, prior phases are guaranteed done
- No verification scripts or dependency checks

### Post-cleanup verification
- Grep the codebase for any remaining references to deleted script names (autoresponder.sh, hook-watcher.sh, gsd-session-hook.sh)
- Fix stale references in-place — remove or update them, don't just log
- Complete cleanup: no broken pointers left behind after this phase

### Claude's Discretion
- Exact grep patterns for finding references
- Whether to update or remove stale references (context-dependent)
- Order of file deletions

</decisions>

<specifics>
## Specific Ideas

- Phase is intentionally minimal: just `git rm` tracked files + fix dangling references
- User explicitly chose not to add process killing or temp file cleanup — keep it simple
- Verification (grep for references) doubles as finding work items for the fix step

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 04-cleanup*
*Context gathered: 2026-02-17*

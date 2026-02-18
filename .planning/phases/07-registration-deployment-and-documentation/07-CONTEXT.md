# Phase 7: Registration, Deployment, and Documentation - Context

**Gathered:** 2026-02-18
**Status:** Ready for planning

<domain>
## Phase Boundary

Register the new PreToolUse hook in settings.json so AskUserQuestion forwarding activates in all Claude Code sessions, add /tmp pane state file cleanup to session-end-hook.sh, and update SKILL.md to document the v2.0 architecture. This is deployment and documentation -- no new extraction logic, no new hook scripts.

</domain>

<decisions>
## Implementation Decisions

### Hook Registration
- Add PreToolUse entry to register-hooks.sh's HOOKS_CONFIG with matcher "AskUserQuestion"
- PreToolUse hook must be in the pre-flight script check array (HOOK_SCRIPTS)
- No timeout for PreToolUse hook (or short timeout ~10s) -- the hook backgrounds its work and exits immediately, unlike Stop/Notification which may do synchronous work
- Verification section should confirm PreToolUse registration alongside existing hooks

### Temp File Cleanup
- session-end-hook.sh cleans up only THIS session's state files: `/tmp/gsd-pane-prev-${SESSION_NAME}.txt` and `/tmp/gsd-pane-lock-${SESSION_NAME}`
- Do NOT clean all `/tmp/gsd-pane-*` files -- other sessions may still be running
- Cleanup happens AFTER the wake message delivery (not before)
- Use `rm -f` (silent failure) -- files may not exist if pane diff fallback was never triggered
- Add cleanup as a numbered section after delivery (section 7 in session-end-hook.sh)

### Documentation Updates
- Update SKILL.md hooks section to include pre-tool-use-hook.sh with one-line description
- Add lib/hook-utils.sh to the project structure (new "Shared Libraries" subsection or add to existing hooks listing)
- Document v2 wake format: [CONTENT] replaces [PANE CONTENT], transcript extraction primary, pane diff fallback
- Note minimum Claude Code version requirement: >= 2.0.76 (PreToolUse + AskUserQuestion bug fixed)
- Keep progressive disclosure style -- hooks section stays concise, point to docs/hooks.md for details
- Update docs/hooks.md with v2 format details, extraction chain, and pre-tool-use-hook.sh behavior

### Deployment Coordination
- The wake format change from [PANE CONTENT] to [CONTENT] is already live in stop-hook.sh (Phase 6)
- Gideon's wake message parsing is outside this skill's scope -- it lives in OpenClaw's gateway or Gideon's workspace
- SKILL.md should document the format change as a breaking change with a "Migration" or "Breaking Changes" note
- register-hooks.sh is the deployment trigger -- running it activates all v2 hooks for new sessions

### Claude's Discretion
- Exact wording and structure of SKILL.md documentation
- Whether to add a CHANGELOG or "v2.0 Migration" section to README.md
- docs/hooks.md organizational structure for v2 additions

</decisions>

<specifics>
## Specific Ideas

- register-hooks.sh already handles all 5 hooks idempotently -- adding PreToolUse follows the exact same pattern
- session-end-hook.sh is the simplest hook (87 lines) -- cleanup addition is 5-10 lines
- SKILL.md uses progressive disclosure: quick reference in main file, detailed behavior in docs/hooks.md
- The register-hooks.sh verification output should show PreToolUse alongside existing hooks

</specifics>

<deferred>
## Deferred Ideas

None -- discussion stayed within phase scope.

</deferred>

---

*Phase: 07-registration-deployment-and-documentation*
*Context gathered: 2026-02-18*

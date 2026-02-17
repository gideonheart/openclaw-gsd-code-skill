# Phase 5: Documentation - Context

**Gathered:** 2026-02-17
**Status:** Ready for planning

<domain>
## Phase Boundary

Update SKILL.md, README.md, TOOLS.md, and create docs/ reference files to reflect the new hook-driven architecture. Covers all hook scripts, hybrid mode, hook_settings, system_prompt configuration, and the updated script inventory. Clean slate — no mention of the old polling system.

</domain>

<decisions>
## Implementation Decisions

### Documentation architecture (audience split)
- **SKILL.md** is for agents — teaches an orchestrator agent how to spawn, configure, and manage GSD sessions
- **README.md** is for admins — covers everything a human needs to set up before the skill runs autonomously (registry, hooks, systemd, Laravel Forge scheduling)
- **docs/ folder** holds shared deep-dive content referenced by both SKILL.md and README.md — no duplication between files
- Token efficiency is critical: SKILL.md must be lean enough that an agent can spawn new sessions without overloading context; deeper docs loaded on demand only if needed

### SKILL.md structure
- Quick-start flow first: step-by-step "launch a new agent" (configure registry, register hooks, spawn)
- Lifecycle narrative: spawn -> hooks control session -> crash/reboot -> systemd timer -> recovery -> agents resume
- Agent-invocable scripts get enough detail for happy-path usage directly in SKILL.md (no extra doc loading needed for standard operations)
- Deeper details (hook specs, troubleshooting) live in docs/ files, referenced from SKILL.md with load instructions

### Hook script documentation
- Full behavior spec per hook: trigger event, what it does, configuration via hook_settings, edge cases, relevant registry fields
- Grouped by purpose: "Wake hooks" (stop-hook, notification-idle-hook, notification-permission-hook) and "Lifecycle hooks" (session-end-hook, pre-compact-hook)
- Inline hook_settings JSON examples with each hook's documentation
- Hook docs live in docs/ (split-off file) — SKILL.md references them, not inlined

### Registry schema documentation
- Annotated JSON example with inline comments explaining each field, required/optional status, defaults, and three-tier fallback
- Three-tier fallback (per-agent > global > hardcoded) explained in text description with concrete example
- Registry docs stay in README.md (admin territory) — SKILL.md references README.md, no duplication

### README.md structure
- Admin setup checklist (pre-flight): numbered steps covering registry config, hook registration, systemd install, Laravel Forge schedule
- Full registry schema with annotated JSON example
- Operational runbook: manual runs, dry-run, troubleshooting, daemon verification
- How to check if daemon is watching and hooks are firing

### Script inventory
- Grouped by role in SKILL.md: Session management (spawn, recover, sync), Hooks (stop, idle, permission, session-end, pre-compact), Utilities (menu-driver, register-hooks)
- TOOLS.md updated: gsd-code-skill section reflects only agent-invocable scripts (spawn, recover, menu-driver, sync, register-hooks) — hook scripts excluded (they fire automatically)
- register-hooks.sh appears in both TOOLS.md and README.md (agent may need to re-register after updates)

### Clean slate approach
- No mention of old polling system (autoresponder, hook-watcher, gsd-session-hook)
- Document current architecture as if it always existed

### Claude's Discretion
- Exact docs/ file structure and naming (e.g., docs/hooks.md, docs/registry.md, or different split)
- How much spawn/recover detail goes inline vs docs/ (balance token budget with "works on first try" usability)
- SKILL.md section ordering beyond quick-start first
- README.md section ordering beyond checklist first

</decisions>

<specifics>
## Specific Ideas

- "Agent should be able to execute commands, use this skill, and hook into hooks autonomously after setup"
- "After restart, all agents can continue like nothing happened because daemons are set up"
- "Systemd/daemon setup will happen through Laravel Forge UI" — README.md should document what needs configuring in Forge, not raw systemctl commands only
- "Agent should be able to make new agent sessions without overwhelming loading of all docs, only load more if it fails"
- TOOLS.md gsd-code-skill section must be updated so Gideon knows what's available

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 05-documentation*
*Context gathered: 2026-02-17*

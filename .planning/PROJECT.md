# gsd-code-skill

## What This Is

A multi-agent Claude Code session management skill for OpenClaw. It launches Claude Code sessions in tmux with strict GSD constraints, provides deterministic recovery after reboot/OOM, and handles interactive menu responses — enabling agents (Gideon, Warden, Forge) to operate autonomously across persistent coding sessions.

## Core Value

Reliable, intelligent agent session lifecycle — launch, recover, and respond to Claude Code sessions without human intervention.

## Current Milestone: v1.0 Hook-Driven Agent Control

**Goal:** Replace polling-based menu handling with Claude Code's native Stop hook for event-driven, agent-intelligent control.

**Target features:**
- Stop hook replaces autoresponder.sh and hook-watcher.sh
- Per-agent configurable system prompts via recovery registry
- OpenClaw agents make intelligent menu decisions (not blind heuristics)
- Precise agent targeting (direct session ID, not broadcast)

## Requirements

### Validated

<!-- Shipped and confirmed valuable. Inferred from existing working code. -->

- spawn.sh — Launch Claude Code in tmux with GSD constraints, auto-upsert registry
- recover-openclaw-agents.sh — Deterministic multi-agent recovery after reboot/OOM
- menu-driver.sh — Atomic TUI actions (snapshot, choose, enter, esc, clear_then, submit)
- sync-recovery-registry-session-ids.sh — Refresh OpenClaw session IDs from agent directories
- autoresponder.sh — Local heuristic-based menu responder (to be replaced)
- hook-watcher.sh — Polling-based menu detection with OpenClaw wake (to be replaced)
- systemd timer — Auto-recovery on boot (45s delay)

### Active

<!-- Current scope. Building toward these. -->

- [ ] Stop hook for event-driven agent control
- [ ] Per-agent configurable system prompts
- [ ] Menu-driver freeform text input
- [ ] Remove polling-based scripts (autoresponder, hook-watcher)
- [ ] Updated documentation

### Out of Scope

- Multi-project session management — one session per agent is sufficient
- Web dashboard integration — warden.kingdom.lv reads tmux directly
- Claude Code plugin/extension development — bash scripts only

## Context

- **Host:** Ubuntu 24 on Vultr, managed by Laravel Forge, user `forge`
- **Current scripts:** 6 bash scripts (~1,333 lines total), all production-quality
- **Agent architecture:** Gideon (orchestrator), Warden (coding), Forge (infra) — each with tmux sessions
- **Integration points:** Claude Code (`--append-system-prompt`, hooks API), OpenClaw (`openclaw agent --session-id`), tmux, systemd
- **Prior investigation:** Warden idle bug (resolved) — spawn.sh now uses `--append-system-prompt` correctly
- **PRD exists:** `PRD.md` at repo root with detailed technical design

## Constraints

- **Tech stack**: Bash scripts only (no Node/Python runtime dependencies beyond embedded Python for JSON) — matches OpenClaw skill conventions
- **Compatibility**: Must work with Claude Code hooks API (Stop hook, SessionStart hook)
- **Recovery**: Recovery flow must remain deterministic and work after cold boot
- **Non-breaking**: Existing managed sessions must not break during migration

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Stop hook over polling | Event-driven is more precise, lower overhead, enables intelligent decisions | -- Pending |
| Per-agent system prompts in registry | Different agents need different personalities/constraints | -- Pending |
| Delete autoresponder + hook-watcher | Replaced by Stop hook; keeping both creates confusion | -- Pending |

---
*Last updated: 2026-02-17 after milestone v1.0 initialization*

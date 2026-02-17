# gsd-code-skill

## What This Is

A multi-agent Claude Code session management skill for OpenClaw. It launches Claude Code sessions in tmux with strict GSD constraints, provides deterministic recovery after reboot/OOM, and handles interactive menu responses — enabling agents (Gideon, Warden, Forge) to operate autonomously across persistent coding sessions.

## Core Value

Reliable, intelligent agent session lifecycle — launch, recover, and respond to Claude Code sessions without human intervention.

## Current Milestone: v2.0 Smart Hook Delivery

**Goal:** Replace blunt 120-line pane scraping with precise content extraction — read transcript for responses, forward AskUserQuestion data via PreToolUse hook, and diff-based delivery for remaining pane captures.

**Target features:**
- Transcript-based response extraction (read transcript_path JSONL instead of tmux pane scraping)
- PreToolUse hook for AskUserQuestion (forward exact questions + options to OpenClaw)
- Diff-based pane content (compare with previous capture, send only changes)
- Structured wake message v2 (compact, extracted data instead of raw pane dump)
- Minimum context guarantee (always send at least 10 lines so orchestrator has context)

## Requirements

### Validated

<!-- Shipped and confirmed valuable. -->

- spawn.sh — Launch Claude Code in tmux with GSD constraints, auto-upsert registry
- recover-openclaw-agents.sh — Deterministic multi-agent recovery after reboot/OOM
- menu-driver.sh — Atomic TUI actions (snapshot, choose, enter, esc, clear_then, submit, type)
- sync-recovery-registry-session-ids.sh — Refresh OpenClaw session IDs from agent directories
- systemd timer — Auto-recovery on boot (45s delay)
- Hook system (Stop, Notification, SessionEnd, PreCompact) — event-driven agent control (v1.0)
- Per-agent configurable system prompts via recovery registry (v1.0)
- hook_settings with three-tier fallback (per-agent > global > hardcoded) (v1.0)
- Hybrid hook mode: async default, bidirectional per-agent (v1.0)
- Separate scripts per hook event (SRP) (v1.0)

### Active

<!-- Current scope. Building toward these. -->

- [ ] Read transcript_path JSONL to extract Claude's last response
- [ ] PreToolUse hook forwarding AskUserQuestion data to OpenClaw
- [ ] Diff-based pane content delivery (send delta, not full 120 lines)
- [ ] Structured wake message v2 format
- [ ] Deduplication (skip or lightweight signal when content unchanged)

### Out of Scope

- Multi-project session management — one session per agent is sufficient
- Web dashboard integration — warden.kingdom.lv reads tmux directly
- Claude Code plugin/extension development — bash scripts only
- /copy programmatic API — no programmatic access exists, user-facing command only

## Context

- **Host:** Ubuntu 24 on Vultr, managed by Laravel Forge, user `forge`
- **Current scripts:** 11 bash scripts (5 hooks + 6 core), all production-quality
- **Agent architecture:** Gideon (orchestrator), Warden (coding), Forge (infra) — each with tmux sessions
- **Integration points:** Claude Code (`--append-system-prompt`, hooks API), OpenClaw (`openclaw agent --session-id`), tmux, systemd
- **Prior investigation:** Warden idle bug (resolved) — spawn.sh now uses `--append-system-prompt` correctly
- **PRD exists:** `PRD.md` at repo root with detailed technical design

## Constraints

- **Tech stack**: Bash + jq only (no Node/Python runtime dependencies) — matches OpenClaw skill conventions, cross-platform compatible
- **Compatibility**: Must work with Claude Code hooks API (Stop, Notification, SessionEnd, PreCompact, SessionStart)
- **Recovery**: Recovery flow must remain deterministic and work after cold boot
- **Non-breaking**: Existing managed sessions must not break during migration

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Stop hook over polling | Event-driven is more precise, lower overhead, enables intelligent decisions | Confirmed |
| Multiple hook events (Stop, Notification, SessionEnd, PreCompact) | OpenClaw needs full visibility into Claude Code sessions for autonomous operation | Confirmed |
| Per-agent system prompts in registry | Different agents need different personalities/constraints | Confirmed |
| jq replaces Python for registry operations | Cross-platform compatibility, no Python dependency, jq already installed | Confirmed |
| Hybrid hook mode (async + bidirectional) | Default async for speed, optional bidirectional for direct instruction injection | Confirmed |
| hook_settings nested object with three-tier fallback | Per-agent > global > hardcoded, per-field merge for granular config | Confirmed |
| External default-system-prompt.txt | Tracked in git, easy to edit without touching script code | Confirmed |
| Separate scripts per hook event (SRP) | Each script does one thing, easier to maintain and debug | Confirmed |
| Delete autoresponder + hook-watcher | Replaced by hook system; keeping both creates confusion | Confirmed |
| Transcript-based extraction over pane scraping | transcript_path JSONL provides exact response text, no tmux noise | Confirmed |
| PreToolUse hook for AskUserQuestion | Notification hooks don't include question data; PreToolUse does via tool_input | Confirmed |
| Diff-based pane delivery | Git-style delta reduces token waste and signal-to-noise for orchestrator | Confirmed |

---
*Last updated: 2026-02-17 after v2.0 milestone start*

# Milestones: gsd-code-skill

## v4.0 Event-Driven Hook Architecture (In Progress)

**Goal:** Rewrite hook system from scratch. Event-folder architecture where each Claude Code hook event maps to `./events/{event_name}/` with handler + prompt. Agent wakes via OpenClaw, responds with GSD slash commands.

**Started:** 2026-02-19
**Phases:** TBD (defining requirements)

## v3.2 Per-Hook TUI Instruction Prompts (Shipped)

**Completed:** 2026-02-19
**Phases:** 3 (15-17), 17 total across all milestones
**What shipped:** Per-hook prompt templates, load_hook_prompt(), menu-driver multi-select support

## v3.1 Hook Refactoring & Migration (Shipped)

**Completed:** 2026-02-18
**Phases:** 3 (12-14)
**What shipped:** hook-preamble.sh shared bootstrap, extract_hook_settings(), detect_session_state(), [CONTENT] migration

## v3.0 Structured Hook Observability (Shipped)

**Completed:** 2026-02-18
**Phases:** 4 (8-11)
**What shipped:** JSONL event logging, write_hook_event_record(), PostToolUse AskUserQuestion lifecycle

## v2.0 Smart Hook Delivery (Shipped)

**Completed:** 2026-02-18
**Phases:** 2 (6-7)
**What shipped:** Transcript extraction, pane diff, PreToolUse hook, v2 wake format

## v1.0 Hook-Driven Agent Control (Shipped)

**Completed:** 2026-02-17
**Phases:** 5 (1-5)
**What shipped:** 5 hook scripts, per-agent system prompts, hook_settings, hybrid hook mode, menu-driver type action

---
*Last updated: 2026-02-19 after v4.0 milestone start*

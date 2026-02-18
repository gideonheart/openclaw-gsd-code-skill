# Roadmap: gsd-code-skill

## Milestones

- ✅ **v1.0 Hook-Driven Agent Control** - Phases 1-5 (shipped 2026-02-17)
- ✅ **v2.0 Smart Hook Delivery** - Phases 6-7 (shipped 2026-02-18)
- ✅ **v3.0 Structured Hook Observability** - Phases 8-11 (shipped 2026-02-18)

## Phases

<details>
<summary>✅ v1.0 Hook-Driven Agent Control (Phases 1-5) - SHIPPED 2026-02-17</summary>

### Phase 1: Additive Changes
**Goal**: Create all new components (5 hook scripts, menu-driver type action, hook_settings schema, default-system-prompt.txt) without disrupting existing autoresponder/hook-watcher workflows
**Depends on**: Nothing (first phase)
**Requirements**: HOOK-01 through HOOK-11, WAKE-01 through WAKE-06, MENU-01, CONFIG-01, CONFIG-02, CONFIG-04 through CONFIG-08
**Success Criteria** (what must be TRUE):
  1. stop-hook.sh exists with all safety guards (stop_hook_active check, stdin consumption, $TMUX validation, registry lookup, fast-path exits, hybrid mode support)
  2. notification-idle-hook.sh exists and handles idle_prompt events
  3. notification-permission-hook.sh exists and handles permission_prompt events (future-proofing)
  4. session-end-hook.sh exists and notifies OpenClaw on session termination
  5. pre-compact-hook.sh exists and captures state before context compaction
  6. All hook scripts share common guard patterns (stdin consumption, $TMUX check, registry lookup)
  7. menu-driver.sh supports `type <text>` action using tmux send-keys -l for literal freeform input
  8. recovery-registry.json schema includes system_prompt field (top-level) and hook_settings nested object with strict known fields
  9. Global hook_settings at registry root level with per-agent override and per-field merge (three-tier fallback)
  10. recovery-registry.example.json documents all fields with realistic multi-agent setup (Gideon, Warden, Forge)
  11. config/default-system-prompt.txt exists with minimal GSD workflow guidance, tracked in git
  12. Wake message format includes structured sections, session identity, state hint, trigger type, and context pressure with warning level
  13. No Python dependency — all registry operations use jq
**Plans**: 3 plans

Plans:
- [x] 01-01-PLAN.md -- Foundation: registry schema (system_prompt, hook_settings), default system prompt, menu-driver type action
- [x] 01-02-PLAN.md -- Wake-capable hooks: stop-hook.sh, notification-idle-hook.sh, notification-permission-hook.sh
- [x] 01-03-PLAN.md -- Lifecycle hooks: session-end-hook.sh, pre-compact-hook.sh

### Phase 2: Hook Wiring
**Goal**: Register all hooks globally in settings.json (Stop, Notification idle_prompt, Notification permission_prompt, SessionEnd, PreCompact) and remove SessionStart hook watcher launcher
**Depends on**: Phase 1
**Requirements**: CONFIG-03
**Success Criteria** (what must be TRUE):
  1. Stop hook registered in ~/.claude/settings.json calling stop-hook.sh
  2. Notification hooks registered with matchers for idle_prompt and permission_prompt
  3. SessionEnd hook registered calling session-end-hook.sh
  4. PreCompact hook registered calling pre-compact-hook.sh
  5. gsd-session-hook.sh removed from SessionStart hooks array in settings.json
  6. New Claude Code sessions fire all hooks instead of spawning hook-watcher.sh
  7. Existing sessions with running hook-watcher continue working (brief overlap tolerated)
**Plans**: 1 plan

Plans:
- [x] 02-01-PLAN.md -- Create idempotent registration script, wire all 5 hooks into settings.json, remove gsd-session-hook.sh from SessionStart

### Phase 3: Launcher Updates
**Goal**: Update spawn.sh and recover-openclaw-agents.sh to use system_prompt from registry with fallback defaults, using jq for all registry operations
**Depends on**: Phase 1
**Requirements**: SPAWN-01 through SPAWN-05, RECOVER-01, RECOVER-02
**Success Criteria** (what must be TRUE):
  1. spawn.sh reads system_prompt from registry entry after upsert and uses it via --append-system-prompt (falls back to default-system-prompt.txt if empty)
  2. spawn.sh supports --system-prompt flag for explicit override
  3. spawn.sh has no autoresponder flag or launch logic
  4. spawn.sh has no hardcoded strict_prompt function
  5. spawn.sh uses jq for all registry operations (no Python upsert)
  6. Per-agent system_prompt replaces default when present (replacement model per CONTEXT.md locked decision)
  7. recover-openclaw-agents.sh extracts system_prompt per agent from registry and passes via --append-system-prompt on launch
  8. Recovery script handles missing system_prompt field gracefully with fallback default
  9. Recovery script uses per-agent error handling (no set -e abort) and sends summary even on partial success
  10. Registry writes use atomic pattern with flock to prevent corruption
**Plans**: 2 plans

Plans:
- [x] 03-01-PLAN.md -- Rewrite spawn.sh as registry-driven jq-only launcher (agent-name primary key, system prompt composition, remove legacy code)
- [x] 03-02-PLAN.md -- Rewrite recover-openclaw-agents.sh with jq-only registry operations, per-agent system prompts, failure-only Telegram reporting

### Phase 4: Cleanup
**Goal**: Remove obsolete polling scripts (autoresponder, hook-watcher, gsd-session-hook) now that spawn and recovery no longer launch them
**Depends on**: Phase 2, Phase 3
**Requirements**: CLEAN-01, CLEAN-02, CLEAN-03
**Success Criteria** (what must be TRUE):
  1. autoresponder.sh deleted from scripts directory
  2. hook-watcher.sh deleted from scripts directory
  3. ~/.claude/hooks/gsd-session-hook.sh deleted
  4. Old hook-watcher processes left to die naturally when sessions end or on reboot (per user decision — no pkill)
  5. Watcher state files in /tmp left to disappear naturally on reboot (per user decision — no manual cleanup)
**Plans**: 1 plan

Plans:
- [x] 04-01-PLAN.md -- Delete obsolete polling scripts and fix dangling references in active documentation

### Phase 5: Documentation
**Goal**: Update skill documentation to reflect new hook architecture, all hook scripts, hybrid mode, hook_settings, and system_prompt configuration
**Depends on**: Phase 4
**Requirements**: DOCS-01, DOCS-02
**Success Criteria** (what must be TRUE):
  1. SKILL.md documents hook architecture (all 5 hook scripts), hybrid mode, hook_settings configuration, and system_prompt
  2. README.md documents updated registry schema with system_prompt field, hook_settings object, and recovery flow with all hooks
  3. Script list reflects removed scripts (autoresponder, hook-watcher, gsd-session-hook) and added hook scripts (stop-hook, notification-idle-hook, notification-permission-hook, session-end-hook, pre-compact-hook)
**Plans**: 2 plans

Plans:
- [x] 05-01-PLAN.md -- Agent-facing docs: rewrite SKILL.md with progressive disclosure, create docs/hooks.md, update TOOLS.md
- [x] 05-02-PLAN.md -- Admin-facing docs: rewrite README.md with pre-flight checklist, registry schema, operational runbook

</details>

### ✅ v2.0 Smart Hook Delivery (Complete — 2026-02-18)

**Milestone Goal:** Replace noisy 120-line raw pane dumps with clean content: transcript extraction (primary), pane diff fallback, and structured AskUserQuestion forwarding via PreToolUse.

### Phase 6: Core Extraction and Delivery Engine
**Goal**: Gideon receives clean extracted content — Claude's response from transcript JSONL (primary) or pane diff (fallback), plus structured AskUserQuestion data forwarded before TUI renders
**Depends on**: Phase 5
**Requirements**: LIB-01, LIB-02, EXTRACT-01, EXTRACT-02, EXTRACT-03, ASK-01, ASK-02, ASK-03, WAKE-07, WAKE-08, WAKE-09
**Success Criteria** (what must be TRUE):
  1. Wake message [CONTENT] section contains Claude's actual response text extracted from transcript JSONL — no ANSI codes, no pane noise
  2. When transcript extraction fails (file missing, parse error), hook falls back to pane diff (only new/added lines from last 40 lines) — never crashes, never sends empty
  3. When Claude calls AskUserQuestion, Gideon receives structured [ASK USER QUESTION] wake with question text and options (async, never blocks TUI)
  4. v1 wake format code removed — clean v2 format only: [SESSION IDENTITY], [TRIGGER], [CONTENT], [STATE HINT], [CONTEXT PRESSURE], [AVAILABLE ACTIONS]
  5. Shared lib/hook-utils.sh provides DRY extraction functions sourced by stop-hook.sh and pre-tool-use-hook.sh only
**Plans**: 3 plans

Plans:
- [x] 06-01-PLAN.md -- Shared library: lib/hook-utils.sh with three extraction functions (transcript, pane diff, question formatting)
- [x] 06-02-PLAN.md -- PreToolUse hook: scripts/pre-tool-use-hook.sh for AskUserQuestion forwarding
- [x] 06-03-PLAN.md -- Stop hook v2: transcript extraction, pane diff fallback, v2 [CONTENT] wake format

### Phase 7: Registration, Deployment, and Documentation
**Goal**: New hooks are live in all Claude Code sessions, temp state files are cleaned up on session exit, and SKILL.md reflects the v2.0 architecture
**Depends on**: Phase 6
**Requirements**: REG-01, REG-02, DOCS-03
**Success Criteria** (what must be TRUE):
  1. Running register-hooks.sh adds the PreToolUse hook with AskUserQuestion matcher to settings.json — new sessions get AskUserQuestion forwarding automatically
  2. When a Claude Code session ends, session-end-hook.sh deletes /tmp pane state files — no stale files accumulate
  3. SKILL.md documents v2.0 architecture: lib/hook-utils.sh, pre-tool-use-hook.sh, v2 wake format, minimum Claude Code version >= 2.0.76
**Plans**: 2 plans

Plans:
- [x] 07-01-PLAN.md -- Registration and cleanup: PreToolUse hook in register-hooks.sh, /tmp state file cleanup in session-end-hook.sh
- [x] 07-02-PLAN.md -- Documentation: Update SKILL.md and docs/hooks.md with v2.0 architecture

### v3.0 Structured Hook Observability

**Milestone Goal:** Replace plain-text debug_log with structured JSONL event logging — one complete record per hook invocation with full lifecycle data (trigger, state, wake message, response, outcome, duration). Single-record-per-invocation design: accumulate data during execution, write once at the end.

### Phase 8: JSONL Logging Foundation
**Goal**: Extend lib/hook-utils.sh with shared JSONL logging functions — the DRY foundation all 6 hook scripts will source. All correctness rules (jq --arg, flock, explicit parameter passing, /dev/null) established here before any hook uses them.
**Depends on**: Phase 7
**Requirements**: JSONL-01, JSONL-02, JSONL-03, JSONL-04, JSONL-05, OPS-01
**Success Criteria** (what must be TRUE):
  1. `write_hook_event_record()` function in lib/hook-utils.sh writes a single complete JSONL record per hook invocation
  2. All string fields use `jq -cn --arg` — wake messages with newlines, quotes, ANSI codes, embedded JSON produce valid JSONL
  3. All JSONL appends use `flock -x -w 2` on `${LOG_FILE}.lock` for atomic writes under concurrent hook fires
  4. `deliver_async_with_logging()` wrapper replaces bare `openclaw ... &` — captures response in background subshell, writes complete record after response arrives
  5. Background subshell uses explicit `</dev/null` to prevent stdin inheritance hangs
  6. Per-session `.jsonl` log files routed to `logs/{SESSION_NAME}.jsonl`
  7. Every record includes `duration_ms` from hook entry to record write
  8. Functions testable in isolation (bash unit test without running Claude Code session)
**Plans**: 2 plans

Plans:
- [x] 08-01-PLAN.md -- write_hook_event_record() function in lib/hook-utils.sh with JSONL record construction, flock atomic append, and unit test
- [x] 08-02-PLAN.md -- deliver_async_with_logging() wrapper in lib/hook-utils.sh with background subshell delivery and integration test

### Phase 9: Hook Script Migration
**Goal**: All 6 hook scripts emit structured JSONL records — source lib at top, accumulate lifecycle data, replace debug_log with structured logging, replace bare openclaw calls with delivery wrapper
**Depends on**: Phase 8
**Requirements**: HOOK-12, HOOK-13, HOOK-14, HOOK-15, HOOK-16, HOOK-17, ASK-04
**Success Criteria** (what must be TRUE):
  1. stop-hook.sh writes one JSONL record containing: trigger, state, content source, full wake message body, OpenClaw response, outcome, duration
  2. pre-tool-use-hook.sh writes one JSONL record with `questions_forwarded` field showing questions, options, headers sent to OpenClaw
  3. notification-idle-hook.sh, notification-permission-hook.sh, session-end-hook.sh, pre-compact-hook.sh each write one JSONL record per invocation
  4. All 6 scripts source lib/hook-utils.sh at top of script (before any guard exit)
  5. Plain-text `.log` files continue in parallel for backward compatibility during transition
  6. Guard exits (no TMUX, no registry match) do NOT emit JSONL — zero jq overhead for non-managed sessions
**Plans**: 3 plans

Plans:
- [x] 09-01-PLAN.md -- Migrate simple hooks: notification-idle, notification-permission, session-end
- [x] 09-02-PLAN.md -- Migrate medium hooks: pre-tool-use (ASK-04), pre-compact (bidirectional)
- [x] 09-03-PLAN.md -- Migrate stop-hook.sh (bidirectional, dynamic content_source)

### Phase 10: AskUserQuestion Lifecycle Completion
**Goal**: Full question-to-answer audit trail — see what OpenClaw received, what it decided, and how it controlled the TUI
**Depends on**: Phase 9
**Requirements**: ASK-05, ASK-06
**Success Criteria** (what must be TRUE):
  1. New `post-tool-use-hook.sh` fires after AskUserQuestion completes and emits JSONL record with `answer_selected` field
  2. PostToolUse hook registered in settings.json via register-hooks.sh
  3. `answer_selected` record includes which option was chosen and TUI control action taken (menu-driver command)
  4. PreToolUse and PostToolUse records share `tool_use_id` enabling question-to-answer lifecycle linking
  5. PostToolUse stdin schema empirically validated before schema is committed
**Plans**: 1 plan

Plans:
- [x] 10-01-PLAN.md -- PostToolUse hook, tool_use_id lifecycle linking, hook registration

### Phase 11: Operational Hardening
**Goal**: Production-grade log management and diagnostic tooling for JSONL logs
**Depends on**: Phase 9
**Requirements**: OPS-02, OPS-03
**Success Criteria** (what must be TRUE):
  1. logrotate config at `/etc/logrotate.d/gsd-code-skill` with `copytruncate` prevents unbounded disk growth
  2. `diagnose-hooks.sh` parses JSONL log files with `jq` for meaningful diagnostic output (recent events, error counts, outcome distribution)
  3. Log rotation verified safe with open `>>` file descriptors (copytruncate pattern)
**Plans**: 2 plans

Plans:
- [x] 11-01-PLAN.md -- Logrotate config template and install script (copytruncate for open >> fd safety)
- [x] 11-02-PLAN.md -- diagnose-hooks.sh Step 10: JSONL log analysis with jq diagnostic queries

## Phase Details

### Phase 6: Core Extraction and Delivery Engine
**Goal**: Gideon receives clean extracted content — Claude's response from transcript JSONL (primary) or pane diff (fallback), plus structured AskUserQuestion data forwarded before TUI renders
**Depends on**: Phase 5
**Requirements**: LIB-01, LIB-02, EXTRACT-01, EXTRACT-02, EXTRACT-03, ASK-01, ASK-02, ASK-03, WAKE-07, WAKE-08, WAKE-09
**Success Criteria** (what must be TRUE):
  1. Wake message [CONTENT] section contains Claude's actual response text extracted from transcript JSONL — no ANSI codes, no pane noise
  2. When transcript extraction fails (file missing, parse error), hook falls back to pane diff (only new/added lines from last 40 lines) — never crashes, never sends empty
  3. When Claude calls AskUserQuestion, Gideon receives structured [ASK USER QUESTION] wake with question text and options (async, never blocks TUI)
  4. v1 wake format code removed — clean v2 format only: [SESSION IDENTITY], [TRIGGER], [CONTENT], [STATE HINT], [CONTEXT PRESSURE], [AVAILABLE ACTIONS]
  5. Shared lib/hook-utils.sh provides DRY extraction functions sourced by stop-hook.sh and pre-tool-use-hook.sh only
**Plans**: 3 plans

Plans:
- [x] 06-01-PLAN.md -- Shared library: lib/hook-utils.sh with three extraction functions (transcript, pane diff, question formatting)
- [x] 06-02-PLAN.md -- PreToolUse hook: scripts/pre-tool-use-hook.sh for AskUserQuestion forwarding
- [x] 06-03-PLAN.md -- Stop hook v2: transcript extraction, pane diff fallback, v2 [CONTENT] wake format

### Phase 7: Registration, Deployment, and Documentation
**Goal**: New hooks are live in all Claude Code sessions, temp state files are cleaned up on session exit, and SKILL.md reflects the v2.0 architecture
**Depends on**: Phase 6
**Requirements**: REG-01, REG-02, DOCS-03
**Success Criteria** (what must be TRUE):
  1. Running register-hooks.sh adds the PreToolUse hook with AskUserQuestion matcher to settings.json — new sessions get AskUserQuestion forwarding automatically
  2. When a Claude Code session ends, session-end-hook.sh deletes /tmp pane state files — no stale files accumulate
  3. SKILL.md documents v2.0 architecture: lib/hook-utils.sh, pre-tool-use-hook.sh, v2 wake format, minimum Claude Code version >= 2.0.76
**Plans**: 2 plans

Plans:
- [x] 07-01-PLAN.md -- Registration and cleanup: PreToolUse hook in register-hooks.sh, /tmp state file cleanup in session-end-hook.sh
- [x] 07-02-PLAN.md -- Documentation: Update SKILL.md and docs/hooks.md with v2.0 architecture

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4 → 5 → 6 → 7 → 8 → 9 → 10 → 11

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1. Additive Changes | v1.0 | 3/3 | Complete | 2026-02-17 |
| 2. Hook Wiring | v1.0 | 1/1 | Complete | 2026-02-17 |
| 3. Launcher Updates | v1.0 | 2/2 | Complete | 2026-02-17 |
| 4. Cleanup | v1.0 | 1/1 | Complete | 2026-02-17 |
| 5. Documentation | v1.0 | 2/2 | Complete | 2026-02-17 |
| 6. Core Extraction and Delivery Engine | v2.0 | 3/3 | Complete | 2026-02-18 |
| 7. Registration, Deployment, and Documentation | v2.0 | 2/2 | Complete | 2026-02-18 |
| 8. JSONL Logging Foundation | v3.0 | 2/2 | Complete | 2026-02-18 |
| 9. Hook Script Migration | v3.0 | 3/3 | Complete | 2026-02-18 |
| 10. AskUserQuestion Lifecycle Completion | v3.0 | 1/1 | Complete | 2026-02-18 |
| 11. Operational Hardening | v3.0 | 2/2 | Complete | 2026-02-18 |

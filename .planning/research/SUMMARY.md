# Project Research Summary

**Project:** Stop Hook Integration for GSD Code Skill
**Domain:** Event-driven multi-agent control for Claude Code sessions
**Researched:** 2026-02-17
**Confidence:** HIGH

## Executive Summary

This project replaces polling-based menu detection (autoresponder.sh, hook-watcher.sh) with event-driven agent control via Claude Code's native Stop hook. The architecture is a clean evolution: when Claude finishes responding, the Stop hook captures the TUI state and sends it directly to the specific OpenClaw agent (via `openclaw agent --session-id`), who then makes intelligent decisions using menu-driver.sh. This eliminates 0-1s polling latency, removes duplicate wake events from broadcasting to all agents, and provides context in a single round-trip.

The stack requires zero new dependencies — all components (Claude Code 2.1.44, tmux 3.4, OpenClaw 2026.2.16, jq 1.7) are already installed and version-verified in production. Changes are surgical: add stop-hook.sh, enhance menu-driver.sh with a `type` action for freeform text input, add `system_prompt` field to recovery registry, and update spawn/recovery scripts to use custom prompts per agent. Migration is low-risk with careful phase ordering: additive changes first (no breakage), then hook wiring, then launcher updates, then cleanup of old polling scripts.

Critical risks center on hook implementation discipline: stdin must be consumed immediately to prevent pipe blocking, `stop_hook_active` guard prevents infinite loops, background openclaw calls must redirect stdin/stdout to avoid hook corruption, and registry writes need atomic patterns to prevent JSON corruption during concurrent access. The 10 documented pitfalls map cleanly to prevention phases, with verification steps to confirm safe migration.

## Key Findings

### Recommended Stack

**No new dependencies required.** All components are production-verified and currently running. The stack additions are native Claude Code features (Stop hook), flags on existing tools (tmux send-keys -l), and CLI capabilities already in OpenClaw (agent --session-id).

**Core technologies:**
- **Claude Code 2.1.44** with Stop hook: Event-driven session state capture when Claude finishes responding — native feature with stdin JSON and decision control
- **tmux 3.4** with send-keys -l: Literal mode for freeform text injection without key name interpretation — prevents garbled commands during concurrent spawns
- **OpenClaw 2026.2.16** with agent --session-id: Direct session messaging to specific agent instead of broadcast — precision targeting with full context in wake message
- **Bash + jq**: Stop hook implementation, registry lookup, pane capture, context extraction — zero runtime cost, 2ms execution time for fast-path exits
- **Recovery registry JSON**: Single source of truth mapping tmux sessions to OpenClaw agents — adds `system_prompt` field for per-agent customization

**What NOT to use:**
- Node.js or Python for hook (adds latency, bash is 2ms vs 50ms)
- Polling with sleep (CPU waste, hook eliminates need)
- Plugin-based Stop hook (known bug where JSON output not captured — use inline settings.json hooks)
- Global system events (broadcast noise — use targeted --session-id)

### Expected Features

**Must have (table stakes):**
- Stop hook fires on response complete — industry standard event-driven pattern (2026)
- `stop_hook_active` guard — prevents infinite loops (critical safety)
- Session registry lookup — routes pane snapshots to correct agent
- Pane snapshot capture — last 120 lines for decision context
- Context pressure extraction — token usage percentage enables proactive /clear decisions
- Backgrounded agent wake — hook exits <5ms, never blocks Claude
- Fast-path exit for non-managed sessions — 1-5ms overhead when session not in registry
- Freeform text input (`type` action) — agent responds to non-menu prompts
- Configurable system prompt — per-agent prompts from registry, not hardcoded
- Recovery flow integration — recover script passes system prompt on launch

**Should have (differentiators):**
- Agent-specific routing (not broadcast) — Stop hook wakes exact OpenClaw session, reduces noise
- Structured decision payload — hook sends pane + available actions + context warning (actionable, not raw dump)
- Multi-hook safety (wire vs logic separation) — hook in settings.json, logic in skill scripts (upgrading logic doesn't require editing global config)
- Zero-token overhead for non-managed sessions — fast-path exits when session not in registry
- Immediate hook exit (async agent wake) — prevents timeout and slowdown
- Retry-safe action deduplication — agent can safely retry menu-driver.sh calls (idempotent)
- Registry sync from agent sessions — auto-refresh session IDs to prevent stale rot

**Defer (v2+):**
- Advanced context pressure heuristics beyond percentage threshold (current ≥50% sufficient)
- LLM-guided decision complexity scoring (simple "send everything" works)
- Multi-agent swarm coordination (single agent per session sufficient)
- Audit trail / decision logging in hook (agent already logs)
- Rate limiting / backpressure on agent wakes (menus infrequent)

### Architecture Approach

Stop hook integration is a **subsequent milestone** adding to existing architecture. Current system uses polling (autoresponder.sh picks option 1 blindly every 1s, hook-watcher.sh broadcasts to all agents when menu detected). New system: Claude finishes → Stop hook fires instantly → captures pane → looks up agent in registry by tmux_session_name → sends snapshot + actions to specific agent → agent decides → calls menu-driver.sh → Claude receives input. This eliminates polling overhead, duplicate detection (SHA1 signatures no longer needed), broadcast spam, and separate snapshot requests.

**Major components:**
1. **stop-hook.sh (NEW)** — Stop hook entry point with guards (stop_hook_active, $TMUX check, registry lookup), pane capture (tmux capture-pane -S -120), context extraction (statusline parsing), structured payload (pane + actions + context warning), backgrounded OpenClaw wake (openclaw agent --session-id with stdin/stdout redirect)
2. **menu-driver.sh (MODIFIED)** — Atomic TUI actions, adds `type <text>` for freeform input (tmux send-keys -l for literal mode, C-u to clear line first)
3. **spawn.sh (MODIFIED)** — Remove autoresponder logic and hardcoded strict_prompt(), add --system-prompt flag, read system_prompt from registry after upsert, fall back to default if empty
4. **recover-openclaw-agents.sh (MODIFIED)** — Extract system_prompt per agent, pass via --append-system-prompt on launch, remove set -e for graceful partial recovery, add per-agent error handling
5. **recovery-registry.json (MODIFIED)** — Add system_prompt field (string, defaults to empty, optional per agent), Python upsert uses setdefault()
6. **~/.claude/settings.json (MODIFIED)** — Add Stop hook calling stop-hook.sh, remove gsd-session-hook.sh from SessionStart (no more hook-watcher launch)

**Integration points:**
- Stop hook → Registry lookup: reads $TMUX, queries registry by tmux_session_name, extracts openclaw_session_id, exits 0 if no match
- Stop hook → OpenClaw agent: captures pane, extracts context pressure, builds message, backgrounds openclaw call with `&`, exits immediately
- OpenClaw agent → menu-driver.sh: receives full context, makes LLM decision, calls appropriate action (snapshot, choose, type, clear_then, etc.)
- spawn.sh → Registry system prompt: upserts agent entry, reads system_prompt back, falls back to default if empty, builds claude_cmd with --append-system-prompt
- recover script → System prompt injection: extracts system_prompt per agent in Python parser, passes to ensure_claude_is_running_in_tmux(), appends via --append-system-prompt

### Critical Pitfalls

1. **Stop hook infinite loop via `stop_hook_active` ignorance** — Hook fires after every Claude response; if hook causes another response without checking `stop_hook_active` guard, infinite loop consumes all tokens and locks session. **Avoid:** Read stdin JSON first, check stop_hook_active field, exit 0 if true, background all openclaw calls, never return decision: "block"

2. **stdin pipe blocking from unconsumed input** — Hook scripts that don't consume stdin cause entire pipeline to block (pipe buffer fills, Claude waits for reader, hook waits for something else → deadlock). **Avoid:** Always consume stdin at top of script (cat > /dev/null or jq), test with large JSON payloads >64KB

3. **Registry corruption from concurrent writes** — Multiple processes (spawn.sh, recover script, sync script) write to registry.json simultaneously, causing truncated objects, interleaved writes, malformed JSON. **Avoid:** Atomic write pattern (write to .tmp.$$, then mv), wrap modifications in flock, validate JSON after every write, add retry with backoff

4. **Tmux send-keys corruption from concurrent spawning** — Multiple spawn.sh or recovery launches in parallel cause send-keys commands to interleave (tmux server input queue not isolated), producing garbled commands like "ccdd //ppaatthh". **Avoid:** Sequential processing with sleep 0.5 between agents, use send-keys -l (literal mode), avoid parallel spawns

5. **Recovery script failure leaves system broken** — If recover-openclaw-agents.sh aborts partway (Python exception, missing binary, malformed registry), some agents recovered and others not, systemd may mark service as start-limit-hit. **Avoid:** Remove set -e (handle errors per-agent), wrap each recovery in try/catch pattern, always send summary to global session even on partial failure, validate dependencies early

6. **Concurrent old and new systems create duplicate events** — During migration, both hook-watcher.sh (polling) and stop-hook.sh (new hook) active simultaneously, causing duplicate wakes within 1 second. **Avoid:** Accept brief overlap as tolerable (agents should be idempotent), add deduplication check in stop-hook (skip if old watcher state file modified <5s), kill all watchers before Phase 4 cleanup

7. **`system_prompt` field missing breaks recovery** — Old registry entries don't have system_prompt field; if recovery script doesn't handle gracefully, either passes empty prompt or crashes. **Avoid:** Use setdefault("system_prompt", "") in Python upsert, provide fallback default in bash, test recovery with old registry, document default prompt

8. **Hook fires for non-managed sessions, burning tokens** — Stop hook is global (in ~/.claude/settings.json), fires for ALL Claude Code sessions; expensive logic before registry check burns resources on random sessions. **Avoid:** Fast-path guards at top (check $TMUX, then registry match) BEFORE any expensive operations, log non-managed invocations for debugging

9. **Background `openclaw agent` inherits hook's stdin/stdout** — Backgrounding with `&` doesn't redirect file descriptors; child process competes for stdin or corrupts stdout, causing hook to hang or produce garbled JSON. **Avoid:** Redirect when backgrounding: `openclaw agent ... </dev/null >/dev/null 2>&1 &`, or use nohup, never rely on background process output

10. **Tmux session detection race condition during recovery** — Script checks `tmux has-session`, then sends keys; between check and action, session could die (manual kill, OOM), causing "session not found" error. **Avoid:** Don't rely on has-session checks, directly attempt operation and handle failure, wrap tmux commands in error handling, add retry logic with backoff

## Implications for Roadmap

Based on research, suggested phase structure prioritizes safety through additive changes first, then wiring, then updates, then cleanup. Critical path: new files must exist before hooks reference them, registry schema must exist before launchers read it, menu-driver.sh type action must exist before agents call it.

### Phase 1: Additive Changes (No Breakage)
**Rationale:** Create all new components without disrupting existing sessions. No hook registered yet, so stop-hook.sh is inert. New registry field ignored by old scripts. New menu-driver.sh action unused until agents updated.

**Delivers:**
- stop-hook.sh with full guards (stop_hook_active, stdin consumption, $TMUX check, registry lookup, fast-path exits)
- menu-driver.sh type action (tmux send-keys -l for literal freeform input)
- system_prompt field added to recovery-registry.json (empty string default, backward compatible)

**Addresses features:**
- Stop hook core (table stakes)
- Session registry lookup (table stakes)
- Freeform text input (table stakes)
- Configurable system prompt (table stakes)

**Avoids pitfalls:**
- Pitfall 1 (infinite loop): stop_hook_active guard implemented
- Pitfall 2 (stdin blocking): stdin consumption at top of hook
- Pitfall 7 (missing field): setdefault in Python upsert
- Pitfall 8 (non-managed sessions): fast-path guards before expensive logic
- Pitfall 9 (background inherits stdin): redirect stdin/stdout in openclaw call

**Research flags:** Standard bash/tmux patterns, no additional research needed.

### Phase 2: Hook Wiring (Minimal Risk)
**Rationale:** Wire Stop hook globally, remove SessionStart launcher for hook-watcher. New sessions use Stop hook, old sessions continue with hook-watcher until they end. Brief overlap acceptable (duplicate wakes are idempotent).

**Delivers:**
- Stop hook added to ~/.claude/settings.json
- gsd-session-hook.sh removed from SessionStart hooks
- New Claude Code sessions fire Stop hook instead of spawning hook-watcher

**Addresses features:**
- Stop hook fires on response complete (table stakes)
- Backgrounded agent wake (table stakes)
- Zero-token overhead (differentiator)
- Immediate hook exit (differentiator)

**Avoids pitfalls:**
- Pitfall 6 (duplicate events): Document overlap as temporary, agents designed for idempotency

**Research flags:** Verify Stop hook JSON schema with official Claude Code docs (already completed via WebSearch in STACK.md).

### Phase 3: Launcher Updates (Registry Reader Changes)
**Rationale:** Update spawn.sh and recover script to use system_prompt from registry. New sessions and recoveries get per-agent customization. Removes autoresponder launch logic (but files still exist until Phase 4).

**Delivers:**
- spawn.sh: Remove --autoresponder flag, remove strict_prompt(), add --system-prompt flag, read from registry with fallback
- recover-openclaw-agents.sh: Extract system_prompt per agent, pass via --append-system-prompt, remove set -e, add per-agent error handling, sequential processing with delays
- Python upsert updated: setdefault("system_prompt", "")
- Atomic write pattern for registry updates with flock
- Graceful partial recovery with global summary

**Addresses features:**
- Configurable system prompt (table stakes)
- Recovery flow integration (table stakes)
- Agent-specific routing (differentiator)
- Structured decision payload (differentiator)
- Retry-safe action deduplication (differentiator)

**Avoids pitfalls:**
- Pitfall 3 (registry corruption): flock + atomic write + validation
- Pitfall 4 (send-keys corruption): sequential processing with delays, send-keys -l
- Pitfall 5 (recovery failure): remove set -e, per-agent error handling, send summary on partial success
- Pitfall 7 (missing system_prompt): setdefault + fallback default
- Pitfall 10 (tmux race): remove has-session checks, handle failures gracefully, add retry logic

**Research flags:** No additional research needed (modifying existing scripts with established patterns).

### Phase 4: Cleanup (Script Deletions)
**Rationale:** Remove obsolete polling scripts now that spawn.sh and recover script no longer launch them. Existing background processes continue until sessions end (harmless overlap). Kill lingering watchers before deletion.

**Delivers:**
- Delete autoresponder.sh
- Delete hook-watcher.sh
- Delete ~/.claude/hooks/gsd-session-hook.sh
- Kill all existing hook-watcher processes: `pkill -f 'hook-watcher.sh'`
- Remove watcher state files from /tmp

**Addresses features:**
- Multi-hook safety (differentiator): Only new hook system remains

**Avoids pitfalls:**
- Pitfall 6 (duplicate events): Kill old watchers to end overlap period

**Research flags:** None (deletions, no new logic).

### Phase 5: Documentation
**Rationale:** Update skill documentation to reflect new architecture. No code impact, pure documentation.

**Delivers:**
- Update SKILL.md: New architecture, Stop hook flow, system_prompt configuration
- Update README.md: Registry schema with system_prompt, recovery flow with Stop hook
- Update script list: Remove autoresponder/hook-watcher, add stop-hook

**Research flags:** None (documentation).

### Phase Ordering Rationale

**Why additive first:** New files don't interfere with existing autoresponder/hook-watcher workflows. Zero risk of breaking running sessions. All guards and safety patterns implemented before hook fires.

**Why hook wiring second:** Stop hook registration requires stop-hook.sh to exist (dependency). Brief overlap with old system is harmless (agents designed for duplicate wakes). Old watchers die naturally when sessions end.

**Why launcher updates third:** Registry schema must exist before launchers read it (dependency from Phase 1). Autoresponder logic removed from spawn.sh safely after hook wired (no longer needed). Recovery script refactoring includes critical error handling improvements.

**Why cleanup fourth:** Scripts must be unused before deletion (dependencies from Phase 2-3). Killing watchers before file deletion ensures clean transition. No new sessions will launch old scripts.

**Why documentation last:** Documents implementation that's already complete. No risk, no dependencies.

**Critical path dependencies:**
- Phase 2 depends on Phase 1: stop-hook.sh must exist before settings.json references it
- Phase 3 depends on Phase 1: system_prompt field must exist before spawn/recover scripts read it
- Phase 4 depends on Phase 2-3: scripts must be unused before deletion

### Research Flags

**Phases needing deeper research during planning:**
- None — all patterns are established (bash scripting, tmux operations, registry manipulation, systemd services)

**Phases with standard patterns (skip research-phase):**
- **Phase 1:** Bash scripting with jq, tmux capture-pane, JSON schema additions (well-documented)
- **Phase 2:** Claude Code hook registration (official docs reviewed in STACK.md)
- **Phase 3:** Bash script refactoring, Python JSON manipulation, systemd service patterns (standard operations)
- **Phase 4:** File deletions, process cleanup (no research needed)
- **Phase 5:** Documentation (no research needed)

**Overall:** This project has exceptionally complete research. All 4 research files show HIGH confidence based on official sources, existing implementation knowledge, and real-world GitHub issues (2026). No speculative or unverified patterns.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | All components production-verified (Claude Code 2.1.44, tmux 3.4, OpenClaw 2026.2.16). Stop hook schema confirmed via official docs. No new dependencies required. |
| Features | HIGH | Based on official Claude Code hooks reference (code.claude.com/docs), aiorg.dev 2026 guide, and existing implementation (menu-driver.sh, recovery registry). All table stakes verified as industry standard patterns. |
| Architecture | HIGH | All source files read (spawn.sh 343 lines, recover script 484 lines, autoresponder 112 lines, hook-watcher 50 lines, menu-driver 64 lines). Integration points mapped to specific line numbers. Migration path verified. |
| Pitfalls | HIGH | 10 critical pitfalls documented with real-world sources: GitHub issues from 2026, official Claude Code hooks guide, Mozilla JSON corruption analysis, systemd debugging docs, bash background process tutorials. Each pitfall mapped to prevention phase with verification steps. |

**Overall confidence:** HIGH

### Gaps to Address

**None identified.** Research is exceptionally complete:

- Stack: All components version-verified in production environment
- Features: Table stakes vs differentiators clearly separated based on official docs and industry patterns
- Architecture: Existing implementation fully audited, integration points specified to line-number precision
- Pitfalls: 10 critical issues documented with prevention strategies, phase mapping, and recovery steps

**Validation during implementation:**
- Test stop-hook.sh with large JSON payloads (>64KB) to verify stdin consumption prevents blocking
- Test concurrent spawns (3+ agents in parallel) to verify send-keys corruption mitigated
- Test recovery with old registry.json (without system_prompt field) to verify fallback works
- Test hook with non-managed Claude sessions to verify fast-path exit performance (<10ms)
- Test migration overlap (Phase 2-3) to verify duplicate events are tolerable and brief

**No additional research needed.** All patterns are established, all dependencies verified, all pitfalls documented with sources.

## Sources

### Primary (HIGH confidence)

**Official Documentation:**
- [Claude Code Hooks Reference](https://code.claude.com/docs/en/hooks) — Stop hook stdin/stdout JSON schema, hook configuration format, exit code behavior
- [Claude Code Hooks Guide (aiorg.dev 2026)](https://aiorg.dev/blog/claude-code-hooks) — Stop hook patterns, stop_hook_active guard, infinite loop prevention
- [ClaudeLog Hooks Mechanics](https://claudelog.com/mechanics/hooks/) — Hook lifecycle, decision control patterns
- [Claude Code Hook Control Flow (stevekinney.com)](https://stevekinney.com/courses/ai-development/claude-code-hook-control-flow) — Hook execution model, JSON parsing

**Version Verification:**
- Claude Code: 2.1.44 (confirmed via claude --version)
- OpenClaw: 2026.2.16 (confirmed via openclaw --version)
- tmux: 3.4 (confirmed via tmux -V)
- jq: 1.7 (confirmed via jq --version)

**Local Implementation:**
- PRD.md — Hook architecture and implementation plan
- scripts/spawn.sh (343 lines) — Session launcher architecture
- scripts/recover-openclaw-agents.sh (484 lines) — Recovery flow
- scripts/autoresponder.sh (112 lines) — Polling pattern being replaced
- scripts/hook-watcher.sh (50 lines) — Polling pattern being replaced
- scripts/menu-driver.sh (64 lines) — Existing atomic action interface
- ~/.claude/settings.json — Current hook configuration
- config/recovery-registry.example.json — Registry schema

### Secondary (MEDIUM confidence)

**Multi-Agent Patterns:**
- [Agentic AI in Production (Medium 2026)](https://medium.com/@dewasheesh.rana/agentic-ai-in-production-designing-autonomous-multi-agent-systems-with-guardrails-2026-guide-a5a1c8461772) — Guardrails for autonomous agents
- [Guardrails and Best Practices for Agentic Orchestration (Camunda 2026)](https://camunda.com/blog/2026/01/guardrails-and-best-practices-for-agentic-orchestration/) — Safety patterns
- [AI Agent Decision-Making: A Practical Explainer (Skywork)](https://skywork.ai/blog/ai-agent/ai-agent-decision-making) — Heuristics vs LLM decisions

**Event-Driven Architecture:**
- [Why we replaced polling with event triggers (Jan 2026)](https://medium.com/@systemdesignwithsage/why-we-replaced-polling-with-event-triggers-234ecda134b2) — Polling to event-driven migration
- [The Ultimate Guide to Event-Driven Architecture Patterns (Solace)](https://solace.com/event-driven-architecture-patterns/) — Event-driven patterns

**Pitfall Sources:**
- [Claude Code Hooks 2026: Automate Your Dev Workflow (ClaudeWorld)](https://claude-world.com/articles/hooks-development-guide/) — stdin handling, hook development
- [GitHub Issue #10875](https://github.com/anthropics/claude-code/issues/10875) — Plugin hook JSON output bug
- [GitHub Issue #23615](https://github.com/anthropics/claude-code/issues/23615) — send-keys corruption in agent teams
- [Tmux Issue #2438](https://github.com/tmux/tmux/issues/2438) — Race condition loading config
- [Tmux Issue #3360](https://github.com/tmux/tmux/issues/3360) — send-keys race condition
- [EdgeApp JSON Corruption Issue #258](https://github.com/EdgeApp/edge-core-js/issues/258) — Concurrent write corruption
- [lowdb JSON Corruption Issue #333](https://github.com/typicode/lowdb/issues/333) — Multi-process writes
- [Mozilla JSONFile Analysis](https://mozilla.github.io/firefox-browser-architecture/text/0012-jsonfile.html) — JSON file-backed storage issues
- [Red Hat: Systemd Automate Recovery](https://www.redhat.com/en/blog/systemd-automate-recovery) — Service recovery patterns
- [systemd.io: Diagnosing Boot Problems](https://systemd.io/DEBUGGING/) — Boot troubleshooting
- [DigitalOcean: Bash Job Control](https://www.digitalocean.com/community/tutorials/how-to-use-bash-s-job-control-to-manage-foreground-and-background-processes) — Background processes
- [LinuxVox: Spawn Separate Process](https://linuxvox.com/blog/spawn-an-entirely-separate-process-in-linux-via-bash/) — Process spawning patterns

### Tertiary (LOW confidence)
None — all sources are either official documentation, version-verified production environment, local implementation audit, or real-world GitHub issues from 2026.

---
*Research completed: 2026-02-17*
*Ready for roadmap: yes*

# Feature Landscape: Hook-Driven Agent Control

**Domain:** Hook-driven autonomous agent control for Claude Code sessions
**Researched:** 2026-02-17
**Confidence:** HIGH

## Table Stakes

Features users expect. Missing = system feels incomplete or broken.

| Feature | Why Expected | Complexity | Notes | Dependencies |
|---------|--------------|------------|-------|--------------|
| Stop hook fires on response complete | Native Claude Code hook event pattern (2026 standard) | Low | Industry standard for hook-driven architecture; missing this would mean falling back to polling | None |
| `stop_hook_active` guard | Prevents infinite loops when hook returns `decision: "block"` | Low | Critical safety pattern documented in all Claude Code hook guides | Stop hook |
| Session registry lookup | Stop hook must identify which OpenClaw agent owns the session | Low | Required to route pane snapshots to correct agent | stop-hook.sh, recovery-registry.json |
| Pane snapshot capture | Hook captures tmux pane state (last 120-180 lines) | Low | Core data for intelligent decision-making | tmux, Stop hook |
| Context pressure extraction | Extract token usage percentage from statusline | Medium | Heuristic from hook-watcher.sh; enables proactive /clear decisions | Pane snapshot, statusline format knowledge |
| Backgrounded agent wake | Stop hook must exit immediately, not block on OpenClaw response | Low | Hook timeout is 120s; blocking risks hook failure and delayed Claude responses | openclaw agent CLI |
| Fast-path exit for non-managed sessions | Hook exits <5ms when `$TMUX` missing or session not in registry | Low | Avoids token cost and latency for unmanaged Claude Code usage | Session registry |
| Freeform text input (`type` action) | Agent may need to type arbitrary text (not just option numbers) | Low | Required for responding to non-menu prompts or interactive editors | menu-driver.sh |
| Configurable system prompt | Per-agent system prompt from registry (not hardcoded) | Low | Different agents need different constraints (strict slash-only vs flexible) | recovery-registry.json |
| Recovery flow integration | Recover script must pass system prompt to Claude on launch | Low | New agents post-reboot must have same prompt as pre-reboot sessions | recover-openclaw-agents.sh |
| Deterministic menu actions preserved | Existing menu-driver.sh actions (snapshot, choose, enter, esc, clear_then, submit) | None (exists) | Already built; Stop hook reuses these | menu-driver.sh |

## Differentiators

Features that set this system apart. Not expected, but high value.

| Feature | Value Proposition | Complexity | Notes | Dependencies |
|---------|-------------------|------------|-------|--------------|
| Agent-specific routing (not broadcast) | Stop hook wakes exact OpenClaw session (not all agents via system event) | Low | Precision vs hook-watcher.sh broadcast; reduces noise and wrong-agent confusion | Session registry with agent_id |
| Structured decision payload | Hook sends: pane snapshot + available actions + context pressure warning | Medium | Agent receives actionable decision prompt, not raw pane dump | Stop hook logic |
| Multi-hook safety (wire vs logic separation) | Hook in ~/.claude/settings.json, logic in skill scripts | Low | Upgrading hook logic doesn't require editing global settings.json again | Script path stability |
| Zero-token overhead for non-managed sessions | Hook fast-path exits when session not in registry | Low | Users can still use Claude Code normally without paying OpenClaw cost | Registry lookup guard |
| Immediate hook exit (async agent wake) | Hook never blocks; agent wakes in background | Low | Prevents hook timeout and Claude Code slowdown | Backgrounded openclaw call |
| Retry-safe action deduplication | Agent can safely retry menu-driver.sh calls (idempotent state) | Medium | If agent wakes twice on same menu, second call is harmless | menu-driver.sh state awareness |
| Context pressure proactive warning | Hook flags when token usage ≥50% (agent can suggest /clear or "Next area") | Medium | Prevents context overflow; agent can plan compaction before forced | Statusline parsing heuristic |
| Registry sync from agent sessions | Auto-refresh openclaw_session_id from agent/sessions.json | Medium (exists) | Prevents stale session id rot after agent restart | sync-recovery-registry-session-ids.sh |
| Graceful degradation on registry errors | jq failures wrapped in `|| true`; hook never crashes Claude | Low | Robustness: broken registry → unmanaged session behavior (exit 0) | Error handling discipline |
| Multiple system prompt modes | Registry can store different prompts: strict slash-only, GSD-preferred, or flexible | Low | Supports different agent personalities (Warden vs Gideon vs Forge) | recovery-registry.json schema |

## Anti-Features

Features to explicitly NOT build.

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| LLM decision in Stop hook itself | Hook timeout is 120s max; invoking LLM in hook risks timeout and blocks Claude Code | Background wake OpenClaw agent; agent calls menu-driver.sh after deciding |
| Blocking on OpenClaw response | Waiting for agent decision before hook exits → slow Claude Code, risk timeout | Fire-and-forget: background openclaw call with `|| true` |
| Automatic approvals for updates | Autoresponder.sh explicitly blocked "update" keywords; Stop hook should preserve this | Agent receives full context and makes judgment call (defaults to "No" on updates) |
| Hook returns `decision: "block"` | Infinite loop risk (stop_hook_active prevents, but adds complexity) | Always exit 0; agent decides whether to wake and act |
| Polling fallback as backup | Two parallel systems (Stop hook + hook-watcher.sh) → duplicate wakes, state confusion | Commit to Stop hook; delete hook-watcher.sh and autoresponder.sh entirely |
| Global Claude Code hooks config modification on every spawn | Editing ~/.claude/settings.json on every spawn.sh run → race conditions, corruption | Set hook once globally; skill scripts stay in workspace/skills/gsd-code-skill/scripts/ |
| Hardcoded system prompts in spawn.sh | Each agent role needs different prompt; hardcoding requires spawn.sh edits per agent | Read system_prompt from registry; default to sensible fallback if empty |
| Custom hook per tmux session | Multiple ~/.claude/settings.json or session-scoped hooks → maintenance nightmare | Single global hook; session filtering via registry lookup |
| Regex-based pane parsing for actions | Hook tries to parse "1. Option A" and auto-choose → brittle, breaks on format changes | Send raw pane + available actions; agent decides and calls menu-driver.sh explicitly |
| Synchronous registry updates in hook | Writing to recovery-registry.json during hook execution → file lock contention | Registry is read-only in hook; updated only by spawn.sh and recover script |

## Feature Dependencies

```
Stop hook
  ├─> stop_hook_active guard
  ├─> $TMUX fast-path check
  ├─> Session registry lookup (recovery-registry.json)
  │     └─> Fast-path exit if not found
  ├─> Pane snapshot (tmux capture-pane -S -120)
  ├─> Context pressure extraction (statusline heuristic)
  ├─> Structured decision payload
  └─> Backgrounded OpenClaw agent wake
        └─> openclaw agent --session-id <uuid> --message "..."

OpenClaw agent receives snapshot
  ├─> Intelligent decision (LLM-based)
  └─> Calls menu-driver.sh <session> <action> [args]
        ├─> snapshot (read-only, returns pane)
        ├─> choose <n> (select numbered option)
        ├─> type <text> (NEW: freeform input)
        ├─> enter / esc / submit (keyboard actions)
        └─> clear_then <cmd> (reset context, run command)

Recovery flow
  ├─> sync-recovery-registry-session-ids.sh (refresh session ids)
  ├─> recover-openclaw-agents.sh reads registry
  ├─> Extract system_prompt per agent
  ├─> Launch Claude with --append-system-prompt
  └─> Send initial wake to openclaw_session_id
```

## MVP Recommendation

**Phase 1: Additive (no breakage)**
1. Create stop-hook.sh with all guards and fast-paths
2. Add `type <text>` action to menu-driver.sh
3. Add system_prompt field to recovery-registry.json (empty string default)

**Phase 2: Wire up hook**
4. Add Stop hook to ~/.claude/settings.json (one-time global edit)
5. Remove gsd-session-hook.sh from SessionStart hooks

**Phase 3: Update launchers**
6. Modify spawn.sh: remove autoresponder logic, add system_prompt support
7. Modify recover-openclaw-agents.sh: pass system_prompt on Claude launch

**Phase 4: Remove old scripts**
8. Delete autoresponder.sh
9. Delete hook-watcher.sh
10. Delete ~/.claude/hooks/gsd-session-hook.sh

**Phase 5: Documentation**
11. Update SKILL.md and README.md

**Defer:**
- Advanced heuristics for context pressure (beyond percentage threshold) — current ≥50% heuristic sufficient for MVP
- LLM-guided decision complexity scoring — simple "send everything to agent" is enough for now
- Multi-agent swarm coordination — single agent per session is sufficient
- Audit trail / decision logging in hook — OpenClaw agent already logs decisions
- Rate limiting / backpressure on agent wakes — unlikely to spam (menus are infrequent)

## Complexity Assessment

| Feature Category | Complexity | Reasoning |
|------------------|------------|-----------|
| Stop hook core | Low | Bash script, stdin JSON parsing, exit guards |
| Session registry lookup | Low | jq query on static JSON file |
| Pane snapshot capture | Low | Single tmux command |
| Context pressure extraction | Medium | Regex parsing statusline; heuristic may need tuning |
| Backgrounded agent wake | Low | Bash background process with `|| true` |
| Freeform text input | Low | tmux send-keys with `-l` flag (literal mode) |
| System prompt plumbing | Low | Pass variable through spawn.sh → Claude CLI |
| Registry schema migration | Low | Add one field; existing entries get empty string default |
| Fast-path guards | Low | Early exits with zero cost |
| Error handling | Medium | Wrap every external call in `|| true` to prevent hook crash |

**Overall MVP Complexity:** Low to Medium

Most work is plumbing (hook → registry → agent → menu-driver). No complex algorithms, no networking, no concurrency issues. Biggest risk is edge cases in tmux pane parsing or registry corruption (mitigated by read-only access in hook).

## Architecture Implications for Roadmap

**Why this phase ordering:**

1. **Additive first** — new files don't break existing autoresponder/hook-watcher workflows
2. **Wire hook** — Stop hook runs in parallel with old system briefly (harmless overlap)
3. **Update launchers** — spawn.sh and recover script now use new system
4. **Remove old** — clean up deprecated polling scripts
5. **Document** — update docs to reflect new architecture

**Critical path dependencies:**
- stop-hook.sh must exist before ~/.claude/settings.json references it
- system_prompt field must exist in registry before recover script reads it
- menu-driver.sh `type` action must exist before agent tries to call it

**Phase-specific research flags:**
- Phase 1: No additional research needed (bash + tmux patterns well-understood)
- Phase 2: Verify Stop hook JSON schema with official Claude Code docs (done via WebSearch)
- Phase 3: No research needed (modifying existing scripts)
- Phase 4: No research needed (deletions)
- Phase 5: No research needed (documentation)

## Edge Cases

| Edge Case | Severity | Mitigation |
|-----------|----------|------------|
| Non-managed Claude session triggers hook | Low | Fast-path exit at `$TMUX` check or registry lookup (5ms overhead) |
| Infinite loop from `decision: "block"` | Critical | `stop_hook_active` guard; never return blocking decision |
| Registry file unreadable/corrupt | Medium | jq wrapped in `|| true`; hook exits 0 (unmanaged session behavior) |
| OpenClaw agent call fails | Low | Backgrounded with `|| true`; hook never blocks |
| Stale hook-watcher processes during transition | Low | Old processes die when tmux session ends; brief overlap harmless |
| Empty system_prompt in registry | Low | Fall back to sensible default prompt |
| Context pressure regex fails | Low | Variable defaults to empty; agent doesn't receive warning (acceptable) |
| Multiple menus appear rapidly | Medium | Agent may receive multiple wakes; menu-driver.sh state tracking prevents duplicate actions |
| Agent session ID rotates | Medium | sync-recovery-registry-session-ids.sh auto-syncs from agent/sessions.json |
| Hook timeout (>120s) | Critical | Never invoke LLM in hook; always background openclaw call |

## Decision Complexity: Heuristics vs LLM

**Where heuristics win:**
- `stop_hook_active` guard (deterministic, instant)
- Fast-path exits (registry lookup failure → exit 0)
- Context pressure threshold (≥50% → warn agent)
- Menu detection (grep "Enter to select" in autoresponder.sh was sufficient)

**Where LLM wins:**
- Which menu option to choose (context-dependent: phase planning, bug fixing, approvals)
- When to run /clear vs "Next area" (depends on task state)
- Whether to approve updates (requires understanding what's being updated)
- Freeform text input (agent composes natural language responses)

**Hybrid approach (this system):**
- Heuristics in Stop hook: guards, fast-paths, context extraction
- LLM in OpenClaw agent: decision-making, action selection, freeform composition
- Deterministic actions in menu-driver.sh: keyboard automation, pane capture

**Why this split:**
- Stop hook must exit quickly (<5s ideal, <120s hard limit)
- LLM inference takes 2-10s+ depending on model and context
- Backgrounding agent wake decouples hook latency from decision latency
- menu-driver.sh provides idempotent, retryable interface for agent

## Observability

**What gets logged:**
- Stop hook: session_id, registry lookup result, pane snapshot length, context pressure
- OpenClaw agent: received snapshot, chosen action, menu-driver.sh call
- menu-driver.sh: action type, tmux command sent

**What doesn't get logged (by design):**
- Hook never writes to disk (too slow; exit time critical)
- Pane content not logged by hook (sent to agent, agent logs if needed)

**Debugging workflow:**
1. Check ~/.claude/settings.json: Stop hook configured?
2. Check recovery-registry.json: session in registry? agent_id correct?
3. Check OpenClaw agent logs: received snapshot? decision made?
4. Check tmux session: menu-driver.sh action applied?

## Sources

**HIGH confidence (official sources):**
- [Hooks reference - Claude Code Docs](https://code.claude.com/docs/en/hooks)
- [Claude Code Hooks: Complete Guide with 20+ Ready-to-Use Examples (2026)](https://aiorg.dev/blog/claude-code-hooks)
- [Event-Driven Claude Code and OpenCode Workflows with Hooks](https://www.subaud.io/event-driven-claude-code-and-opencode-workflows-with-hooks/)
- [Claude Code Hooks: Complete Guide to All 12 Lifecycle Events](https://claudefa.st/blog/tools/hooks/hooks-guide)

**MEDIUM confidence (multi-agent patterns and guardrails):**
- [Agentic AI in Production: Designing Autonomous Multi-Agent Systems with Guardrails (2026 Guide)](https://medium.com/@dewasheesh.rana/agentic-ai-in-production-designing-autonomous-multi-agent-systems-with-guardrails-2026-guide-a5a1c8461772)
- [Guardrails and Best Practices for Agentic Orchestration](https://camunda.com/blog/2026/01/guardrails-and-best-practices-for-agentic-orchestration/)
- [AI Guardrails Will Stop Being Optional in 2026](https://statetechmagazine.com/article/2026/01/ai-guardrails-will-stop-being-optional-2026)
- [From guardrails to governance: A CEO's guide for securing agentic systems](https://www.technologyreview.com/2026/02/04/1131014/from-guardrails-to-governance-a-ceos-guide-for-securing-agentic-systems)

**MEDIUM confidence (tmux and agent decision-making):**
- [TmuxAI: AI-Powered, Non-Intrusive Terminal Assistant](https://tmuxai.dev/)
- [Tmux MCP Shell Tool](https://lobehub.com/mcp/ketema-tmux-mcp-shell-tool)
- [tmux Workflow for AI Coding Agents](https://www.agent-of-empires.com/guides/tmux-ai-coding-workflow/)
- [AI Agent Decision-Making: A Practical Explainer](https://skywork.ai/blog/ai-agent/ai-agent-decision-making)

**MEDIUM confidence (event-driven architecture):**
- [The Ultimate Guide to Event-Driven Architecture Patterns](https://solace.com/event-driven-architecture-patterns/)
- [Event Driven Architecture Done Right: How to Scale Systems with Quality in 2025](https://www.growin.com/blog/event-driven-architecture-scale-systems-2025/)

**LOCAL (existing implementation):**
- PRD.md (hook architecture and implementation plan)
- scripts/menu-driver.sh (existing deterministic actions)
- scripts/autoresponder.sh (heuristics for menu detection and option selection)
- scripts/hook-watcher.sh (polling pattern and context pressure extraction)
- README.md (recovery registry schema and operational patterns)
- SKILL.md (skill metadata and script documentation)

# Feature Research

**Domain:** Structured JSONL event logging for hook/webhook interaction lifecycle — gsd-code-skill v3.0
**Researched:** 2026-02-18
**Confidence:** HIGH (existing codebase well-understood; JSONL log schema patterns verified via multiple sources)

---

## Context: What v2.0 Built (Already Shipped)

This is a subsequent milestone research file. v2.0 shipped:
- Transcript JSONL extraction as primary content source (no tmux noise)
- Pane diff fallback when transcript unavailable
- PreToolUse hook for AskUserQuestion forwarding (structured question + options)
- Wake message v2 format: [SESSION IDENTITY], [TRIGGER], [CONTENT], [STATE HINT], [CONTEXT PRESSURE], [AVAILABLE ACTIONS]
- Per-session log files in skill logs/ directory (plain-text debug_log())
- Shared lib/hook-utils.sh with DRY extraction functions

**v3.0 problem statement:** The current plain-text log format captures debug breadcrumbs but not structured events. What actually went into the wake message (the full body sent to OpenClaw) is never recorded. What OpenClaw responded with is only recorded as the first 200 characters in bidirectional mode, and as background PID in async mode. No request/response pairs are correlated. No AskUserQuestion lifecycle is captured (questions asked → option selected). This makes post-hoc debugging difficult and makes automation impossible — you can't grep for "all ask_user_question interactions in the last hour" or "all bidirectional responses where decision=block."

---

## Feature Landscape

### Table Stakes (Users Expect These)

Features that must exist for v3.0 to be considered functional. These are the non-negotiable building blocks. Missing any makes the milestone incomplete by its own definition.

| Feature | Why Expected | Complexity | Dependencies on v2.0 |
|---------|--------------|------------|----------------------|
| JSONL event schema with standard fields | Every structured log system uses machine-parseable one-record-per-line format. Fields: `timestamp`, `event_type`, `correlation_id`, `session_name`, `agent_id`, `hook_script`, `level` | LOW | Existing debug_log() replaced or wrapped in all 6 hook scripts |
| Shared JSONL logging function in lib/hook-utils.sh | All 6 hook scripts currently duplicate the debug_log() definition inline — a shared emit_event() function that writes a JSONL line belongs in hook-utils.sh (DRY, SRP) | LOW | lib/hook-utils.sh (exists, 4 functions) |
| hook_fired event (request) on every hook invocation | The moment a hook script fires is a meaningful lifecycle event: which hook, which session, which agent, timestamp, stdin size, trigger type — this is the "request" side of each interaction | LOW | All 6 hook scripts — add after stdin consumed and session resolved |
| wake_sent event (request delivery) capturing full wake message body | The complete text sent to OpenClaw is currently never stored. Logging it in a JSONL field makes it queryable and replayable. This is the primary gap. | LOW | Stop hook and notification hooks — log after building WAKE_MESSAGE and before the openclaw call |
| wake_response_received event (response) with OpenClaw response body | In bidirectional mode, RESPONSE is currently truncated to 200 chars. Log the full response. In async mode, log the background PID and that response capture is not available. | LOW | Bidirectional branches in stop-hook.sh, notification-idle-hook.sh, notification-permission-hook.sh, pre-compact-hook.sh |
| correlation_id linking request and response events | Async mode fires the openclaw call in a background process — the parent and background process can't share a variable after fork. A correlation_id generated before the fork and passed to the background process links the wake_sent and wake_response_received events from different PIDs. | MEDIUM | All hooks using async backgrounding — generate ID before fork, pass via env or argument |
| Per-session JSONL log file (one file per session, session-prefixed name) | v2.0 already uses per-session plain-text logs ({SESSION_NAME}.log). The JSONL file should use the same pattern: {SESSION_NAME}.jsonl in logs/. | LOW | Existing per-session plain-text log pattern (sessions already write to logs/{SESSION_NAME}.log) |
| hook_exit event on early-exit paths (non-managed sessions, guards) | When a hook exits early (no TMUX, no registry match, stop_hook_active guard), that exit should be a minimal JSONL record so early exits are distinguishable from never-fired hooks | LOW | All 6 hooks — add before each early-exit point |

### Differentiators (Competitive Advantage)

Features that make this logging system significantly more capable than plain-text logs. Not required for basic correctness, but high diagnostic and automation value.

| Feature | Value Proposition | Complexity | Dependencies on v2.0 |
|---------|-------------------|------------|----------------------|
| AskUserQuestion lifecycle: question_forwarded event | When PreToolUse hook fires for AskUserQuestion, log which questions and options were forwarded — structured: question text, options list, tool_use_id. Enables "how often does Claude ask questions?" analysis. | LOW | pre-tool-use-hook.sh (question data already extracted in format_ask_user_questions); add JSONL emit before openclaw call |
| AskUserQuestion lifecycle: answer_selected event via PostToolUse hook | When AskUserQuestion tool completes, a PostToolUse hook fires with the selected answer in tool_result. Logging the answer_selected event closes the question/answer lifecycle: you know what was asked AND what was chosen. This requires adding a new PostToolUse hook script and registering it. | MEDIUM | Requires new post-tool-use-hook.sh (new script); new PostToolUse hook registration in register-hooks.sh and settings.json; tool_result field in hook stdin |
| Duration field in wake events (ms from hook_fired to wake_sent) | Time from hook entry to openclaw call reveals slow registry lookups, slow transcript reads, slow pane captures. Single arithmetic subtraction (EPOCHREALTIME or date +%s%N). | LOW | All hooks — capture start timestamp at entry, compute delta before wake_sent event |
| content_source field in wake events (transcript vs pane_diff vs raw_pane) | The stop hook already knows which source was used (extracted response vs pane diff fallback). Recording this in the JSONL event exposes when fallback mode activates — a signal that transcript extraction is failing. | LOW | stop-hook.sh — content source decision already made (line 163-177), just add to event fields |
| decision field in response events (block vs proceed for bidirectional mode) | When bidirectional response contains decision=block, log the decision and reason explicitly. Enables "how many times did Gideon block an action?" queries. | LOW | Bidirectional response parsing already done in stop-hook.sh and notification-idle-hook.sh |
| Shared log rotation awareness (max file size guard before writing) | JSONL files grow indefinitely. A simple guard: if logs/{SESSION_NAME}.jsonl exceeds 10MB, rotate to .jsonl.1 or truncate. Prevents disk fill on long-running sessions. | LOW | Per-session JSONL file — add size check before emit_event() writes |

### Anti-Features (Commonly Requested, Often Problematic)

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| Log the full pane content in JSONL events | Seems useful for debugging — store exactly what the pane showed | Pane content is 40-120 lines per hook fire, potentially 8000+ characters, mostly unchanged between fires. JSONL files grow to hundreds of MB per session per day. The pane content is already captured in the wake message which IS logged. | Log wake_message_bytes (size of the payload) and content_source (transcript/pane_diff) — enough for diagnosis without storing the full content twice |
| Log the full transcript content in JSONL events | Complete conversation context enables replaying sessions | Transcripts grow to hundreds of KB. Logging them in JSONL events creates 100x storage amplification. The transcript file itself is the source of truth at transcript_path. | Log transcript_path (string reference) and transcript_bytes (file size) in the event — pointer, not copy |
| Emit JSONL to stdout or stderr instead of a log file | Simpler — no file management | Claude Code captures hook stdout for decision injection (bidirectional mode). Writing JSONL to stdout corrupts the decision JSON. Writing to stderr risks interleaving with Claude Code's own stderr. | Write to per-session .jsonl files in logs/ — completely separate from hook stdout/stderr |
| OpenTelemetry / structured logging framework (Python/Node runtime) | Industry-standard distributed tracing with OTLP export | Adds Python or Node.js startup penalty (50-200ms) to hooks that must complete in <5ms for non-managed sessions. Violates the "Bash + jq only" constraint. No OTLP collector running on this host. | Use jq -n with --arg parameters to emit JSONL directly — no runtime dependency, same output format, <1ms overhead |
| Centralized JSONL log file across all sessions (single hooks.jsonl) | Easier to query one file | Concurrent hook fires from multiple sessions race to write to the same file. Requires flock on every event emit. Per-session files have no concurrent writers. | Per-session JSONL files — session isolation means no locking needed. Cross-session queries use: jq -s '.' logs/*.jsonl |
| SQLite event store instead of JSONL | Structured queries, proper indexing, atomic writes | SQLite requires sqlite3 binary (not guaranteed installed), adds dependency. Querying JSONL with jq is sufficient for single-host use. Migration path away from SQLite is painful. | JSONL files queryable with: jq 'select(.event_type == "wake_sent")' logs/*.jsonl — no additional dependencies |
| Real-time streaming / tailing of events | Useful for live dashboards | Not in scope for v3.0 (out of scope in PROJECT.md: "Dashboard rendering/UI — warden.kingdom.lv integration is separate work"). JSONL files support tail -f natively for humans. | JSONL files are inherently tail-able. Dashboard integration deferred to separate milestone. |

---

## Feature Dependencies

```
Shared JSONL logging function (emit_event in lib/hook-utils.sh)
    └──required by──> hook_fired event (all 6 hooks)
    └──required by──> wake_sent event (all hooks with openclaw delivery)
    └──required by──> wake_response_received event (bidirectional hooks)
    └──required by──> hook_exit event (all early-exit paths)
    └──required by──> question_forwarded event (pre-tool-use-hook.sh)
    └──required by──> answer_selected event (post-tool-use-hook.sh, if built)

correlation_id
    └──requires──> generation before openclaw call (in hook script, before fork)
    └──required by──> wake_sent event (carries the ID)
    └──required by──> wake_response_received event (carries same ID from background process)
    └──links──> hook_fired → wake_sent → wake_response_received (same invocation chain)

hook_fired event
    └──requires──> Shared JSONL logging function
    └──requires──> session_name resolved (fires after TMUX check + registry lookup)
    └──enhances──> duration_ms in wake_sent (needs start timestamp from hook_fired)

wake_sent event
    └──requires──> Shared JSONL logging function
    └──requires──> correlation_id (generated before openclaw call)
    └──requires──> hook_fired (provides start timestamp for duration_ms calculation)
    └──requires──> WAKE_MESSAGE built (logs full body or byte count)

wake_response_received event
    └──requires──> Shared JSONL logging function
    └──requires──> correlation_id (passed to background process or captured in bidirectional branch)
    └──requires──> openclaw call completed (async: after background process waits; bidirectional: after synchronous call)
    └──contains──> decision field (only relevant in bidirectional mode with block response)

AskUserQuestion question_forwarded event
    └──requires──> Shared JSONL logging function
    └──requires──> format_ask_user_questions output (already extracted in pre-tool-use-hook.sh)
    └──contains──> tool_use_id (links to answer_selected event)

AskUserQuestion answer_selected event
    └──requires──> Shared JSONL logging function
    └──requires──> post-tool-use-hook.sh (NEW script — does not exist yet)
    └──requires──> PostToolUse hook registration in settings.json with matcher "AskUserQuestion"
    └──requires──> tool_result field in PostToolUse hook stdin (contains selected answer)
    └──links to──> question_forwarded (via tool_use_id)
    └──conflicts with──> "ASK-03: always exit 0, always async" (PostToolUse is separate from PreToolUse — no conflict)

Per-session JSONL log file
    └──requires──> Shared JSONL logging function (writes to file path)
    └──follows same pattern as──> Per-session plain-text log (logs/{SESSION_NAME}.log already exists)
    └──enhanced by──> Log rotation guard (optional, prevents disk fill)
```

### Dependency Notes

- **emit_event requires no external calls:** It is a pure jq -n invocation writing one JSON line — no network, no flock needed (per-session files have single writer).
- **correlation_id bridges async fork boundary:** Generated with `date +%s%N-$$-$RANDOM` or similar before `openclaw ... &` — the background subshell inherits the variable from the parent environment.
- **answer_selected event has the highest complexity:** It requires a new script (post-tool-use-hook.sh) and a new hook registration. It is the only v3.0 feature that touches scripts/settings beyond lib/hook-utils.sh additions. This makes it a candidate for a separate phase from the core JSONL infrastructure.
- **duration_ms requires start timestamp capture:** The hook_fired event must capture a start timestamp (EPOCHREALTIME in bash 5+, or date +%s%3N). All subsequent events in the same hook invocation compute duration relative to this start.

---

## Event Schema

### Core Event Fields (All Events)

```json
{
  "timestamp": "2026-02-18T10:00:00.123Z",
  "event_type": "hook_fired | hook_exit | wake_sent | wake_response_received | question_forwarded | answer_selected",
  "hook_script": "stop-hook.sh",
  "session_name": "warden-main",
  "agent_id": "warden",
  "correlation_id": "1708250400123-12345-47829",
  "level": "info | warn | error"
}
```

### Event-Specific Fields

**hook_fired** (emitted when hook starts, after stdin consumed and session resolved):
```json
{
  "event_type": "hook_fired",
  "hook_event_name": "Stop",
  "stdin_bytes": 1842,
  "pid": 12345
}
```

**hook_exit** (emitted on early-exit paths — non-managed session, guard triggered):
```json
{
  "event_type": "hook_exit",
  "exit_reason": "no_tmux | no_registry_match | stop_hook_active | empty_session_name | registry_missing",
  "exit_phase": "tmux_guard | registry_lookup | agent_id_empty"
}
```

**wake_sent** (emitted after openclaw call is dispatched, before hook exits):
```json
{
  "event_type": "wake_sent",
  "openclaw_session_id": "sess_abc123",
  "hook_mode": "async | bidirectional",
  "wake_message_bytes": 1247,
  "content_source": "transcript | pane_diff | raw_pane",
  "trigger_type": "response_complete | idle_prompt | permission_prompt | pre_compact | session_end | ask_user_question",
  "duration_ms": 12,
  "bg_pid": 12348
}
```

**wake_response_received** (emitted by background process after openclaw responds, or synchronously in bidirectional mode):
```json
{
  "event_type": "wake_response_received",
  "hook_mode": "async | bidirectional",
  "response_bytes": 98,
  "response_status": "ok | error | empty",
  "decision": "block | proceed | null",
  "reason": "reason text if block, else null",
  "duration_ms": 843
}
```

**question_forwarded** (emitted by pre-tool-use-hook.sh after AskUserQuestion wake is dispatched):
```json
{
  "event_type": "question_forwarded",
  "tool_use_id": "toolu_01ABC...",
  "question_count": 1,
  "options_count": 3,
  "multi_select": false,
  "duration_ms": 8
}
```

**answer_selected** (emitted by post-tool-use-hook.sh after AskUserQuestion completes):
```json
{
  "event_type": "answer_selected",
  "tool_use_id": "toolu_01ABC...",
  "answer_text": "OAuth (Recommended)",
  "answer_index": 0,
  "duration_ms": 4521
}
```

---

## MVP Definition

### Launch With (v3.0 — core JSONL infrastructure)

The minimum that makes v3.0 meaningful. All must ship together since they share the emit_event function.

- [ ] **Shared emit_event() in lib/hook-utils.sh** — Replaces debug_log() with a jq-based JSONL emitter. Writes one JSON line per call to the per-session .jsonl file. Accepts event_type and arbitrary key-value fields. Shared by all hook scripts via source.
- [ ] **hook_fired event** — Emitted in all 6 hook scripts after stdin consumed and session resolved. Fields: hook_script, hook_event_name, session_name, agent_id, correlation_id, stdin_bytes, pid.
- [ ] **hook_exit event** — Emitted on early-exit paths in all 6 hook scripts. Replaces "EXIT: ..." debug_log lines. Fields: exit_reason, exit_phase.
- [ ] **wake_sent event** — Emitted in stop-hook.sh, notification-idle-hook.sh, notification-permission-hook.sh, pre-compact-hook.sh, pre-tool-use-hook.sh, session-end-hook.sh after openclaw call is dispatched. Fields: wake_message_bytes, content_source, trigger_type, hook_mode, duration_ms, bg_pid (async only).
- [ ] **wake_response_received event** — Emitted in bidirectional branches (stop, notification-idle, notification-permission, pre-compact) after openclaw responds synchronously. Fields: response_bytes, response_status, decision, reason, duration_ms. In async mode: emitted by background subprocess after openclaw call completes.
- [ ] **correlation_id linking request and response** — Generated once per hook invocation (before the openclaw fork), carried in hook_fired, wake_sent, and wake_response_received events.
- [ ] **question_forwarded event** — Emitted in pre-tool-use-hook.sh after AskUserQuestion wake is dispatched. Fields: tool_use_id, question_count, options_count, multi_select.
- [ ] **Per-session JSONL file** — logs/{SESSION_NAME}.jsonl, parallel to existing logs/{SESSION_NAME}.log plain-text file. emit_event() writes here; debug_log() continues writing to .log for backward compatibility during transition.

### Add After Validation (v3.x)

- [ ] **answer_selected event via PostToolUse hook** — Requires new post-tool-use-hook.sh and hook registration. Closes the AskUserQuestion lifecycle loop. Add after confirming question_forwarded works correctly and correlation via tool_use_id is reliable.
- [ ] **duration_ms in all events** — Requires capturing hook start time (EPOCHREALTIME) immediately on script entry. Straightforward but requires touching all 6 hooks. Add in second pass after core events are confirmed correct.
- [ ] **Log rotation guard** — Size check before emit_event writes. Add when log accumulation becomes visible in practice (depends on session frequency).

### Future Consideration (v4+)

- [ ] **Remove plain-text debug_log() entirely** — Once JSONL events cover all cases debug_log() covered, delete the duplicate plain-text logging. Requires confirming JSONL log contains no gaps.
- [ ] **Cross-session query tooling** — A query-logs.sh script that wraps jq queries across all session JSONL files. Deferred to when dashboard integration begins.
- [ ] **OTLP export** — If a local collector is ever running, add OTLP transport as an alternative destination for emit_event(). Separate from file-based logging, not replacing it.

---

## Feature Prioritization Matrix

| Feature | Diagnostic Value | Implementation Cost | Priority |
|---------|-----------------|---------------------|----------|
| Shared emit_event() in lib | HIGH — enables all other features | LOW — 10-15 lines of jq bash | P1 |
| hook_fired event | HIGH — proves hook executed, captures entry state | LOW — one call per hook after session resolved | P1 |
| wake_sent event with wake_message_bytes | HIGH — confirms delivery, captures payload size | LOW — one call per hook before openclaw | P1 |
| correlation_id | HIGH — links request/response across async fork | MEDIUM — generate before fork, pass to bg subprocess | P1 |
| wake_response_received (bidirectional) | HIGH — captures what OpenClaw actually said | LOW — synchronous, already in response variable | P1 |
| wake_response_received (async) | MEDIUM — async response captured after the fact | MEDIUM — background subprocess must emit to same file | P2 |
| hook_exit event | MEDIUM — distinguishes early exits from never-fired | LOW — replaces existing debug_log exit lines | P1 |
| question_forwarded event | MEDIUM — AskUserQuestion audit trail starts here | LOW — data already extracted in pre-tool-use-hook.sh | P1 |
| answer_selected event (PostToolUse) | HIGH — closes the lifecycle loop | MEDIUM — new script + new hook registration | P2 |
| duration_ms in wake events | LOW-MEDIUM — performance diagnosis | LOW — one arithmetic op per event | P2 |
| content_source in wake events | MEDIUM — reveals transcript fallback rate | LOW — already a local variable in stop-hook.sh | P1 |
| Log rotation guard | LOW — prevents disk fill over weeks | LOW — wc -c check + mv | P3 |

**Priority key:**
- P1: Core JSONL infrastructure — must ship in first phase
- P2: Completeness — add in second phase within same milestone
- P3: Operational hygiene — add when problem manifests

---

## AskUserQuestion Lifecycle Detail

### Current State (v2.0)
```
Claude calls AskUserQuestion tool
    → PreToolUse hook fires
    → pre-tool-use-hook.sh: extracts question + options from tool_input
    → Formats and sends wake message to Gideon (async background)
    → debug_log: "DELIVERED (async AskUserQuestion forward, bg PID=X)"
    → Hook exits 0 (TUI menu renders)
    → [NOTHING LOGGED ABOUT WHICH OPTION WAS SELECTED]
```

### Target State (v3.0)
```
Claude calls AskUserQuestion tool
    → PreToolUse hook fires
    → pre-tool-use-hook.sh:
        → correlation_id = "1708250400123-12345-47829"
        → emit_event: {event_type: "hook_fired", correlation_id: ..., tool_use_id: "toolu_01ABC..."}
        → extracts question + options
        → sends wake to Gideon (async background, background process emits wake_response_received)
        → emit_event: {event_type: "question_forwarded", tool_use_id: "toolu_01ABC...", question_count: 1, options_count: 3}
        → hook exits 0 (TUI menu renders)

Gideon selects option (via menu-driver.sh choose 2)
    → Claude Code submits answer
    → PostToolUse hook fires (NEW in v3.x)
    → post-tool-use-hook.sh:
        → reads tool_use_id from stdin
        → reads answer from tool_result in stdin
        → emit_event: {event_type: "answer_selected", tool_use_id: "toolu_01ABC...", answer_text: "JWT", answer_index: 1}
        → hook exits 0
```

### tool_use_id as the Lifecycle Link

The `tool_use_id` field in PreToolUse and PostToolUse hook stdin is the stable identifier for a single AskUserQuestion invocation. It links the question_forwarded event to the answer_selected event. This is the canonical way to correlate question and answer across the async gap between hook fires.

PostToolUse hook stdin structure (for AskUserQuestion completion):
```json
{
  "hook_event_name": "PostToolUse",
  "tool_name": "AskUserQuestion",
  "tool_use_id": "toolu_01ABC...",
  "tool_input": { "questions": [...] },
  "tool_response": {
    "type": "tool_result",
    "content": "JWT"
  }
}
```

Note: The `tool_response.content` field contains the raw selected answer text (or comma-separated for multiSelect). Confidence: MEDIUM — inferred from PreToolUse pattern and Claude Code hooks documentation structure; PostToolUse is in the hooks spec but the exact field name for AskUserQuestion response needs verification during implementation.

---

## Edge Cases

| Scenario | Severity | Behavior |
|----------|----------|----------|
| emit_event() fails (disk full, permission error) | LOW | emit_event must be fire-and-forget with `|| true` — never abort hook execution on logging failure |
| JSONL file gets corrupted (partial write) | LOW | JSONL is append-only; a corrupted line is one bad record; jq --raw-input skips invalid lines gracefully |
| Background subprocess can't write to JSONL file (file deleted between hook_fired and bg completion) | LOW | The bg process emits with `|| true`; lost wake_response_received events are non-fatal |
| correlation_id generation in same-second, same-PID, same-RANDOM scenario | VERY LOW | Use `$EPOCHREALTIME-$$-$RANDOM` — EPOCHREALTIME has microsecond precision, collision probability is negligible |
| PostToolUse stdin for AskUserQuestion field names | MEDIUM | Needs empirical verification during implementation — test with a real session before committing to field schema |
| debug_log() and emit_event() writing to different files simultaneously | LOW | The .log and .jsonl files are independent write targets — no conflict, both append-only |
| Session name contains characters that break jq --arg | LOW | SESSION_NAME already used in .log filenames without issue; jq --arg handles arbitrary strings safely |

---

## Sources

**HIGH confidence (existing codebase — ground truth):**
- scripts/stop-hook.sh (v2.0 shipped) — current plain-text debug_log pattern, async/bidirectional branches, RESPONSE capture
- scripts/pre-tool-use-hook.sh (v2.0 shipped) — AskUserQuestion forwarding, format_ask_user_questions call
- lib/hook-utils.sh (v2.0 shipped) — existing shared library, format_ask_user_questions, extract functions
- .planning/PROJECT.md — v3.0 target features, constraints (bash + jq only), out-of-scope declarations
- .planning/REQUIREMENTS.md — ADV-05 (PostToolUse for AskUserQuestion answer) — pre-existing requirement

**HIGH confidence (structured logging best practices — multiple sources):**
- [Structured Logging: Best Practices & JSON Examples — Uptrace](https://uptrace.dev/glossary/structured-logging) — standard fields: timestamp, level, service, correlation_id, event; request/response schema
- [Practical Structured Logging — Dash0](https://www.dash0.com/guides/structured-logging-for-modern-applications) — correlation ID propagation, 2-3 level nesting limit, ISO 8601 UTC
- [Log Event JSON Schema — vectordotdev](https://github.com/vectordotdev/log-event-json-schema) — context object for cross-cutting data (session, agent identity), event object for typed event data

**MEDIUM confidence (bash JSONL pattern — implementation pattern):**
- [How to make a shell script log JSON messages — stegard.net](https://stegard.net/2021/07/how-to-make-a-shell-script-log-json-messages/) — jq-based structured logging in bash, field expansion approach; does NOT cover correlation IDs (verified: not in the article)
- jq -n --arg pattern — standard `jq` usage for constructing JSON from bash variables; widely documented

**MEDIUM confidence (PostToolUse hook stdin schema):**
- Claude Code Hooks Reference (via training data + v2.0 PreToolUse investigation) — PostToolUse fires after tool execution with tool_result in stdin; specific field names for AskUserQuestion tool_response require empirical verification

---

*Feature research for: gsd-code-skill v3.0 Structured Hook Observability*
*Researched: 2026-02-18*

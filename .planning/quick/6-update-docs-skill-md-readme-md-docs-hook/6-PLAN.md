---
phase: quick-6
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - SKILL.md
  - README.md
  - docs/hooks.md
autonomous: true
requirements: [DOC-UPDATE]

must_haves:
  truths:
    - "All 7 hook scripts are listed in every doc that enumerates hooks"
    - "lib/hook-utils.sh is documented with all 6 functions"
    - "logrotate config and install script appear in file tables and setup instructions"
    - "diagnose-hooks.sh appears in utilities section with JSONL analysis mentioned"
    - "Hook count references say 7 everywhere, not 5 or 6"
    - "docs/hooks.md has PostToolUse behavior spec"
    - "v3.0 additions (JSONL logging, logrotate, diagnostics) are mentioned"
  artifacts:
    - path: "SKILL.md"
      provides: "Agent-facing skill reference"
    - path: "README.md"
      provides: "Admin-facing setup and operational guide"
    - path: "docs/hooks.md"
      provides: "Hook behavior specifications"
  key_links: []
---

<objective>
Update all three documentation files (SKILL.md, README.md, docs/hooks.md) to reflect Phase 10 and Phase 11 additions: post-tool-use-hook.sh, logrotate config, install-logrotate.sh, JSONL diagnostics in diagnose-hooks.sh, and corrected hook/function counts.

Purpose: Documentation is stale after Phases 8-11 shipped. All hook counts say 5 or 6 when there are now 7 hooks. lib/hook-utils.sh says 3 functions when there are 6. New scripts and config files are undocumented.

Output: Three updated documentation files with accurate counts, complete file listings, and new feature coverage.
</objective>

<execution_context>
@/home/forge/.claude/get-shit-done/workflows/execute-plan.md
@/home/forge/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@SKILL.md
@README.md
@docs/hooks.md
@.planning/phases/10-askuserquestion-lifecycle-completion/10-01-SUMMARY.md
@.planning/phases/11-operational-hardening/11-01-SUMMARY.md
@.planning/phases/11-operational-hardening/11-02-SUMMARY.md
</context>

<tasks>

<task type="auto">
  <name>Task 1: Update SKILL.md with Phase 10-11 additions</name>
  <files>SKILL.md</files>
  <action>
Read SKILL.md and make these targeted updates:

1. **Lifecycle paragraph** (line ~38): Change "Hooks fire on Claude Code events (Stop, Notification, SessionEnd, PreCompact, PreToolUse)" to include PostToolUse: "(Stop, Notification, SessionEnd, PreCompact, PreToolUse, PostToolUse)"

2. **Hooks subsection** (after line ~100): Add entry for post-tool-use-hook.sh:
```
**post-tool-use-hook.sh** - Fires after AskUserQuestion completes (forwards selected answer and tool_use_id to OpenClaw for lifecycle correlation)
```

3. **All hooks bullet list** (around line ~103-106): Update to say 7 hooks instead of implicit 5/6. Change the exit time reference from "Exit in <5ms" to match current reality. Add bullet point:
```
- Log structured JSONL records per-session via `write_hook_event_record`
```

4. **lib/hook-utils.sh description** (line ~109-111): Replace the current description:
```
**lib/hook-utils.sh** - Shared functions sourced by all hook scripts

Contains 6 functions: `lookup_agent_in_registry`, `extract_last_assistant_response`, `extract_pane_diff`, `format_ask_user_questions`, `write_hook_event_record`, `deliver_async_with_logging`. No side effects on source.
```

5. **Utilities subsection**: Add entries for diagnose-hooks.sh and install-logrotate.sh:
```
**diagnose-hooks.sh** - End-to-end hook chain diagnostic for a registered agent

\```bash
scripts/diagnose-hooks.sh <agent-name> [--send-test-wake]
\```

Tests 11 steps: hook registration, script permissions, registry entry, tmux session, TMUX propagation, session name resolution, registry lookup, openclaw binary, debug logs, JSONL log analysis, and optional test wake.

**install-logrotate.sh** - Install logrotate config for hook log rotation

\```bash
scripts/install-logrotate.sh
\```

Installs `config/logrotate.conf` to `/etc/logrotate.d/gsd-code-skill` via sudo tee. Uses copytruncate for safe rotation while hook scripts hold open file descriptors. Daily rotation, 7-day retention, compress with delaycompress.
```

6. **register-hooks.sh description** (line ~133-139): Update event count from "6 hook events" to "7 hook events" and add PostToolUse to the parenthetical list: "(Stop, Notification [idle_prompt + permission_prompt], SessionEnd, PreCompact, PreToolUse [AskUserQuestion], PostToolUse [AskUserQuestion])"

7. **Configuration section**: Add entry for logrotate config:
```
**Logrotate:** `config/logrotate.conf`

Template for log rotation. Install via `scripts/install-logrotate.sh` (requires sudo). Uses copytruncate to safely rotate while hook scripts hold open file descriptors.
```

8. **v2.0 Changes section** (line ~158): Add a new **v3.0 Changes** section after v2.0:
```
## v3.0 Changes

**Structured JSONL logging:** All 7 hooks emit per-session JSONL records (`logs/{session}.jsonl`) with timestamp, hook_script, trigger, outcome, duration_ms, and hook-specific extra fields. Plain-text debug logs (`logs/{session}.log`) are preserved in parallel.

**PostToolUse hook (new):** Fires after AskUserQuestion completes. Logs `answer_selected` and `tool_use_id` for lifecycle correlation with the PreToolUse record. Always async, always notification-only.

**Logrotate:** `config/logrotate.conf` with copytruncate handles both `*.jsonl` and `*.log` files. Install via `scripts/install-logrotate.sh`.

**Diagnostics:** `scripts/diagnose-hooks.sh` now includes JSONL log analysis (Step 10) showing recent events, outcome distribution, hook script distribution, non-delivered event detection, and duration stats.

**Minimum Claude Code version:** >= 2.0.76 (PostToolUse hook support added in same version as PreToolUse).
```
  </action>
  <verify>
Read the updated SKILL.md. Grep for "5 hook" and "6 hook" to confirm no stale counts remain. Grep for "post-tool-use" to confirm new hook is listed. Grep for "logrotate" to confirm config is mentioned. Grep for "diagnose" to confirm diagnostic script is listed. Grep for "6 functions" to confirm lib description is updated.
  </verify>
  <done>SKILL.md lists all 7 hooks, all 6 lib functions, both new scripts (install-logrotate.sh, diagnose-hooks.sh), logrotate config, and has v3.0 Changes section. No stale "5 hook" or "6 hook" references remain except where "6 functions" refers to lib/hook-utils.sh.</done>
</task>

<task type="auto">
  <name>Task 2: Update README.md with Phase 10-11 additions</name>
  <files>README.md</files>
  <action>
Read README.md and make these targeted updates:

1. **Pre-Flight Step 2** (lines ~47-63): Update hook registration section:
   - Change "5 hook events" to "7 hook events" in the intro text
   - Add PreToolUse and PostToolUse to the bullet list:
     ```
     - PreToolUse with AskUserQuestion matcher (agent about to ask user a question)
     - PostToolUse with AskUserQuestion matcher (user answered agent's question)
     ```
   - Change verification expected output from "all 5 hook events" to "all 7 hook events"

2. **Pre-Flight section**: Add a new step between step 3 (systemd timer) and step 4 (verify daemon). Renumber steps 4 and 5 to 5 and 6. New step 4:
```
### 4. Install logrotate (recommended)

Install log rotation to prevent unbounded disk growth from hook JSONL and debug logs:

\```bash
scripts/install-logrotate.sh
\```

This installs `config/logrotate.conf` to `/etc/logrotate.d/gsd-code-skill` (requires sudo). Uses `copytruncate` for safe rotation while hook scripts hold open file descriptors. Daily rotation with 7-day retention.

Verify installation:

\```bash
cat /etc/logrotate.d/gsd-code-skill
\```
```

3. **Recovery Flow hooks list** (lines ~380-385): Add the two missing hook events:
```
- **PreToolUse (AskUserQuestion)**: Agent about to ask user a question (forwards question data)
- **PostToolUse (AskUserQuestion)**: User answered agent's question (logs answer for lifecycle correlation)
```

4. **Verification Commands section**: Add JSONL log inspection command:
```
**Check hook JSONL logs for a session**:
\```bash
scripts/diagnose-hooks.sh <agent-name>
\```

Runs 11-step diagnostic including JSONL log analysis (recent events, outcome distribution, non-delivered detection, duration stats).
```

5. **Files / Scripts table** (lines ~493-506): Add three missing entries:
```
| `scripts/pre-tool-use-hook.sh` | Hook: fires when agent calls AskUserQuestion (forwards question data). |
| `scripts/post-tool-use-hook.sh` | Hook: fires after AskUserQuestion completes (logs selected answer). |
| `scripts/diagnose-hooks.sh` | End-to-end 11-step hook chain diagnostic with JSONL analysis. |
| `scripts/install-logrotate.sh` | Install logrotate config for hook log rotation (requires sudo). |
```
Note: pre-tool-use-hook.sh is also missing from the table (was added in Phase 7 but table was last updated in Phase 5). Add it too.

6. **Files / Scripts table**: Update `register-hooks.sh` description from "Registers all 5 hook events" to "Registers all 7 hook events".

7. **Files / Config table** (lines ~510-514): Add logrotate config:
```
| `config/logrotate.conf` | Logrotate template for hook logs. Install via `install-logrotate.sh`. |
```

8. **Files / Documentation table** (line ~526-529): No changes needed, already lists all 3 docs.

9. **Shared Libraries section**: Add to Scripts table or create new section:
```
| `lib/hook-utils.sh` | Shared library (6 functions) sourced by all hook scripts. No side effects on source. |
```
  </action>
  <verify>
Read the updated README.md. Grep for "5 hook" to confirm no stale counts remain. Grep for "post-tool-use" to confirm new hook is listed. Grep for "logrotate" to confirm config and install script are mentioned. Grep for "diagnose" to confirm diagnostic script is listed. Count rows in the Scripts table to verify all scripts are listed.
  </verify>
  <done>README.md lists all 7 hooks in registration/recovery sections, includes logrotate install step in Pre-Flight, has all scripts in Files table (including pre-tool-use-hook.sh, post-tool-use-hook.sh, diagnose-hooks.sh, install-logrotate.sh), and logrotate.conf in Config table. No stale "5 hook" references remain.</done>
</task>

<task type="auto">
  <name>Task 3: Update docs/hooks.md with PostToolUse spec and v3.0 additions</name>
  <files>docs/hooks.md</files>
  <action>
Read docs/hooks.md and make these targeted updates:

1. **Opening paragraph** (line 1-3): Change "all 5 Claude Code hooks" to "all 7 Claude Code hooks". Update the hook list in the paragraph to include PreToolUse and PostToolUse.

2. **After the pre-tool-use-hook.sh section** (after line ~160): Add a complete PostToolUse behavior spec section:
```
## post-tool-use-hook.sh

**Trigger:** Fires after AskUserQuestion completes (PostToolUse event with `AskUserQuestion` matcher)

**What It Does:**

1. Consume stdin JSON to prevent pipe blocking
2. Log raw stdin via `debug_log` for empirical validation of `tool_response` schema (ASK-05 requirement)
3. Check `$TMUX` environment (exit if not in tmux)
4. Extract tmux session name via `tmux display-message -p '#S'`
5. Lookup agent entry in registry via `lookup_agent_in_registry`
6. Exit if no match (non-managed session)
7. Extract `tool_use_id` from stdin JSON
8. Extract `answer_selected` from stdin JSON using defensive multi-shape extractor (handles object with `.content`/`.text` and plain string shapes)
9. Build wake message with `[ANSWER SELECTED]` section containing tool_use_id and answer
10. Deliver wake message asynchronously via `deliver_async_with_logging` with JSONL record containing `tool_use_id` and `answer_selected` extra fields
11. Exit 0 (always -- PostToolUse fires after tool ran, cannot block)

**Configuration (hook_settings):**

None. PostToolUse hook ignores `hook_mode` (always async, never bidirectional). Timeout: 10s in settings.json.

**Edge Cases:**

- Always exits 0 -- PostToolUse fires after the tool already ran, non-zero exit has no effect
- No `stop_hook_active` check (PostToolUse doesn't recurse)
- No pane capture (answer data comes from `tool_response` in stdin, not from tmux pane)
- Defensive `answer_selected` extractor handles multiple `tool_response` shapes pending empirical validation
- Raw stdin logged for schema validation -- can be narrowed once AskUserQuestion PostToolUse schema is confirmed from live session data
- Lifecycle correlation: `tool_use_id` links PostToolUse record back to PreToolUse record via `jq --arg id "toolu_..." 'select(.tool_use_id == $id)' logs/session.jsonl`

**Exit Time:** <5ms for non-managed sessions, ~20-50ms for managed sessions

**Related Registry Fields:** `tmux_session_name`, `agent_id`, `openclaw_session_id`
```

3. **Shared Library table** (line ~323-330): Replace the 3-function table with the full 6-function table:
```
| Function | Used By | Purpose |
|----------|---------|---------|
| `lookup_agent_in_registry` | all hooks | Registry agent lookup by tmux session name (prefix match) |
| `extract_last_assistant_response` | stop-hook.sh | JSONL transcript text extraction |
| `extract_pane_diff` | stop-hook.sh | Per-session pane line delta |
| `format_ask_user_questions` | pre-tool-use-hook.sh | AskUserQuestion data formatting |
| `write_hook_event_record` | all hooks (via deliver_async_with_logging) | Structured JSONL record emission with 13 positional parameters |
| `deliver_async_with_logging` | all hooks | Backgrounded async delivery with JSONL logging (calls write_hook_event_record + openclaw agent) |
```

4. **Temp File Lifecycle section** (lines ~341-346): Update to reflect Quick-5 migration from /tmp to skill-local logs/:
```
## Log File Lifecycle

Per-session log files in `logs/`:
- `{session-name}.jsonl` -- structured JSONL records (one per hook invocation, written by `write_hook_event_record`)
- `{session-name}.log` -- plain-text debug log (written by `debug_log` in each hook script)
- `hooks.log` -- shared log for entries before session name is known (Phase 1 of two-phase logging)

Pane diff state files in `logs/`:
- `gsd-pane-prev-{session}.txt` -- last pane capture (written by `extract_pane_diff`)
- `gsd-pane-lock-{session}` -- flock file for atomic diff operations

Log rotation handled by `config/logrotate.conf` (installed via `scripts/install-logrotate.sh`). Uses `copytruncate` for safe rotation while hooks hold open `>>` file descriptors.
```

5. **Add new section before Troubleshooting**: Add a "v3.0 Structured JSONL Logging" section:
```
# v3.0 Structured JSONL Logging

All 7 hooks emit structured JSONL records to `logs/{session-name}.jsonl`. Each record contains:

| Field | Description |
|-------|-------------|
| `timestamp` | ISO 8601 UTC timestamp |
| `hook_script` | Hook script filename (e.g., `stop-hook.sh`) |
| `session_name` | tmux session name |
| `agent_id` | Agent identifier from registry |
| `trigger` | Event trigger type (e.g., `stop`, `idle_prompt`, `ask_user_question_answered`) |
| `state` | Detected session state |
| `content_source` | Content extraction method used |
| `outcome` | Delivery result: `delivered`, `sync_delivered`, `skipped`, `error` |
| `duration_ms` | Hook execution duration in milliseconds |
| `extra` | Hook-specific extra fields (JSON object) |

**Hook-specific extra fields:**

- `pre-tool-use-hook.sh`: `{"questions_forwarded": N, "tool_use_id": "toolu_..."}`
- `post-tool-use-hook.sh`: `{"tool_use_id": "toolu_...", "answer_selected": "..."}`
- Other hooks: `{}` (empty object)

**Lifecycle correlation:** Link PreToolUse question to PostToolUse answer via shared `tool_use_id`:

\```bash
jq --arg id "toolu_abc123" 'select(.tool_use_id == $id)' logs/session-name.jsonl
\```

**Diagnostics:** Run `scripts/diagnose-hooks.sh <agent-name>` for JSONL analysis including recent events, outcome distribution, non-delivered detection, and duration stats.
```

6. **Troubleshooting section**: Add JSONL-related troubleshooting entries:
```
**No JSONL records appearing:**
- Hooks only write JSONL for managed sessions (agent must be in registry)
- Check `logs/` directory exists and is writable
- Check `logs/{session-name}.jsonl` after a hook fires
- Run `scripts/diagnose-hooks.sh <agent-name>` for Step 10 JSONL analysis

**Hook delivery failures in JSONL:**
- Run `scripts/diagnose-hooks.sh <agent-name>` -- Step 10 shows non-delivered events
- Check `logs/{session-name}.log` for detailed error context around the failed delivery
- Verify openclaw binary is available: `command -v openclaw`
```
  </action>
  <verify>
Read the updated docs/hooks.md. Grep for "5 Claude" to confirm no stale count. Grep for "post-tool-use" to confirm PostToolUse spec exists. Grep for "write_hook_event_record" to confirm all 6 functions in table. Grep for "JSONL" to confirm structured logging section exists. Grep for "/tmp" to confirm no stale temp file references.
  </verify>
  <done>docs/hooks.md documents all 7 hooks with complete PostToolUse behavior spec, lists all 6 lib/hook-utils.sh functions, has v3.0 JSONL logging section, updated log file lifecycle (skill-local logs/ not /tmp), and JSONL troubleshooting entries. No stale "5 hooks" or "/tmp" references remain.</done>
</task>

</tasks>

<verification>
After all 3 tasks:
1. Grep all three files for "5 hook" — must return zero matches (except where "5" appears in non-count context)
2. Grep all three files for "post-tool-use-hook" — must find entries in each file
3. Grep all three files for "logrotate" — must find entries in SKILL.md and README.md
4. Grep all three files for "diagnose-hooks" — must find entries in SKILL.md and README.md
5. Grep docs/hooks.md for "/tmp" — must return zero matches
</verification>

<success_criteria>
All three documentation files accurately reflect the current state of the skill after Phases 8-11:
- 7 hooks (not 5 or 6) everywhere
- 6 lib functions (not 3) everywhere
- PostToolUse behavior spec in docs/hooks.md
- install-logrotate.sh, diagnose-hooks.sh, config/logrotate.conf in file tables
- v3.0 additions section in SKILL.md
- JSONL structured logging documented in docs/hooks.md
- No stale /tmp references (logs moved to skill-local logs/)
</success_criteria>

<output>
After completion, create `.planning/quick/6-update-docs-skill-md-readme-md-docs-hook/6-SUMMARY.md`
</output>

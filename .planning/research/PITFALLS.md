# Pitfalls Research

**Domain:** Polling-to-Hook Migration for Multi-Agent Claude Code Control
**Researched:** 2026-02-17
**Confidence:** HIGH

## Critical Pitfalls

### Pitfall 1: Stop Hook Infinite Loop via `stop_hook_active` Ignorance

**What goes wrong:**
The Stop hook fires after every Claude response. If the hook script itself causes Claude to respond (e.g., by calling `openclaw agent` synchronously and that agent calls `menu-driver.sh` which sends keys, causing Claude to respond again), the Stop hook fires again immediately, creating an infinite loop that consumes all tokens and locks up the session.

**Why it happens:**
Developers assume backgrounding `openclaw agent &` is sufficient, but fail to consume stdin from the hook or ignore the `stop_hook_active` guard in the JSON input. When `stop_hook_active: true`, it means the hook is already in a recursive call and must exit immediately to allow the stop to proceed.

**How to avoid:**
1. Always read and parse stdin JSON at the start of the hook
2. Check `stop_hook_active` field in the JSON
3. Exit 0 immediately if `stop_hook_active` is `true`
4. Background all `openclaw agent` calls with `&` and append `|| true` to prevent hook failure
5. Never return decision: "block" from the hook (always exit 0 quickly)

**Warning signs:**
- Hook script hangs indefinitely
- Claude Code session becomes unresponsive
- Context percentage jumps to 100% rapidly
- Logs show repeated hook invocations within milliseconds
- `ps aux | grep openclaw` shows dozens of backgrounded processes

**Phase to address:**
Phase 1 (Create stop-hook.sh) — implement guard at the top of the script, before any logic

---

### Pitfall 2: stdin Pipe Blocking from Unconsumed Input

**What goes wrong:**
Hook scripts that don't consume stdin cause the entire hook pipeline to block indefinitely. Claude Code writes JSON to the hook's stdin pipe and waits for the hook to exit, but if the hook never reads from stdin, the pipe buffer fills (typically 64KB) and the writer (Claude Code) blocks, waiting for the reader (hook) to consume it. The hook is waiting for something else, creating a deadlock.

**Why it happens:**
Developers focus on hook logic and forget that bash scripts don't automatically consume stdin. Unlike interactive shells, piped input must be explicitly read or it will cause blocking. This is especially insidious because it only manifests when the JSON input grows large enough to fill the pipe buffer (e.g., when transcript paths or session metadata expand).

**How to avoid:**
1. Always consume stdin at the very top of the hook script, even if you don't need the JSON
2. Use `cat > /dev/null` as the first line after the shebang and `set -euo pipefail`
3. Or use `jq -r '.stop_hook_active // false'` to both consume stdin AND extract needed fields
4. Test with large JSON payloads (>64KB) to verify no blocking occurs

**Warning signs:**
- Hook appears to hang with no CPU usage
- Claude Code session freezes after a response
- `strace` on the hook process shows it blocked in `poll()` or `select()` waiting on stdin
- Hook works in small test repos but fails in repos with deep transcript history

**Phase to address:**
Phase 1 (Create stop-hook.sh) — add stdin consumption as the second line of the script (after `set -euo pipefail`)

**Source:**
- [Claude Code Hooks 2026 Guide](https://claude-world.com/articles/hooks-development-guide/)
- [aiorg.dev Hooks Best Practices](https://aiorg.dev/blog/claude-code-hooks)

---

### Pitfall 3: Registry Corruption from Concurrent Writes

**What goes wrong:**
Multiple processes (spawn.sh, recover-openclaw-agents.sh, sync-recovery-registry-session-ids.sh) write to `config/recovery-registry.json` simultaneously, causing JSON corruption. The file ends up with truncated objects (e.g., `{"agent_id":"warden","enabled":tr`), interleaved writes from two processes, or completely malformed JSON that breaks all future reads.

**Why it happens:**
JSON files are not atomic write targets. When Process A reads the registry, modifies it, and writes it back, Process B may do the same simultaneously. Without file-level locking, the last write wins, losing the changes from the first process. Even worse, if writes are unbuffered or interrupted (OOM, crash, disk full), the file is left in a partially written state.

**How to avoid:**
1. Use atomic write pattern: write to `${file}.tmp.$$`, then `mv` to final location
2. Wrap registry modifications in `flock` to serialize access: `flock /tmp/registry.lock -c "python3 update_registry.py"`
3. Add retry logic with exponential backoff if lock acquisition fails
4. For recovery-registry.json specifically: spawn.sh and recover script should never run concurrently (spawn is manual, recover is boot-only), but sync script may run via cron — ensure sync script uses flock
5. Validate JSON after every write: `jq empty < registry.json || restore_from_backup`

**Warning signs:**
- `jq` fails with "parse error: Invalid numeric literal" when reading registry
- Registry file size is suspiciously small (truncated mid-write)
- Registry contains only partial agent entries
- Python upsert script exits with JSON decode error
- Agents randomly disappear from registry after successful spawn

**Phase to address:**
Phase 3 (Update spawn.sh and recover script) — wrap Python upsert calls in flock, add atomic write to Python script

**Source:**
- [JSON Corruption from Concurrent Writes](https://github.com/EdgeApp/edge-core-js/issues/258)
- [lowdb Concurrent Write Issue](https://github.com/typicode/lowdb/issues/333)
- [Mozilla's JSONFile.jsm Analysis](https://mozilla.github.io/firefox-browser-architecture/text/0012-jsonfile.html)

---

### Pitfall 4: Tmux `send-keys` Corruption from Concurrent Spawning

**What goes wrong:**
When multiple spawn.sh processes or multiple recovery script launches run simultaneously, `tmux send-keys` commands get garbled. Instead of sending `cd /path/to/workdir`, tmux receives `ccdd //ppaatthh` or `mentcd` because keystrokes from two `send-keys` calls are interleaved at the tmux server level. This causes agents to fail with "command not found" errors on startup.

**Why it happens:**
Tmux's internal input queue is not isolated per-session or per-pane. When two `send-keys` commands target different panes but execute within milliseconds of each other, the tmux server may interleave the characters. This is a known race condition in tmux's design, exacerbated by parallel agent spawning (e.g., recover script looping over agents without delays).

**How to avoid:**
1. Never spawn multiple agents in parallel without delays — serialize with `sleep 0.5` between spawns
2. In recover-openclaw-agents.sh, process agents sequentially, not in parallel
3. Use `tmux send-keys -l` (literal mode) to send entire strings as a single operation
4. Add a small delay (`sleep 0.1`) between `send-keys` calls within a single spawn
5. Avoid `send-keys` entirely for initialization — use `tmux new-session -d -s "$SESSION" -c "$WORKDIR" "claude ..."`

**Warning signs:**
- Agents fail to start with "command not found: mentcd" or similar garbled commands
- `tmux capture-pane` shows partial commands or duplicated characters
- Failure rate increases with number of concurrent spawns (works with 1-2 agents, fails with 4+)
- Success rate improves when adding manual delays between spawns

**Phase to address:**
Phase 3 (Update spawn.sh and recover script) — ensure sequential processing, add `send-keys -l`, add inter-spawn delays in recovery script

**Source:**
- [Claude Code Agent Teams send-keys Corruption](https://github.com/anthropics/claude-code/issues/23615)
- [Tmux send-keys Race Condition Discussion](https://github.com/tmux/tmux/issues/3360)

---

### Pitfall 5: Recovery Script Failure Leaves System in Broken State

**What goes wrong:**
The recovery script (`recover-openclaw-agents.sh`) is invoked by systemd at boot (via `recover-openclaw-agents.service`). If the script fails partway through (e.g., Python exception, missing binary, malformed registry), some agents are recovered and others are not. Worse, if systemd's `StartLimitBurst` is exceeded due to repeated failures, the service is permanently marked as failed and will not run on subsequent boots without manual `systemctl reset-failed`.

**Why it happens:**
Recovery scripts are critical infrastructure but often lack defensive coding. A single unhandled error (missing `tmux`, Python import failure, registry corruption) causes `set -euo pipefail` to abort the entire script. Partial execution leaves the system in an inconsistent state: Gideon might be running but Warden isn't, or sessions exist but OpenClaw session IDs weren't synced.

**How to avoid:**
1. Remove `set -e` from recovery script — handle errors explicitly per-agent instead of aborting globally
2. Wrap each agent recovery in a try/catch pattern: `recover_agent || log_failure`
3. Always send a summary to the global status OpenClaw session, even on partial failure
4. Use systemd `Restart=on-failure` with `StartLimitBurst=5` and `StartLimitIntervalSec=300`
5. Add a systemd watchdog: the script must call `systemd-notify --status="Recovering agent X"` periodically
6. Validate all dependencies (tmux, python3, openclaw, jq) before starting recovery loop
7. If registry is corrupted, log error and continue with empty agent list rather than crashing

**Warning signs:**
- `systemctl status recover-openclaw-agents.service` shows "failed" with no clear error
- Some agents are running but others are missing after boot
- Logs show "python3: ModuleNotFoundError" or "command not found: tmux"
- Service marked as "start-limit-hit" and won't restart
- OpenClaw receives no global summary message after boot

**Phase to address:**
Phase 3 (Update recover-openclaw-agents.sh) — refactor error handling, remove `set -e`, add per-agent try/catch, validate dependencies early

**Source:**
- [Systemd Service Recovery Best Practices](https://www.redhat.com/en/blog/systemd-automate-recovery)
- [Implementing Restart Policies in systemd](https://dohost.us/index.php/2025/10/27/implementing-service-recovery-and-restart-policies-in-systemd/)
- [Diagnosing Boot Problems](https://systemd.io/DEBUGGING/)

---

### Pitfall 6: Concurrent Old and New Systems Create Duplicate Events

**What goes wrong:**
During migration (Phase 2-3), both `hook-watcher.sh` (polling system) and `stop-hook.sh` (new hook system) are active simultaneously. This causes duplicate wake events: the hook fires immediately when Claude responds, then 1 second later the polling watcher also detects the menu and fires another wake. The OpenClaw agent receives two identical "menu detected" messages, potentially making duplicate decisions or getting confused by rapid-fire messages.

**Why it happens:**
Migration phases overlap to avoid breaking running sessions. Phase 2 adds the Stop hook but doesn't remove the old SessionStart hook that launches `hook-watcher.sh`. Existing sessions spawned before Phase 2 still have `hook-watcher.sh` running in the background. Even after Phase 4 deletes the scripts, those background processes persist until their tmux session ends.

**How to avoid:**
1. In stop-hook.sh, check for existence of old watcher state files (`/tmp/gsd-hook-watcher/${SESSION}.lastsig`) and skip wake if state file was modified within last 5 seconds (indicates watcher is still active)
2. Make hook-watcher.sh check for a "migration mode" flag file (`/tmp/stop-hook-migration-active`) and exit if present
3. Document migration procedure: Phase 2 creates the flag file, Phase 4 removes it
4. Accept brief duplicate events as tolerable during migration — OpenClaw agents should be idempotent anyway
5. After migration, kill all existing hook-watcher processes: `pkill -f 'hook-watcher.sh'`

**Warning signs:**
- OpenClaw logs show duplicate "menu detected" events within 1 second
- Agents make decisions twice for the same menu
- menu-driver.sh gets called twice, sending keys twice, breaking the menu flow
- Context pressure warnings appear twice in rapid succession

**Phase to address:**
Phase 2 (Wire up Stop hook) — add deduplication logic to stop-hook.sh
Phase 4 (Remove old scripts) — kill all existing watcher processes before deleting scripts

---

### Pitfall 7: `system_prompt` Field Missing Breaks Recovery Launch

**What goes wrong:**
After adding `system_prompt` to the registry schema, old registry entries don't have the field. When `recover-openclaw-agents.sh` tries to extract `system_prompt` from an old entry, it gets `null` or empty string. If the recovery script doesn't handle this gracefully, it either passes an empty `--append-system-prompt ""` to Claude (which may cause Claude to ignore the flag and use no system prompt), or it crashes trying to build the launch command.

**Why it happens:**
Schema evolution without migration. Adding a new required field to the registry breaks compatibility with existing entries. Python's `entry.get("system_prompt")` returns `None` for old entries, and bash string substitution of `${system_prompt}` may produce empty strings that break command construction.

**How to avoid:**
1. Use `setdefault("system_prompt", "")` in the Python upsert function to add the field to old entries on first access
2. In recovery script, provide a fallback default: `system_prompt="${system_prompt:-You are a GSD-driven agent...}"`
3. Document the default system prompt in README and SKILL.md so it's consistent across spawn.sh and recovery script
4. Test recovery with an old registry.json (without `system_prompt` field) to verify fallback works
5. Consider a registry migration script that runs once to add missing fields to all entries

**Warning signs:**
- Recovered Claude sessions don't see the expected system prompt
- `claude --append-system-prompt ""` in logs (empty prompt)
- Python KeyError or jq parse error when accessing `system_prompt`
- Agents behave differently after recovery vs. after spawn.sh (spawn has prompt, recovery doesn't)

**Phase to address:**
Phase 3 (Update spawn.sh and recover script) — add setdefault to Python, add fallback in bash, test with old registry

---

### Pitfall 8: Hook Fires for Non-Managed Sessions, Burning Tokens

**What goes wrong:**
The Stop hook is global (in `~/.claude/settings.json`), so it fires for EVERY Claude Code session on the system, not just GSD-managed ones. A developer running Claude Code manually in a random directory triggers the hook, which tries to look up the session in the registry, fails, and exits. This is harmless if the hook exits quickly, but if the hook makes expensive calls (API requests, database queries, LLM calls) before checking the registry, it burns resources on every non-managed session.

**Why it happens:**
Hooks in `~/.claude/settings.json` are user-global. There's no way to scope them to specific sessions. Developers add expensive logic (e.g., wake OpenClaw, analyze pane content with an LLM) before checking if the session is managed, assuming all sessions are managed.

**How to avoid:**
1. Fast-path exits at the top of the hook: check `$TMUX` existence, then check registry match, BEFORE any expensive operations
2. Structure hook as: consume stdin → check guards → exit if non-managed → do work
3. Use project-specific `.claude/settings.json` instead of user-global if possible (but this requires per-project config management)
4. Log non-managed session hook invocations to `/tmp/stop-hook-nonmanaged.log` for debugging, but don't block or fail
5. Document in SKILL.md that the hook is global and will fire for all sessions (expected behavior)

**Warning signs:**
- OpenClaw receives unexpected "session not in registry" logs
- Hook execution time is slow even for non-managed sessions
- API rate limits hit from hooks firing on unrelated Claude sessions
- `/tmp/stop-hook.log` shows thousands of "not managed, skipping" entries

**Phase to address:**
Phase 1 (Create stop-hook.sh) — implement fast-path guards at the top, before any expensive logic

---

### Pitfall 9: Background `openclaw agent` Inherits Hook's stdin/stdout

**What goes wrong:**
Backgrounding `openclaw agent &` in bash doesn't fully detach the process. It inherits the hook's stdin/stdout/stderr, which are connected to Claude Code's pipe. If the backgrounded process tries to read from stdin or write to stdout, it may block waiting for input or corrupt the hook's output, causing Claude Code to misinterpret the hook's result.

**Why it happens:**
Bash's `&` only backgrounds the process; it doesn't redirect file descriptors. The child process still has stdin/stdout/stderr pointing to the same pipes as the parent. If the child reads from stdin, it competes with the parent (hook) for input. If it writes to stdout, that output is mixed with the hook's JSON response.

**How to avoid:**
1. Redirect stdin/stdout/stderr when backgrounding: `openclaw agent ... </dev/null >/dev/null 2>&1 &`
2. Or use `nohup` to fully detach: `nohup openclaw agent ... >/dev/null 2>&1 &`
3. Or use `disown` after backgrounding to remove from job table: `openclaw agent ... & disown`
4. For debugging, redirect to a log file instead of /dev/null: `openclaw agent ... >>/tmp/hook-openclaw.log 2>&1 &`
5. Never rely on the background process's output — the hook must exit immediately with a known state

**Warning signs:**
- Hook hangs even though `openclaw agent` was backgrounded
- Claude Code logs show garbled JSON from the hook
- `openclaw agent` appears to wait for input despite being backgrounded
- Hook works when tested standalone but fails when called by Claude Code

**Phase to address:**
Phase 1 (Create stop-hook.sh) — add proper redirection to all backgrounded `openclaw agent` calls

**Source:**
- [Bash Background Jobs and stdin](https://www.digitalocean.com/community/tutorials/how-to-use-bash-s-job-control-to-manage-foreground-and-background-processes)
- [Spawning Independent Processes in Linux Bash](https://linuxvox.com/blog/spawn-an-entirely-separate-process-in-linux-via-bash/)

---

### Pitfall 10: Tmux Session Detection Race Condition During Recovery

**What goes wrong:**
The recovery script checks if a tmux session exists with `tmux has-session -t "$SESSION"`, then immediately tries to attach or send keys to it. Between the check and the action, the session could have been killed (user manually killed it, OOM killed it, systemd timeout). The script then fails with "session not found" despite the check passing, causing the recovery to abort or hang.

**Why it happens:**
Time-of-check to time-of-use (TOCTOU) race condition. The check and the action are not atomic. In multi-agent recovery, if sessions are created/destroyed concurrently (e.g., manual spawn.sh while recovery is running), the state can change between check and use.

**How to avoid:**
1. Don't rely on `has-session` checks — directly attempt the operation and handle failure
2. Wrap all tmux commands in error handling: `tmux send-keys ... || log_warn "session died during recovery"`
3. Use tmux's `-t` flag error handling: it will fail gracefully if session doesn't exist
4. In recovery script, remove `set -e` so individual tmux failures don't abort the entire recovery
5. Add retry logic with backoff: if session is being created, retry send-keys up to 3 times with 0.5s delay

**Warning signs:**
- Recovery script fails with "session not found" despite just creating the session
- `tmux list-sessions` shows the session exists, but send-keys still fails
- Recovery succeeds on manual retry but fails on first boot attempt
- Logs show successful session creation followed immediately by "session not found"

**Phase to address:**
Phase 3 (Update recover-openclaw-agents.sh) — remove set -e, add retry logic to tmux operations, handle failures gracefully

**Source:**
- [Tmux Race Condition: Config Loading](https://github.com/tmux/tmux/issues/2438)
- [Tmux Session Attach Race](https://github.com/tmux/tmux/issues/2398)

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Skip flock on registry writes | Faster development, no lock contention | Registry corruption when multiple spawns/recoveries run concurrently | Never (corruption risk too high) |
| Use global ~/.claude/settings.json for hooks | Single config, applies everywhere | Hook fires for all sessions, including non-managed ones | Only if fast-path guards are implemented |
| Background openclaw without redirecting stdin/stdout | Simpler code | Hook hangs or produces garbled output | Never (breaks hook contract) |
| Remove set -e from bash scripts | Errors don't abort script | Silent failures accumulate | Only in recovery scripts where partial success is better than total failure |
| Use send-keys without -l flag | Familiar syntax | Garbled commands on concurrent spawns | MVP only, refactor to -l in Phase 3 |
| Hardcode system_prompt in recovery script | No registry schema change needed | Prompts diverge between spawn and recovery | MVP only, add to registry in Phase 1 |

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| Claude Code Stop hook | Assume stdin is optional | Always consume stdin first (cat > /dev/null or jq) |
| Claude Code settings.json | Assume changes apply immediately | Restart Claude session for hook changes to take effect |
| Tmux send-keys | Assume atomic operation | Use send-keys -l for literal mode, add delays between calls |
| Systemd recovery service | Assume script success = system recovered | Send global summary to OpenClaw even on partial failure |
| OpenClaw agent calls | Assume background & is enough | Redirect stdin/stdout/stderr: </dev/null >/dev/null 2>&1 & |
| Recovery registry JSON | Assume reads are safe | Validate JSON after every write: jq empty < file \|\| restore |

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Hook fires for all sessions | Hook latency on every response | Fast-path guards before expensive logic | When user has >5 simultaneous Claude sessions |
| Polling watcher still running | Duplicate events, wasted CPU | Kill all watchers in Phase 4, add migration flag | During migration (Phase 2-3) |
| No delay between concurrent spawns | send-keys corruption | Sequential processing with sleep 0.5 between agents | When spawning 3+ agents in recovery |
| Unbuffered JSON writes | File corruption on crash/OOM | Atomic write via temp file + mv | When system is under memory pressure |

## Security Mistakes

| Mistake | Risk | Prevention |
|---------|------|------------|
| System prompt contains secrets | Secrets visible in ps aux, logs | Never put credentials in system_prompt, use env vars |
| Registry file world-readable | OpenClaw session IDs exposed | chmod 600 recovery-registry.json |
| Hook script logs full pane content | Sensitive data in logs | Sanitize pane content before logging (redact API keys, tokens) |
| Background processes run as root | Privilege escalation if hook exploited | Always run hooks as non-root user (forge) |

## "Looks Done But Isn't" Checklist

- [ ] **Stop hook:** Often missing stdin consumption — verify `cat > /dev/null` is first line after set -euo pipefail
- [ ] **Background openclaw calls:** Often missing stdin/stdout redirection — verify `</dev/null >/dev/null 2>&1 &`
- [ ] **Registry writes:** Often missing atomic write pattern — verify write to temp file, then mv
- [ ] **Recovery script:** Often missing per-agent error handling — verify each agent recovery is wrapped in || log_failure
- [ ] **Tmux send-keys:** Often missing -l flag — verify all send-keys use literal mode for multi-char strings
- [ ] **System prompt fallback:** Often missing in recovery script — verify default prompt if registry field is empty
- [ ] **Migration overlap:** Often missing deduplication logic — verify stop-hook checks for old watcher state files
- [ ] **Global hook guards:** Often missing fast-path exit — verify $TMUX and registry check before expensive logic

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Stop hook infinite loop | MEDIUM | 1. Kill Claude session 2. Add stop_hook_active guard 3. Restart session |
| stdin pipe blocking | LOW | 1. Kill hook process 2. Add cat > /dev/null to script 3. Hook resumes on next Claude response |
| Registry corruption | HIGH | 1. Restore from backup (/tmp backup before migration) 2. Manually reconstruct entries 3. Re-spawn agents |
| send-keys corruption | LOW | 1. Kill garbled session 2. Spawn new session (spawn.sh handles retry) 3. Add delays to recovery script |
| Recovery script failure | HIGH | 1. Check systemctl status 2. systemctl reset-failed 3. Fix script 4. Manually spawn critical agents |
| Duplicate events (migration) | LOW | Accept as temporary, or: 1. Kill old watchers (pkill -f hook-watcher) 2. Remove watcher state files |
| Missing system_prompt | MEDIUM | 1. Add setdefault to Python 2. Add fallback to bash 3. Re-run spawn.sh to update registry |
| Hook fires for non-managed | LOW | Accept as expected, or: 1. Move hook to project .claude/settings.json 2. Add fast-path guard |
| Background process inherits stdin | MEDIUM | 1. Kill hook 2. Add redirects to background call 3. Hook resumes on next response |
| Tmux session race | MEDIUM | 1. Retry recovery manually 2. Add retry logic to script 3. Remove set -e from recovery script |

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| Stop hook infinite loop | Phase 1 (stop-hook.sh creation) | Test: call hook twice rapidly, verify second exits early |
| stdin pipe blocking | Phase 1 (stop-hook.sh creation) | Test: echo large JSON \| hook.sh, verify no hang |
| Registry corruption | Phase 3 (spawn.sh, recover script) | Test: run spawn.sh 3x in parallel, verify registry valid |
| send-keys corruption | Phase 3 (spawn.sh, recover script) | Test: spawn 5 agents via recovery, verify all start correctly |
| Recovery script failure | Phase 3 (recover script refactor) | Test: introduce error in registry, verify partial recovery + summary sent |
| Duplicate events | Phase 2 (wire Stop hook) + Phase 4 (cleanup) | Test: spawn session with old watcher, add Stop hook, verify single wake |
| Missing system_prompt | Phase 3 (spawn.sh, recover script) | Test: load old registry without field, verify fallback prompt used |
| Hook fires for non-managed | Phase 1 (stop-hook.sh creation) | Test: start Claude outside tmux, verify hook exits fast (<10ms) |
| Background inherits stdin | Phase 1 (stop-hook.sh creation) | Test: hook runs in pipe, verify openclaw call doesn't block |
| Tmux session race | Phase 3 (recover script refactor) | Test: kill session between has-session and send-keys, verify graceful handling |

## Sources

### Hook Development & stdin Handling
- [Claude Code Hooks 2026: Automate Your Dev Workflow - ClaudeWorld](https://claude-world.com/articles/hooks-development-guide/)
- [Claude Code Hooks: Complete Guide with 20+ Ready-to-Use Examples (2026)](https://aiorg.dev/blog/claude-code-hooks)
- [Debugging a Ghost in the Machine: Session Isolation for Claude Code Plugins](https://jonroosevelt.com/blog/claude-code-session-isolation-hooks)
- [Be careful when redirecting both stdin and stdout to pipes](https://devblogs.microsoft.com/oldnewthing/20110707-00/?p=10223)

### Polling to Event-Driven Migration
- [Why we replaced polling with event triggers (Jan 2026)](https://medium.com/@systemdesignwithsage/why-we-replaced-polling-with-event-triggers-234ecda134b2)
- [Software Pragmatism - Polling and Event Driven Systems](https://www.softwarepragmatism.com/polling-event-driven)

### Tmux Race Conditions
- [Agent teams should spawn in new tmux window, not split current pane (Issue #23615)](https://github.com/anthropics/claude-code/issues/23615)
- [Race condition loading config file when starting server + session (Issue #2438)](https://github.com/tmux/tmux/issues/2438)
- [send-keys Ctrl-Z breaks code execution inconsistently (Issue #3360)](https://github.com/tmux/tmux/issues/3360)

### JSON Concurrent Write Corruption
- [JSON corruption due concurrent file write (EdgeApp)](https://github.com/EdgeApp/edge-core-js/issues/258)
- [JSON getting corrupted when writing from multiple processes (lowdb)](https://github.com/typicode/lowdb/issues/333)
- [A brief analysis of JSON file-backed storage (Mozilla)](https://mozilla.github.io/firefox-browser-architecture/text/0012-jsonfile.html)

### Systemd Recovery & Critical Infrastructure
- [Set up self-healing services with systemd](https://www.redhat.com/en/blog/systemd-automate-recovery)
- [Implementing Service Recovery and Restart Policies in systemd](https://dohost.us/index.php/2025/10/27/implementing-service-recovery-and-restart-policies-in-systemd/)
- [Diagnosing Boot Problems](https://systemd.io/DEBUGGING/)
- [Troubleshooting Ubuntu Systemd Services That Fail at Boot](https://www.mindfulchase.com/explore/troubleshooting-tips/operating-systems/troubleshooting-ubuntu-systemd-services-that-fail-at-boot-but-work-manually.html)

### Bash Background Processes
- [How To Use Bash's Job Control to Manage Foreground and Background Processes](https://www.digitalocean.com/community/tutorials/how-to-use-bash-s-job-control-to-manage-foreground-and-background-processes)
- [How to Spawn a Separate Process in Linux Using Bash](https://linuxvox.com/blog/spawn-an-entirely-separate-process-in-linux-via-bash/)

---
*Pitfalls research for: Hook-Driven OpenClaw Agent Control for Claude Code Sessions*
*Researched: 2026-02-17*
*Researcher: GSD Project Researcher*
*Confidence: HIGH — based on official Claude Code documentation, real-world GitHub issues (2026), and established bash/tmux best practices*

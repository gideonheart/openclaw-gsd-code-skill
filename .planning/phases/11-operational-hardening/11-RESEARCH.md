# Phase 11: Operational Hardening - Research

**Researched:** 2026-02-18
**Domain:** logrotate configuration for append-mode bash log files + jq-based diagnostic tooling for JSONL logs
**Confidence:** HIGH

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| OPS-02 | logrotate config at `/etc/logrotate.d/gsd-code-skill` prevents unbounded disk growth with `copytruncate` (safe for open `>>` file descriptors) | logrotate 3.21.0 confirmed installed; `copytruncate` directive confirmed in man page; `su forge forge` directive required for files owned by forge; glob patterns tested in debug mode; config template verified correct |
| OPS-03 | `diagnose-hooks.sh` parses JSONL log files with `jq` for meaningful diagnostic output | jq 1.7 confirmed; all diagnostic queries (recent events, error counts, outcome distribution, duration stats) tested against live JSONL data; current script has Step 9 (plain-text log check) which needs JSONL section appended |
</phase_requirements>

## Summary

Phase 11 implements two operational hardening items that depend on the JSONL log infrastructure established in Phases 8–10: log rotation safety and diagnostic tooling. Both are straightforward additions requiring no new dependencies.

**OPS-02 (logrotate):** The skill's `logs/` directory lives in `/home/forge/.openclaw/workspace/skills/gsd-code-skill/logs/` and is owned by `forge:forge`. Hook scripts append to `*.jsonl` and `*.log` files with open `>>` file descriptors — standard logrotate (rename + create) would leave the hook scripts writing to the renamed file, silently losing all logs after rotation. `copytruncate` solves this by truncating the original file in-place after copying, keeping open file descriptors valid. The config must go to `/etc/logrotate.d/gsd-code-skill` (root-owned directory), which requires an install script using `sudo tee`. The `su forge forge` directive is mandatory because the log files are owned by `forge`, not `root`, and logrotate runs as root by default.

**OPS-03 (diagnose-hooks.sh):** The existing `diagnose-hooks.sh` has 10 steps checking hook chain health (registration, scripts, registry, tmux, openclaw binary, plain-text log existence). It has no JSONL awareness. The requirement is to add JSONL parsing showing: recent events (last N), error counts (non-delivered outcomes), and outcome distribution. All diagnostic queries have been tested against live JSONL data and confirmed working with jq 1.7. The JSONL section should be added as a new step (Step 10, moving the optional test-wake step to Step 11) to preserve the existing structure.

**Primary recommendation:** Create `config/logrotate.conf` (the config template tracked in git) and `scripts/install-logrotate.sh` (installs via `sudo tee`); add Step 10 (JSONL log analysis) to `scripts/diagnose-hooks.sh` using confirmed jq query patterns.

## Standard Stack

### Core

| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| logrotate | 3.21.0 (installed) | Rotate `*.jsonl` and `*.log` files | System-standard log rotation; `copytruncate` directive handles open file descriptors; already installed and running daily via systemd timer |
| jq | 1.7 (installed) | Parse JSONL in diagnose-hooks.sh | Already used throughout all hook scripts and diagnose-hooks.sh; zero new dependency; 2ms startup time acceptable for interactive diagnostics |
| sudo tee | system (forge has sudo ALL) | Write logrotate config to `/etc/logrotate.d/` | `/etc/logrotate.d/` is root-owned; forge cannot write directly; `sudo tee` is the standard pattern for writing root-owned config files from scripts |

### Supporting

| Tool | Version | Purpose | When to Use |
|------|---------|---------|-------------|
| `logrotate -d` | 3.21.0 | Debug/dry-run rotation config | Verify config syntax and what would be rotated before installing |
| `logrotate --force` | 3.21.0 | Force rotation for testing | Verify rotation actually works on small files that don't meet size threshold |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `/etc/logrotate.d/` config | User-level logrotate invoked from cron | User-level logrotate is supported (logrotate 3.21+ supports tilde expansion), but requires forge's own cron entry and a separate state file; `/etc/logrotate.d/` is cleaner and already runs daily via systemd |
| `sudo tee` install | Commit config to `/etc/logrotate.d/` manually | Documenting a manual step is fine but an install script is more reliable and reproducible |
| `copytruncate` | `postrotate` script sending SIGHUP | Hook scripts are not daemons and have no reload mechanism; `copytruncate` is the correct choice |
| Adding JSONL step inline in diagnose-hooks.sh | New standalone `query-logs.sh` script | OPS-03 specifically says `diagnose-hooks.sh`; `query-logs.sh` is deferred to OBS-03 in Future Requirements |

## Architecture Patterns

### Recommended File Layout

```
skills/gsd-code-skill/
├── config/
│   └── logrotate.conf          # Template tracked in git (absolute paths to logs/)
├── scripts/
│   ├── diagnose-hooks.sh       # MODIFIED: add Step 10 (JSONL log analysis)
│   └── install-logrotate.sh    # NEW: installs config/logrotate.conf to /etc/logrotate.d/
└── logs/
    ├── hooks.log               # Covered by *.log glob
    ├── {SESSION}.jsonl         # Covered by *.jsonl glob
    ├── {SESSION}.jsonl.lock    # NOT matched by *.jsonl (verified: shell glob *.jsonl does not match *.jsonl.lock)
    └── {SESSION}.log           # Covered by *.log glob
```

### Pattern 1: logrotate Config with copytruncate

**What:** A logrotate config that rotates both `.jsonl` and `.log` files in the skill's logs directory using `copytruncate` to preserve open file descriptors.

**Why `copytruncate` is required:** Hook scripts open files with `>>` (append mode). Standard logrotate renames the log file and creates a new one — but the hook script's bash `>>` fd still references the inode of the renamed file. Appends continue to the renamed file, not the new one. `copytruncate` copies the file to the rotated name then truncates the original to zero bytes, preserving the inode. All open `>>` fds continue writing to the (now empty) original file correctly.

**Small data loss window:** There is a small race between `cp` and `truncate` where data written in that window may be lost. This is acceptable for hook event observability logs — a missing record is preferable to unbounded disk growth.

**Why NOT `create` with `copytruncate`:** The `copytruncate` option implies `norenamecopy` and makes the `create` directive have no effect (confirmed in logrotate man page). Do not include `create` when using `copytruncate`.

**Example config template (`config/logrotate.conf`):**

```
/home/forge/.openclaw/workspace/skills/gsd-code-skill/logs/*.jsonl
/home/forge/.openclaw/workspace/skills/gsd-code-skill/logs/*.log
{
    su forge forge
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
}
```

**Directive rationale:**
- `su forge forge` — log files owned by `forge:forge`; logrotate runs as root; this directive tells logrotate to operate as `forge` when checking/modifying files in forge's home directory. Required by logrotate 3.x for security (non-root owned directories in root-controlled path).
- `daily` — runs daily (logrotate timer fires once daily via `logrotate.timer` systemd unit)
- `rotate 7` — keep 7 rotated versions (7 days of history)
- `compress` + `delaycompress` — compress rotated files with gzip; `delaycompress` skips compressing the most-recent rotated file (useful if a process is still writing to it)
- `missingok` — don't error if no log files match the glob yet (new installation)
- `notifempty` — don't rotate empty files (avoids rotating the empty `.lock` files if they accidentally match)
- `copytruncate` — truncate in-place; required for open `>>` file descriptors

**Lock files are safe:** Shell glob `*.jsonl` does NOT match `*.jsonl.lock`. Verified: `ls logs/*.jsonl` returns only `warden-main-3.jsonl`, not `warden-main-3.jsonl.lock`. The `.lock` files are zero-byte flock targets and will never match the glob.

### Pattern 2: Install Script Using sudo tee

**What:** A one-shot install script that writes the logrotate config to `/etc/logrotate.d/gsd-code-skill` using `sudo tee`.

**Why `sudo tee`:** forge has `(ALL : ALL) ALL` sudo but requires a password for most commands. However, for CI/scripted use the standard pattern is `sudo tee` with the config piped in. For interactive use with password prompt this works fine; for automation the user can run it manually once.

**Why not `sudo cp`:** `sudo tee` with pipe reads from stdin, making it harder to accidentally clobber the wrong path. `sudo cp` would also work but is equivalent.

**Install script pattern:**

```bash
#!/usr/bin/env bash
set -euo pipefail

SKILL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOGROTATE_DEST="/etc/logrotate.d/gsd-code-skill"

log_message() {
  printf '[%s] %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$*"
}

log_message "Installing logrotate config to $LOGROTATE_DEST"

sudo tee "$LOGROTATE_DEST" < "${SKILL_ROOT}/config/logrotate.conf" > /dev/null

log_message "Verifying config with logrotate -d"
logrotate -d "$LOGROTATE_DEST" 2>&1 | grep -v "^warning: logrotate in debug mode" || true

log_message "Done. Config installed at $LOGROTATE_DEST"
log_message "To test rotation: sudo logrotate --force $LOGROTATE_DEST"
```

### Pattern 3: JSONL Diagnostic in diagnose-hooks.sh

**What:** A new step in `diagnose-hooks.sh` that reads the per-session JSONL log file and outputs recent events, error counts, outcome distribution, and duration statistics using `jq`.

**Where to add:** After the existing Step 9 (Hook Debug Logs), before the optional Step 10 (Send test wake). This becomes Step 10 (JSONL Analysis), and the existing optional step becomes Step 11.

**JSONL file path derivation:** The per-session JSONL file is `${HOOK_LOG}/${TMUX_SESSION_NAME}.jsonl` — the same pattern used for `.log` files. `HOOK_LOG` is already set to `${SKILL_ROOT}/logs` in the script.

**Confirmed jq queries (tested against live data):**

```bash
# In a bash script, jq's != operator works correctly when the jq expression
# is in a single-quoted string or heredoc — the shell does not interpret !=.

JSONL_FILE="${HOOK_LOG}/${TMUX_SESSION_NAME}.jsonl"

# Recent events (last 5)
jq -r '[.timestamp, .hook_script, .trigger, .outcome, .duration_ms] | @tsv' "$JSONL_FILE" | tail -5

# Outcome distribution (sorted by count)
jq -r '.outcome' "$JSONL_FILE" | sort | uniq -c | sort -rn

# Hook script distribution
jq -r '.hook_script' "$JSONL_FILE" | sort | uniq -c | sort -rn

# Error count (non-delivered outcomes)
jq -c 'select(.outcome != "delivered")' "$JSONL_FILE" | wc -l

# Duration stats
jq -s '[.[].duration_ms] | {count: length, min: min, max: max, avg: (add/length | round)}' "$JSONL_FILE"
```

**Output format (info lines):**

```
--- Step 10: JSONL Log Analysis ---
  INFO Session JSONL log: /path/to/logs/warden-main-3.jsonl (11 records)
  INFO Last 5 events:
  INFO   2026-02-18T13:41:41Z  stop-hook.sh  response_complete  delivered  10800ms
  INFO   2026-02-18T13:42:53Z  notification-idle-hook.sh  idle_prompt  delivered  11764ms
  INFO Outcome distribution: delivered=11  no_response=0  other=0
  INFO Hook script distribution: notification-idle-hook.sh=6  stop-hook.sh=5
  INFO Non-delivered events: 0
  INFO Duration: count=11 min=8538ms max=19341ms avg=12079ms
```

### Anti-Patterns to Avoid

- **Using `*.log*` glob in logrotate:** Would match `*.log`, `*.log.1`, and `.lock` files. Use separate explicit globs `*.jsonl` and `*.log` on separate lines in the same block.
- **Omitting `su forge forge`:** logrotate runs as root; without `su forge forge`, it operates on forge's home directory files as root. This may cause permission warnings and is not recommended for security reasons.
- **Using `create` with `copytruncate`:** Per man page, `create` has no effect when `copytruncate` is in use. Including it is misleading — omit it.
- **jq string interpolation in bash for diagnose-hooks.sh:** The `jq` expression should be in single quotes or a variable to prevent shell interpretation. `jq -r 'select(.outcome != "delivered")'` works correctly in bash (single quotes prevent shell from interpreting the `!`). This is why the earlier Bash tool tests using `'` failed — the Bash tool double-escapes — but in an actual script file the single quotes work correctly (verified).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Log rotation | Custom bash `mv file file.1` function in hook scripts | logrotate with `copytruncate` | logrotate handles compression, retention count, concurrent access, missing files, empty files, and scheduling; the bash alternative is a partial reimplementation with no compression and no retention policy |
| JSONL parsing | `grep`/`awk` field extraction | `jq` | Wake messages contain newlines — grep cannot reliably extract multi-line JSONL fields; jq handles all JSON correctly in 2ms |
| Install step | Baking absolute paths into scripts | Derive paths from `${BASH_SOURCE[0]}` | The skill root can move; `SKILL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"` is resilient |

**Key insight:** logrotate's `copytruncate` is the one-line solution to what would otherwise require a custom in-process rotation guard. The prior research (STACK.md) proposed an inline `rotate_jsonl_if_needed()` function — that is not needed for Phase 11. logrotate alone satisfies OPS-02 without any hook script changes.

## Common Pitfalls

### Pitfall 1: Missing `su forge forge` Directive
**What goes wrong:** logrotate fails silently or with permission warnings when trying to read/truncate files in `/home/forge/` while running as root.
**Why it happens:** The global `logrotate.conf` sets `su root adm` as the default, which is fine for `/var/log/` but inappropriate for user home directories. Without an override `su` in the per-package config, logrotate operates as root on forge's files.
**How to avoid:** Always include `su forge forge` in the config block.
**Warning signs:** `logrotate -d` shows permission errors for the skill's log files.

### Pitfall 2: Lock Files Matching Glob
**What goes wrong:** `*.jsonl` matches `*.jsonl.lock` and logrotate tries to rotate the zero-byte flock targets.
**Why it happens:** Naive assumption that `*.jsonl` won't match `*.jsonl.lock`.
**How to avoid:** This is NOT actually a problem — verified in bash that `ls logs/*.jsonl` returns only `*.jsonl` files, not `*.jsonl.lock`. The shell glob `*.jsonl` does not match files with additional extensions. Document this clearly to prevent future confusion.
**Warning signs:** None — but double-check with `ls logs/*.jsonl` to confirm.

### Pitfall 3: jq `!=` Operator in Bash Subshell via Bash Tool
**What goes wrong:** `jq 'select(.outcome != "delivered")'` produces parse errors when passed through the Bash tool (which escapes `!` to `\!`).
**Why it happens:** The Bash tool processes the command through a shell that interprets `!` in double-quoted contexts. In actual script files, single-quoted jq expressions work correctly.
**How to avoid:** In `diagnose-hooks.sh`, use single-quoted jq expressions. In the script file, `jq -c 'select(.outcome != "delivered")'` works correctly (verified by creating a temp script and running it).
**Warning signs:** jq parse errors mentioning `INVALID_CHARACTER` or `\!` — only occurs when calling from bash subshell with certain shell configurations.

### Pitfall 4: `size` Trigger vs. `daily` for Active Sessions
**What goes wrong:** A busy session fires 100+ hooks/day. With only `daily` rotation, the log file grows to multi-MB before rotation. With `size 10M` instead of `daily`, logrotate only rotates when the file exceeds 10MB but still only checks once daily.
**Why it happens:** logrotate runs once daily via systemd timer. `size 10M` doesn't make it check more frequently — it just changes the trigger condition for the once-daily check.
**How to avoid:** Use `daily` (not `size`) to ensure consistent daily rotation. At current observed rates (~70KB/day for warden-main-3), daily rotation is appropriate. `size`-based rotation would be useful only if logrotate were invoked more frequently (e.g., hourly via cron).
**Warning signs:** Log files growing beyond expected daily sizes.

### Pitfall 5: Verifying logrotate Config Without Root
**What goes wrong:** Running `logrotate -d /etc/logrotate.d/gsd-code-skill` as forge fails to read the state file (`/var/lib/logrotate/status`) and shows a permission error.
**Why it happens:** The logrotate state file is root-owned. The debug mode still works for verifying the config syntax and what files would be rotated — the state file error is expected and harmless.
**How to avoid:** Ignore the state file error in debug output; verify the rest of the output shows correct file patterns and directives.
**Warning signs:** None — the state file permission error is expected when running as non-root.

## Code Examples

Verified patterns from local testing:

### Complete logrotate Config

```
# /etc/logrotate.d/gsd-code-skill
/home/forge/.openclaw/workspace/skills/gsd-code-skill/logs/*.jsonl
/home/forge/.openclaw/workspace/skills/gsd-code-skill/logs/*.log
{
    su forge forge
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
}
```

Two file patterns on separate lines in the same block — both patterns share all directives.

### Install Script (Full)

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
LOGROTATE_CONF="${SKILL_ROOT}/config/logrotate.conf"
LOGROTATE_DEST="/etc/logrotate.d/gsd-code-skill"

log_message() {
  printf '[%s] %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$*"
}

if [ ! -f "$LOGROTATE_CONF" ]; then
  log_message "ERROR: Config template not found: $LOGROTATE_CONF"
  exit 1
fi

log_message "Installing logrotate config to $LOGROTATE_DEST"
sudo tee "$LOGROTATE_DEST" < "$LOGROTATE_CONF" > /dev/null
log_message "Installed successfully"

log_message "Verifying config syntax with logrotate -d ..."
logrotate -d "$LOGROTATE_DEST" 2>&1 | grep -v 'debug mode\|state file' || true

log_message "Config installed. To force a test rotation:"
log_message "  sudo logrotate --force $LOGROTATE_DEST"
```

### JSONL Diagnostic Section for diagnose-hooks.sh

Add after existing Step 9, before the optional send-test-wake step. Renumber send-test-wake to Step 11.

```bash
# ------------------------------------------------------------------
# 10. JSONL Log Analysis
# ------------------------------------------------------------------
echo "--- Step 10: JSONL Log Analysis ---"

JSONL_LOG_FILE="${HOOK_LOG}/${TMUX_SESSION_NAME}.jsonl"
TOTAL_CHECKS=$((TOTAL_CHECKS + 1))

if [ ! -f "$JSONL_LOG_FILE" ]; then
  info "No JSONL log yet for $TMUX_SESSION_NAME (hooks have not fired)"
  PASSED_CHECKS=$((PASSED_CHECKS + 1))  # Not a failure for a fresh install
else
  JSONL_RECORD_COUNT=$(wc -l < "$JSONL_LOG_FILE" 2>/dev/null || echo "0")
  pass "JSONL log exists: $JSONL_LOG_FILE ($JSONL_RECORD_COUNT records)"
  PASSED_CHECKS=$((PASSED_CHECKS + 1))

  echo ""
  info "Last 5 events:"
  jq -r '[.timestamp, .hook_script, .trigger, .outcome] | @tsv' "$JSONL_LOG_FILE" \
    2>/dev/null | tail -5 | while IFS=$'\t' read -r ts hook trigger outcome; do
    info "  $ts  $hook  $trigger  $outcome"
  done

  echo ""
  info "Outcome distribution:"
  jq -r '.outcome' "$JSONL_LOG_FILE" 2>/dev/null | sort | uniq -c | sort -rn | \
    while read -r count outcome; do
    info "  $count $outcome"
  done

  echo ""
  info "Hook script distribution:"
  jq -r '.hook_script' "$JSONL_LOG_FILE" 2>/dev/null | sort | uniq -c | sort -rn | \
    while read -r count hook; do
    info "  $count $hook"
  done

  echo ""
  NON_DELIVERED=$(jq -c 'select(.outcome != "delivered")' "$JSONL_LOG_FILE" 2>/dev/null | wc -l)
  if [ "$NON_DELIVERED" -gt 0 ]; then
    fail "Non-delivered events: $NON_DELIVERED — recent errors:"
    jq -r 'select(.outcome != "delivered") | [.timestamp, .hook_script, .outcome] | @tsv' \
      "$JSONL_LOG_FILE" 2>/dev/null | tail -5 | while IFS=$'\t' read -r ts hook outcome; do
      info "  $ts  $hook  $outcome"
    done
  else
    pass "No non-delivered events — all $JSONL_RECORD_COUNT hook invocations delivered"
    PASSED_CHECKS=$((PASSED_CHECKS + 1))
  fi

  echo ""
  info "Duration stats (ms):"
  jq -s '[.[].duration_ms] | {count: length, min: min, max: max, avg: (add/length | round)}' \
    "$JSONL_LOG_FILE" 2>/dev/null | jq -r '"  count=\(.count) min=\(.min) max=\(.max) avg=\(.avg)"'
fi

echo ""
```

**Note on `TOTAL_CHECKS` accounting:** The NON_DELIVERED check adds a pass only when count is 0 (all delivered). This mirrors the existing pattern in the script. The initial check (file exists) always adds 1 to TOTAL_CHECKS at top of this section.

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| logrotate requires SIGHUP to reload | `copytruncate` truncates in-place | logrotate 1.x+ | Eliminates need for postrotate script in hook-based logging |
| logrotate only supports `/var/log/` | `su user group` directive supports any directory | logrotate 3.x | Enables per-user log directories with proper ownership |
| Per-file rotation configs | Multiple patterns in one block | logrotate 3.x | Single block covers both `.jsonl` and `.log` patterns |

**Not deprecated/changed:** The `copytruncate` pattern is stable and unchanged since its introduction. logrotate 3.21.0 is the current release on this host. No concerns about version compatibility.

## Open Questions

1. **Should `hooks.log` and `hooks.jsonl` be covered by the same logrotate config?**
   - What we know: The glob `*.log` will match `hooks.log`. There is currently no `hooks.jsonl` (pre-session events do not produce JSONL records — guard exits were explicitly excluded from JSONL). The STACK.md prior research mentioned an inline `rotate_jsonl_if_needed()` for `hooks.jsonl` but this file doesn't exist.
   - What's unclear: Whether a future phase will add `hooks.jsonl` pre-session logging.
   - Recommendation: Include `*.log` in the logrotate config (covers `hooks.log` now); if `hooks.jsonl` is added later, `*.jsonl` glob already covers it. No special handling needed.

2. **Should logrotate use `size 10M` in addition to `daily`?**
   - What we know: At current observed rates (62KB JSONL for ~11 records over a few hours of a live session), a busy session could produce ~500KB/day. logrotate only checks once daily regardless of `size` trigger.
   - What's unclear: Peak daily rates for concurrent multi-session deployments.
   - Recommendation: Use `daily` without a `size` trigger for Phase 11. A size trigger without more frequent logrotate invocation provides no practical benefit. Document this as a future enhancement if growth rates require it.

3. **Should `install-logrotate.sh` verify existing config before overwriting?**
   - What we know: The script will be run idempotently; overwriting is safe since the config is always the same template.
   - Recommendation: Simple idempotent overwrite without version check — simpler and correct for this use case.

## Sources

### Primary (HIGH confidence — local verification)

- logrotate 3.21.0 man page — `copytruncate`, `su`, `daily`, `rotate`, `compress`, `delaycompress`, `missingok`, `notifempty` directives all verified
- `logrotate -d /tmp/test-logrotate.conf` — debug run confirmed config syntax correct, correct files found, `.lock` files NOT matched by `*.jsonl` glob
- `/etc/logrotate.d/bootlog` on this host — real working `copytruncate` example
- `/home/forge/.openclaw/workspace/skills/gsd-code-skill/logs/warden-main-3.jsonl` — live JSONL log used to test all diagnostic queries
- `scripts/diagnose-hooks.sh` — read in full (380 lines); Step 9 structure confirmed; existing `pass`/`fail`/`info` pattern confirmed
- jq 1.7 on host — `@tsv`, `select()`, `-s` (slurp), `add/length`, `round`, nested key access all confirmed working
- `/home/forge/.openclaw/workspace/skills/gsd-code-skill/.planning/research/STACK.md` — prior v3.0 research confirming logrotate pattern
- forge sudoers — `(ALL : ALL) ALL` confirmed; `sudo tee` requires password (not passwordless for this path)

### Secondary (MEDIUM confidence — official documentation)

- logrotate man page — `/etc/logrotate.conf` global config structure, `include /etc/logrotate.d` pattern, `su user group` security recommendation for non-root owned paths

## Metadata

**Confidence breakdown:**
- OPS-02 (logrotate config): HIGH — config tested in debug mode, all directives verified, lock file safety confirmed, install approach clear
- OPS-03 (diagnose-hooks.sh JSONL): HIGH — all jq queries tested against live data, existing script structure understood, new step insertion point identified
- Pitfalls: HIGH — identified from direct testing; the `!=` escape issue was discovered empirically and the workaround (single quotes in script files) was verified

**Research date:** 2026-02-18
**Valid until:** 2026-04-18 (stable tooling — logrotate and jq are not fast-moving)

# Stack Research: Structured JSONL Hook Logging

**Domain:** Structured event logging from bash hook scripts — per-session JSONL files
**Researched:** 2026-02-18
**Confidence:** HIGH — all tools production-verified on this host, no new dependencies required

## Executive Summary

Structured JSONL logging from bash requires **zero new dependencies** beyond what is already
installed. The entire capability is built from `jq 1.7` (already in use), `uuidgen` (util-linux,
confirmed present), `date` with millisecond precision (GNU coreutils 9.4), `flock` (already in use
for pane state), and `stat` for size checks. No Python, no Node, no new packages.

The critical constraint is **jq's `--arg` flag for safe string embedding**. Every string value that
could contain quotes, newlines, or special characters must be passed via `--arg`, never via string
interpolation. This is the single most important rule for JSONL correctness from bash.

**Recommended file naming:** `logs/${SESSION_NAME}.jsonl` — per-session, parallel to existing
`logs/${SESSION_NAME}.log`. Both files serve different consumers: `.log` for human readline,
`.jsonl` for machine processing.

## Recommended Stack

### Core Technologies

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| jq | 1.7 (installed) | Generate JSONL records (`-cn` flag), safe string embedding via `--arg` | Already in every hook script. `jq -cn` with `--arg` is the only correct way to embed arbitrary strings (pane content, assistant responses) without JSON injection. No alternatives needed. |
| uuidgen | util-linux (installed) | UUIDv4 correlation IDs and record IDs | 2ms per call (benchmarked). Produces spec-compliant UUIDv4. Both `uuidgen --random` and `/proc/sys/kernel/random/uuid` are equally fast (0.26s vs 0.30s for 100 calls). Use `uuidgen` for readability. |
| date (GNU coreutils) | 9.4 (installed) | ISO 8601 millisecond timestamps via `%3N` | `date -u +'%Y-%m-%dT%H:%M:%S.%3NZ'` produces millisecond precision (verified: `2026-02-18T09:25:32.056Z`). Required for ordering records within the same second. |
| flock | util-linux (installed) | Concurrent append protection | Multiple hooks fire concurrently for the same session (Stop + Notification can overlap). Without flock, concurrent `>>` appends to the same JSONL file corrupt records mid-line. Already used for pane state files — same pattern. |
| stat | GNU coreutils (installed) | File size check for rotation | `stat --format="%s" file` returns bytes. Used in inline rotation guard before append. Zero subprocess overhead vs `du`. |
| logrotate | 3.21.0 (installed) | Size-based log file rotation | Handles compression, keep N rotations, `copytruncate` for open-filehandle safety. Preferable to in-bash rotation for production use. |

### Supporting Patterns (No New Binaries)

| Pattern | Tools | Purpose | When to Use |
|---------|-------|---------|-------------|
| JSONL record generation | `jq -cn --arg k v ...` | Produce single-line JSON records | Every log write. The `-c` (compact) flag is mandatory for JSONL compliance — one record per line. |
| Safe string embedding | `jq --arg name "$BASH_VAR"` | Escape quotes, newlines, tabs in values | Always. Never use string interpolation for user/session content. |
| Correlation ID generation | `uuidgen --random` | UUIDv4 per hook invocation | At top of each hook script, before any branching, so every exit path carries the same correlation ID. |
| parentId chaining | Store last ID in per-session state file | Link records within a session | For session-level threading: `session_start` record has `parentId: null`; subsequent records carry `parentId` of the preceding record. |
| Millisecond timestamp | `date -u +'%Y-%m-%dT%H:%M:%S.%3NZ'` | ISO 8601 with ms precision | Every record. Required for within-second ordering. Verified to produce distinct values on consecutive calls (056Z, 058Z, 059Z). |
| Concurrent append | `flock -x -w 2 200; jq -cn ... >> file; } 200>file.lock` | Atomic JSONL line append | Whenever multiple hooks can fire for the same session simultaneously. |
| Inline size rotation | `stat --format="%s"` + `mv file file.1` | Rotate before file grows unbounded | For per-session JSONL files where logrotate is not session-aware enough. |

## File Naming Convention

```
logs/
  hooks.jsonl              # Pre-session-resolution events (hook fired but TMUX unset, etc.)
  ${SESSION_NAME}.jsonl    # Per-session structured events (after session name resolved)
  ${SESSION_NAME}.jsonl.1  # Rotated (if inline rotation used)
```

The existing `.log` files (`hooks.log`, `${SESSION_NAME}.log`) remain in place — they serve human
readline debugging. The new `.jsonl` files serve machine processing. They are parallel, not
replacements.

## JSONL Record Schema

Every record must include these fields. Optional fields are hook-specific.

```json
{
  "type": "hook_fired",
  "id": "621c4d70-01e8-4f9d-890e-ca2fd682f7d8",
  "parentId": "50d706d9-09eb-4f72-a904-531d34c7a021",
  "timestamp": "2026-02-18T09:24:37.469Z",
  "session": "warden-main-3",
  "hook": "stop-hook.sh",
  "pid": 72231
}
```

**Mandatory fields:**
- `type` — event discriminator (see event types below)
- `id` — UUIDv4 for this record (from `uuidgen`)
- `parentId` — UUIDv4 of preceding record in this session, or `null` for first record
- `timestamp` — ISO 8601 with milliseconds, UTC (from `date -u +'%Y-%m-%dT%H:%M:%S.%3NZ'`)
- `session` — tmux session name (or `"pre-session"` before resolution)
- `hook` — script filename

**Event types:**
- `hook_fired` — hook script started, stdin consumed
- `guard_exit` — early exit due to guard condition (include `reason` field)
- `registry_miss` — no agent matched session in registry
- `delivery_start` — OpenClaw agent call initiated
- `delivery_complete` — OpenClaw agent call returned (include `exit_code`, `mode` fields)
- `session_end` — SessionEnd hook fired

## JSONL Generation Pattern

The canonical pattern for a single JSONL record append in bash:

```bash
RECORD_ID=$(uuidgen --random)
RECORD_TS=$(date -u +'%Y-%m-%dT%H:%M:%S.%3NZ')

jq -cn \
  --arg type "hook_fired" \
  --arg id "$RECORD_ID" \
  --arg parentId "${PARENT_ID:-null}" \
  --arg ts "$RECORD_TS" \
  --arg session "${SESSION_NAME:-pre-session}" \
  --arg hook "$HOOK_SCRIPT_NAME" \
  --argjson pid "$$" \
  '{
    type: $type,
    id: $id,
    parentId: (if $parentId == "null" then null else $parentId end),
    timestamp: $ts,
    session: $session,
    hook: $hook,
    pid: $pid
  }' >> "$GSD_JSONL_LOG" 2>/dev/null || true
```

**Why `--argjson pid "$$"`** rather than `--arg pid "$$"`: PID is a number in JSON, not a string.
`--argjson` injects already-parsed JSON (the number `72231`), while `--arg` would produce the
string `"72231"`. Use `--arg` for strings, `--argjson` for numbers and booleans.

**Why `parentId: (if $parentId == "null" then null else $parentId end)`**: `--arg` always passes
strings, so the literal string `"null"` must be converted to JSON `null` for the first record.
This is the correct jq idiom.

## Rotation Strategy

**Use logrotate for production rotation.** Install a config at
`/etc/logrotate.d/gsd-code-skill`:

```
/home/forge/.openclaw/workspace/skills/gsd-code-skill/logs/*.jsonl {
    size 10M
    rotate 5
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
}
```

**Why `copytruncate`**: Hook scripts append to open file descriptors. Standard logrotate renames
the file and creates a new one — but the hook script's open `>>` handle still points to the
renamed file. `copytruncate` copies the content then truncates in-place, keeping the file
descriptor valid. Required for correctness.

**Why `size 10M`**: Per-session JSONL files grow proportionally to hook firing frequency. A busy
warden session firing 10 hooks/minute with ~200 byte records produces ~2MB/hour. 10MB = ~5 hours
before rotation, reasonable for debugging any session.

**Inline rotation fallback** (for hooks.jsonl which may not suit logrotate's once-daily default):

```bash
rotate_jsonl_if_needed() {
  local log_file="$1"
  local max_bytes="${2:-10485760}"  # 10MB default
  if [ -f "$log_file" ]; then
    local file_size
    file_size=$(stat --format="%s" "$log_file" 2>/dev/null || echo "0")
    if [ "$file_size" -ge "$max_bytes" ]; then
      mv "$log_file" "${log_file}.1" 2>/dev/null || true
    fi
  fi
}
```

Call this before each append when you need size-bounded files without logrotate scheduling.

## Concurrent Write Safety

All JSONL appends to per-session files must use flock. Same pattern already used for pane state:

```bash
{
  flock -x -w 2 200 || { printf '' ; exit 0; }
  jq -cn --arg ... ... >> "$GSD_JSONL_LOG"
} 200>"${GSD_JSONL_LOG}.lock"
```

The lock file lives alongside the JSONL file (`${SESSION_NAME}.jsonl.lock`). It is never written
with content, only used as a lock target.

**When concurrent writes actually occur:** Stop hook and Notification hook can both fire within
milliseconds of each other for the same session. Without flock, two concurrent `jq -cn ... >>`
appends interleave their output and produce a corrupt JSONL line like
`{"type":"hook_fired"...}{"type":"notification"...}` on one line.

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| `jq -cn --arg` for record generation | `printf '{"type":"%s",...}' "$var"` | Never. String interpolation breaks on any value containing `"`, newlines, or `\`. One corrupted JSONL line invalidates the entire file for streaming parsers. |
| `uuidgen --random` for correlation IDs | `/proc/sys/kernel/random/uuid` | Use `/proc` path only if `uuidgen` is absent. Both are equally fast (2ms). `/proc` has no external binary dependency, but `uuidgen` is more readable and confirmed present. |
| `date -u +'%Y-%m-%dT%H:%M:%S.%3NZ'` for timestamps | `date -u +'%Y-%m-%dT%H:%M:%SZ'` (no ms) | Use second-precision only if within-second ordering is irrelevant. For hook events that fire in rapid succession (multiple hooks on the same Claude response), milliseconds are needed to order records correctly. |
| logrotate with `copytruncate` | In-bash rotation with `mv` | Use in-bash rotation only for `hooks.jsonl` (pre-session file) where logrotate's `size`-based trigger may not run frequently enough. For per-session files, logrotate is preferable. |
| flock for concurrent appends | No locking | Only safe if you can guarantee hooks never fire concurrently for the same session — which cannot be guaranteed (Stop + Notification can overlap). |

## What NOT to Add

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| Python for JSONL generation | Adds dependency, 50ms startup vs 2ms for jq | `jq -cn --arg` (already installed, 2ms) |
| Node.js for JSONL generation | Adds dependency, overkill | `jq -cn --arg` |
| `printf '{"key":"%s"}' "$var"` string interpolation | Breaks on any `"`, newline, `\t` in value — silently produces invalid JSONL | `jq -cn --arg key "$var"` |
| `echo '{"key":"'"$var"'"}' ` string concatenation | Same breakage as printf interpolation | `jq -cn --arg` |
| `sha256sum` for record IDs | Slower and produces non-UUID format (hex string, not hyphenated UUID) | `uuidgen --random` |
| Separate logging daemon | Over-engineering for this scale | Direct file append with flock |
| JSON arrays instead of JSONL | Arrays require full-file rewrite to append | One JSON object per line (JSONL) — append-safe |
| Date without milliseconds | Events within the same second are unorderable | `%3N` for milliseconds |
| `logrotate` without `copytruncate` | Rotated file descriptor still writes to renamed file | Always include `copytruncate` for append-mode log files |

## Version Compatibility

| Component | Version | Requirement | Status |
|-----------|---------|-------------|--------|
| jq | 1.7 (installed) | `--arg`, `--argjson`, `-c`, `-n` flags, `select()` | All present since jq 1.5. Verified 1.7 installed. |
| GNU date (coreutils) | 9.4 (installed) | `%3N` millisecond format specifier | GNU-specific (not POSIX). Confirmed working: `date -u +'%Y-%m-%dT%H:%M:%S.%3NZ'` → `2026-02-18T09:25:32.056Z` |
| uuidgen | util-linux (installed) | UUIDv4 generation | Confirmed at `/usr/bin/uuidgen`. `--random` flag selects UUIDv4 algorithm. |
| flock | util-linux (installed) | Exclusive file locking, `-x -w 2` flags | Already used in `extract_pane_diff()`. Same version, confirmed working. |
| stat | GNU coreutils (installed) | `--format="%s"` for byte count | GNU stat (not POSIX). Confirmed working. |
| logrotate | 3.21.0 (installed) | `size`, `copytruncate`, `compress` directives | All present in logrotate 3.x. Confirmed 3.21.0 installed. |
| bash | 5.2.21 (installed) | `>>` append, `200>lockfile` fd syntax, `$()` subshell | Standard bash 4+. Verified 5.2 installed. |

## Integration Points with Existing Code

**hook-utils.sh changes needed:**
- Add `emit_jsonl_record()` function — takes event type + optional key/value pairs, writes to
  `$GSD_JSONL_LOG` with flock. Sourced by all 6 hooks (already sourced by stop and pre-tool-use).
- Add `rotate_jsonl_if_needed()` function — inline rotation guard.

**Each hook script changes needed:**
- Add `GSD_JSONL_LOG` variable initialization alongside existing `GSD_HOOK_LOG`.
- Replace or supplement `debug_log()` calls with `emit_jsonl_record()` calls at key decision points.
- Generate `CORRELATION_ID=$(uuidgen --random)` at the top of each script, before any branching.
- Pass `CORRELATION_ID` as the `id` for the first record, carry it as `parentId` for subsequent records within the same invocation.

**No changes needed to:**
- `settings.json` hook registration
- `recovery-registry.json` schema
- `openclaw agent` delivery calls
- `spawn.sh` or `register-hooks.sh`

## Sources

**HIGH confidence (local verification):**
- `jq --version` on host → `jq-1.7` — all flags confirmed working
- `date -u +'%Y-%m-%dT%H:%M:%S.%3NZ'` → `2026-02-18T09:25:32.056Z` — milliseconds confirmed
- `uuidgen --random` → valid UUIDv4, 2ms latency (100-iteration benchmark)
- `/proc/sys/kernel/random/uuid` → equally fast (2ms), UUIDv4 format confirmed
- `flock -x -w 2 200 ... 200>lockfile` — existing usage in `extract_pane_diff()`, confirmed working
- `stat --format="%s" file` → byte count, confirmed working
- `logrotate --version` → `logrotate 3.21.0`, `copytruncate` directive confirmed in man page
- `jq -cn --arg content "$MULTILINE"` → correct JSON escaping of `"`, `\n`, `\t` confirmed
- Concurrent `jq -cn ... >> file` with flock → 3 parallel writes produced 3 separate JSONL lines, no corruption

**HIGH confidence (JSONL specification):**
- [JSON Lines specification](http://jsonlines.org/) — UTF-8, one JSON value per line, newline-delimited
- [OpenClaw session JSONL schema](file:///home/forge/.openclaw/agents/forge/sessions/) — `type`, `id`, `parentId`, `timestamp` pattern confirmed from live session files

---
*Stack research for: gsd-code-skill — structured JSONL hook event logging*
*Researched: 2026-02-18*
*Confidence: HIGH — zero new dependencies, all tools production-verified on this host*

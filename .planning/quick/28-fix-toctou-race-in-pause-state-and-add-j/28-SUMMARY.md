---
phase: quick-28
status: complete
commit: b1f14be
date: 2026-03-05
---

# Quick Task 28: Fix TOCTOU race and add JSON CLI output

## What Was Done

### 1. Fixed TOCTOU race in setSessionPauseState

**Problem:** `pause-state.json` is a shared file across ALL sessions. Two concurrent hooks for different sessions could read the same file, both modify their entry, and one write silently drops the other's changes. Per-session queue files don't have this problem because they're isolated.

**Fix:** Added exclusive file lock using `O_CREAT|O_EXCL` (atomic per POSIX) with:
- `acquireExclusiveLockOnPauseStateFile()` — retry loop with `Atomics.wait` sleep (zero CPU spin)
- `removeStaleLockFileIfExpired()` — detects and removes locks left by crashed processes (>5s old)
- `releaseExclusiveLockOnPauseStateFile()` — cleanup in `finally` block
- **Fail-open:** if lock can't be acquired after ~1s, write proceeds unlocked with a warn log

**Verified:** Concurrent writes test — two sessions pausing simultaneously both preserved their entries.

### 2. Switched CLI to JSON output

**Before:** `Session 'x' paused.` (human string, requires string matching to parse)
**After:** `{"session":"x","paused":true}` (JSON, `JSON.parse(stdout)` in warden)

### 3. Updated WARDEN-PAUSE-INTEGRATION.md

- Architecture section: documents locking and lock-free reads
- PATCH endpoint: uses `JSON.parse(stdout)` instead of hardcoded response
- Why-shell-out section: mentions exclusive file lock as a reason

## Design Decisions

- **O_CREAT|O_EXCL over flock CLI** — Pure Node.js, no subprocess overhead. POSIX guarantees atomicity.
- **Atomics.wait over busy loop** — Zero CPU usage during retry sleep.
- **Stale lock detection** — 5s threshold handles process crashes without manual intervention.
- **Fail-open on lock failure** — Consistent with read fail-open philosophy. Losing a pause update is annoying but not dangerous.
- **Lock-free reads** — `isSessionPaused` does NOT acquire the lock. Reads are always fast and never block.

## Verification

```
$ node bin/pause-session.mjs test on
{"session":"test","paused":true}

$ node bin/pause-session.mjs test status
{"session":"test","paused":true}

$ node bin/pause-session.mjs test off
{"session":"test","paused":false}

# Concurrent writes — both sessions preserved:
$ node bin/pause-session.mjs a on & node bin/pause-session.mjs b on & wait
$ cat logs/pause-state.json  # Both "a" and "b" present

# Lock file cleaned up:
$ ls logs/pause-state.json.lock 2>&1
No such file or directory (expected)
```

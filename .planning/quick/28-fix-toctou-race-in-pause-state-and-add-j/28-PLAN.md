---
phase: quick-28
plan: 28
type: execute
wave: 1
depends_on: [27]
files_modified:
  - lib/pause-state.mjs
  - bin/pause-session.mjs
  - docs/WARDEN-PAUSE-INTEGRATION.md
autonomous: true
---

# Quick Task 28: Fix TOCTOU race and add JSON CLI output

## Tasks

1. **Fix TOCTOU race in setSessionPauseState** — Add O_CREAT|O_EXCL exclusive file lock around the read-modify-write cycle. pause-state.json is shared across all sessions (unlike per-session queue files). Stale lock detection for crash safety. Fail-open fallback.

2. **Switch bin/pause-session.mjs to JSON output** — Replace human-readable strings with JSON for machine consumption by warden.

3. **Update WARDEN-PAUSE-INTEGRATION.md** — Reflect JSON output and locking changes.

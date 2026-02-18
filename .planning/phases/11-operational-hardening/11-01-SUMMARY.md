---
phase: 11-operational-hardening
plan: 01
subsystem: infra
tags: [bash, logrotate, copytruncate, log-rotation, systemd]

# Dependency graph
requires:
  - phase: 08-jsonl-logging-foundation
    provides: per-session JSONL log files in logs/ directory, hook scripts appending with >> file descriptors
provides:
  - config/logrotate.conf: logrotate config template covering *.jsonl and *.log with copytruncate
  - scripts/install-logrotate.sh: one-shot installer that writes config to /etc/logrotate.d/ via sudo tee
affects:
  - operational-maintenance (logrotate runs daily via systemd timer, no further action needed)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "copytruncate for log rotation with open >> file descriptors — preserves inode, truncates in-place"
    - "sudo tee for writing root-owned config files from user-space install scripts"
    - "su forge forge directive for logrotate operating on non-root-owned log directories"

key-files:
  created:
    - config/logrotate.conf
    - scripts/install-logrotate.sh
  modified: []

key-decisions:
  - "copytruncate over rename+create — hook scripts hold open >> file descriptors that would silently lose data after standard rename-based rotation"
  - "daily rotation without size trigger — logrotate only checks once daily regardless, and observed rates (~70KB/day) make daily rotation appropriate"
  - "No create directive — has no effect when copytruncate is in use per logrotate man page"
  - "Single block covering both *.jsonl and *.log patterns — shared directives, simpler config"

patterns-established:
  - "Pattern: logrotate config templates tracked in config/ with install script in scripts/"
  - "Pattern: BASH_SOURCE-derived SKILL_ROOT for resilient path resolution in install scripts"

requirements-completed: [OPS-02]

# Metrics
duration: 2min
completed: 2026-02-18
---

# Phase 11 Plan 01: Logrotate Config and Install Script Summary

**Production-grade log rotation with copytruncate for hook JSONL and plain-text logs — prevents unbounded disk growth while preserving open file descriptors**

## Performance

- **Duration:** 2 min
- **Started:** 2026-02-18T13:53:00Z
- **Completed:** 2026-02-18T13:55:00Z
- **Tasks:** 2
- **Files modified:** 2 (2 created)

## Accomplishments

- Created `config/logrotate.conf` with `copytruncate` covering both `*.jsonl` and `*.log` patterns with absolute paths to skill logs directory
- Created `scripts/install-logrotate.sh` as executable installer using `sudo tee` pattern with config template verification via `logrotate -d`
- Verified config syntax with `logrotate -d` — correctly identifies all 3 log files (warden-main-3.jsonl, hooks.log, warden-main-3.log)

## Task Commits

Both tasks committed atomically:

1. **Task 1+2: Logrotate config and install script** - `b7d8270` (feat)

## Files Created/Modified

- `config/logrotate.conf` - Logrotate config template with copytruncate, su forge forge, daily rotation, 7-day retention, compress + delaycompress
- `scripts/install-logrotate.sh` - One-shot installer using sudo tee to write config to /etc/logrotate.d/gsd-code-skill, with logrotate -d verification

## Decisions Made

None - followed plan as specified.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

Run `scripts/install-logrotate.sh` once to install the logrotate config to `/etc/logrotate.d/gsd-code-skill` (requires sudo password). After installation, logrotate runs automatically daily via systemd timer.

## Next Phase Readiness

- Logrotate config template is ready for installation
- Config verified with `logrotate -d` showing correct file pattern matching
- Lock files (*.jsonl.lock) confirmed NOT matched by *.jsonl glob

---
*Phase: 11-operational-hardening*
*Completed: 2026-02-18*

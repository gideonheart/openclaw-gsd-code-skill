---
phase: quick-8
plan: "01"
subsystem: installer/docs
tags: [cleanup, logrotate, docs, install]
dependency_graph:
  requires: []
  provides: [logrotate-free-codebase]
  affects: [scripts/install.sh, SKILL.md, README.md, docs/hooks.md]
tech_stack:
  added: []
  patterns: []
key_files:
  created: []
  modified:
    - scripts/install.sh
    - SKILL.md
    - README.md
    - docs/hooks.md
  deleted:
    - config/logrotate.conf
    - scripts/install-logrotate.sh
decisions:
  - "Removed logrotate entirely -- user-space skill should not require sudo/root system config"
  - "install.sh now has 5 steps (pre-flight, logs dir, hooks, diagnostics, banner)"
metrics:
  duration: "~3 min"
  completed: "2026-02-18"
  tasks_completed: 2
  tasks_total: 2
---

# Quick Task 8: Remove logrotate dependency and update all docs

**One-liner:** Deleted logrotate config and install script, stripped all references from install.sh (5 clean steps), SKILL.md, README.md, and docs/hooks.md.

## Tasks Completed

| # | Task | Commit | Files |
|---|------|--------|-------|
| 1 | Delete logrotate files and clean install.sh | 1437612 | config/logrotate.conf (deleted), scripts/install-logrotate.sh (deleted), scripts/install.sh |
| 2 | Remove logrotate references from all documentation | a280418 | SKILL.md, README.md, docs/hooks.md |

## What Was Done

### Task 1

Removed two files from the repository:
- `config/logrotate.conf` -- logrotate template requiring `/etc/logrotate.d/` (root-owned)
- `scripts/install-logrotate.sh` -- sudo-dependent install script

Updated `scripts/install.sh`:
- Removed the `LOGROTATE_FAILED=false` constant
- Removed the sudo pre-flight check (`if ! command -v sudo`)
- Removed Step 4 "Install Logrotate Config" block (call to install-logrotate.sh, LOGROTATE_FAILED assignment)
- Removed the logrotate failure banner at the end
- Renumbered: old Step 5 (Diagnostics) -> Step 4; old Step 6 (Banner) -> Step 5
- Result: 5 clean steps, zero logrotate or LOGROTATE references, passes `bash -n`

### Task 2

Updated three documentation files:

**SKILL.md:**
- Removed the `install-logrotate.sh` utility block (heading, code block, description paragraph)
- Removed the `Logrotate:` configuration section
- Removed the logrotate line from v3.0 Changes

**README.md:**
- Removed the "### 4. Install logrotate (recommended)" section (15 lines)
- Renumbered "### 5. Verify daemon" -> "### 4. Verify daemon"
- Renumbered "### 6. Test spawn" -> "### 5. Test spawn"
- Removed `scripts/install-logrotate.sh` row from Scripts table
- Removed `config/logrotate.conf` row from Config Files table

**docs/hooks.md:**
- Removed the "Log rotation handled by..." paragraph from Log File Lifecycle section

## Deviations from Plan

None - plan executed exactly as written.

## Verification

All success criteria confirmed:

- `config/logrotate.conf` deleted
- `scripts/install-logrotate.sh` deleted
- `scripts/install.sh` has zero logrotate references and passes `bash -n` syntax check
- `SKILL.md` has zero logrotate references
- `README.md` has zero logrotate references and consistent step numbering 1-5
- `docs/hooks.md` has zero logrotate references
- `grep -r logrotate --include='*.sh' --include='*.md' --include='*.conf' --include='*.txt' . | grep -v '.planning/' | grep -v '.git/'` returns zero matches

## Self-Check: PASSED

Files verified:
- FOUND: scripts/install.sh
- FOUND: SKILL.md
- FOUND: README.md
- FOUND: docs/hooks.md
- MISSING (as expected): config/logrotate.conf
- MISSING (as expected): scripts/install-logrotate.sh

Commits verified:
- FOUND: 1437612
- FOUND: a280418

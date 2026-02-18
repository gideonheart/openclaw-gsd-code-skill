---
phase: quick-8
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - config/logrotate.conf
  - scripts/install-logrotate.sh
  - scripts/install.sh
  - SKILL.md
  - README.md
  - docs/hooks.md
autonomous: true
requirements: [QUICK-8-01]

must_haves:
  truths:
    - "No logrotate config file exists in the project"
    - "No install-logrotate.sh script exists in the project"
    - "install.sh runs without referencing logrotate"
    - "All documentation mentions of logrotate are removed"
    - "Step numbering is consistent after removal"
  artifacts:
    - path: "scripts/install.sh"
      provides: "Installer without logrotate step"
      contains: "Step 4: Diagnostics"
    - path: "SKILL.md"
      provides: "Agent-facing docs without logrotate references"
    - path: "README.md"
      provides: "Admin docs without logrotate references"
    - path: "docs/hooks.md"
      provides: "Hook docs without logrotate references"
  key_links:
    - from: "scripts/install.sh"
      to: "scripts/register-hooks.sh"
      via: "direct bash invocation"
      pattern: "register-hooks\\.sh"
    - from: "scripts/install.sh"
      to: "scripts/diagnose-hooks.sh"
      via: "direct bash invocation"
      pattern: "diagnose-hooks\\.sh"
---

<objective>
Remove the logrotate dependency entirely from gsd-code-skill. Delete logrotate config and install script, update install.sh to remove the logrotate step, and strip all logrotate references from SKILL.md, README.md, and docs/hooks.md.

Purpose: logrotate was a bad decision -- it requires sudo (system dependency for a user-space skill), needs root-owned config in /etc/, is overkill for files that barely grow (~200KB/day), has a data loss window with copytruncate, makes install.sh more complex, and is not portable.

Output: Clean codebase with no logrotate references in any shipped files.
</objective>

<execution_context>
@/home/forge/.claude/get-shit-done/workflows/execute-plan.md
@/home/forge/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@config/logrotate.conf
@scripts/install-logrotate.sh
@scripts/install.sh
@SKILL.md
@README.md
@docs/hooks.md
</context>

<tasks>

<task type="auto">
  <name>Task 1: Delete logrotate files and clean install.sh</name>
  <files>config/logrotate.conf, scripts/install-logrotate.sh, scripts/install.sh</files>
  <action>
1. Delete `config/logrotate.conf` (use `git rm`).
2. Delete `scripts/install-logrotate.sh` (use `git rm`).
3. Update `scripts/install.sh`:
   - Remove the comment reference to "logrotate setup" on line 5 (change to: "Orchestrates: hook registration, log directory creation,")
   - Remove the `LOGROTATE_FAILED=false` constant (line 31)
   - Remove the sudo pre-flight check (lines 47-49: the `if ! command -v sudo` block). jq check stays.
   - Remove entire Step 4 block (lines 79-92: "Step 4: Install Logrotate Config" section including the call to install-logrotate.sh and the LOGROTATE_FAILED assignment)
   - Renumber remaining steps: Step 4 becomes "Diagnostics" (was Step 5), Step 5 becomes "Next-Steps Banner" (was Step 6)
   - Remove the logrotate failure banner at the end (lines 134-137: the `if [ "${LOGROTATE_FAILED}" = true ]` block)
   - Make sure the script still has clean section separators and consistent numbering

Verify the script still follows the pattern: Step 1 (Pre-flight), Step 2 (logs dir), Step 3 (hooks), Step 4 (diagnostics), Step 5 (banner). Five steps total, no mention of logrotate or LOGROTATE_FAILED anywhere.
  </action>
  <verify>
Run: `bash -n scripts/install.sh` (syntax check passes)
Run: `grep -c logrotate scripts/install.sh` (returns 0)
Run: `grep -c LOGROTATE scripts/install.sh` (returns 0)
Run: `ls config/logrotate.conf scripts/install-logrotate.sh 2>&1` (both "No such file")
Run: `grep -c 'Step [0-9]' scripts/install.sh` (returns 5 -- steps 1 through 5)
  </verify>
  <done>config/logrotate.conf and scripts/install-logrotate.sh are deleted. scripts/install.sh has no logrotate references, no LOGROTATE_FAILED variable, no sudo check, steps renumbered 1-5, and passes bash -n syntax check.</done>
</task>

<task type="auto">
  <name>Task 2: Remove logrotate references from all documentation</name>
  <files>SKILL.md, README.md, docs/hooks.md</files>
  <action>
**SKILL.md** -- Remove these sections/lines:

1. Remove the entire "install-logrotate.sh" utility block (lines 144-150): the heading, code block, and description paragraph that starts with "Installs `config/logrotate.conf`...".
2. Remove the "Logrotate" configuration block (lines 177-179): the `**Logrotate:** \`config/logrotate.conf\`` heading and the description paragraph about template for log rotation.
3. Remove the logrotate line from v3.0 Changes section (line 197): the line that reads `**Logrotate:** \`config/logrotate.conf\` with copytruncate handles both...`.

**README.md** -- Remove these sections/lines:

1. Remove entire "### 4. Install logrotate (recommended)" section (lines 108-122): the heading, description, code block, verify command, and all text.
2. Renumber subsequent steps: "### 5. Verify daemon" becomes "### 4. Verify daemon", "### 6. Test spawn" becomes "### 5. Test spawn".
3. Remove the `scripts/install-logrotate.sh` row from the Scripts table (line 536): `| \`scripts/install-logrotate.sh\` | Install logrotate config... |`
4. Remove the `config/logrotate.conf` row from the Config Files table (line 546): `| \`config/logrotate.conf\` | Logrotate template... |`

**docs/hooks.md** -- Remove logrotate reference:

1. In the "Log File Lifecycle" section (line 391), remove the entire paragraph: "Log rotation handled by `config/logrotate.conf` (installed via `scripts/install-logrotate.sh`). Uses `copytruncate` for safe rotation while hooks hold open `>>` file descriptors."

Do NOT modify any .planning/ files (STATE.md, ROADMAP.md, etc.) -- those are historical records.
  </action>
  <verify>
Run: `grep -c logrotate SKILL.md` (returns 0)
Run: `grep -c logrotate README.md` (returns 0)
Run: `grep -c logrotate docs/hooks.md` (returns 0)
Run: `grep -c 'install-logrotate' SKILL.md README.md docs/hooks.md` (returns 0 for each)
Run: `grep '### [0-9]' README.md` to confirm steps are numbered 1-5 sequentially with no gap.
  </verify>
  <done>All three documentation files have zero references to logrotate, install-logrotate.sh, or logrotate.conf. README.md Pre-Flight steps are numbered 1-5 consecutively.</done>
</task>

</tasks>

<verification>
1. `grep -r logrotate --include='*.sh' --include='*.md' --include='*.conf' --include='*.txt' . | grep -v '.planning/' | grep -v '.git/'` returns empty (no logrotate references outside planning history)
2. `bash -n scripts/install.sh` passes
3. `ls config/logrotate.conf scripts/install-logrotate.sh 2>&1 | grep -c 'No such file'` returns 2
4. `ls config/` still contains `default-system-prompt.txt`, `recovery-registry.example.json` (other configs unaffected)
5. `ls scripts/` still contains all other scripts (only install-logrotate.sh removed)
</verification>

<success_criteria>
- config/logrotate.conf deleted
- scripts/install-logrotate.sh deleted
- scripts/install.sh has zero logrotate references and passes syntax check
- SKILL.md has zero logrotate references
- README.md has zero logrotate references and consistent step numbering
- docs/hooks.md has zero logrotate references
- No shipped file outside .planning/ references logrotate
</success_criteria>

<output>
After completion, create `.planning/quick/8-remove-logrotate-dependency-and-update-a/8-SUMMARY.md`
</output>

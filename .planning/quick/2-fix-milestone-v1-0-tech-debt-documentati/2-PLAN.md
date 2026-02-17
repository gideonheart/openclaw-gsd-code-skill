---
phase: quick-2
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - config/recovery-registry.example.json
  - .planning/REQUIREMENTS.md
  - .planning/phases/03-launcher-updates/03-01-SUMMARY.md
  - .planning/phases/03-launcher-updates/03-02-SUMMARY.md
  - .planning/phases/04-cleanup/04-01-SUMMARY.md
  - .planning/phases/05-documentation/05-01-SUMMARY.md
  - .planning/phases/05-documentation/05-02-SUMMARY.md
autonomous: true
requirements: [CONFIG-07, SPAWN-01, SPAWN-02, SPAWN-03, SPAWN-04, SPAWN-05, RECOVER-01, RECOVER-02, CLEAN-01, CLEAN-02, CLEAN-03, DOCS-01, DOCS-02]

must_haves:
  truths:
    - "recovery-registry.example.json comment accurately describes replacement model"
    - "REQUIREMENTS.md CONFIG-07 text matches actual implementation (replacement model)"
    - "All 38 requirement checkboxes in REQUIREMENTS.md are marked [x]"
    - "All SUMMARY files use REQ-IDs in provides field, not concept descriptions"
  artifacts:
    - path: "config/recovery-registry.example.json"
      provides: "Accurate comment for system_prompt field"
      contains: "replacement"
    - path: ".planning/REQUIREMENTS.md"
      provides: "All requirements marked checked with correct CONFIG-07 text"
      contains: "[x] **CONFIG-07**"
    - path: ".planning/phases/03-launcher-updates/03-01-SUMMARY.md"
      provides: "REQ-IDs in provides field"
      contains: "SPAWN-01"
    - path: ".planning/phases/05-documentation/05-02-SUMMARY.md"
      provides: "REQ-IDs in provides field"
      contains: "DOCS-02"
  key_links:
    - from: ".planning/REQUIREMENTS.md"
      to: "CONFIG-07 text"
      via: "replacement model wording"
      pattern: "replacement"
---

<objective>
Fix three documentation inconsistencies identified in the v1.0 milestone audit as tech debt.

Purpose: Bring documentation into alignment with actual implementation so future readers are not misled by stale or inconsistent text.
Output: Updated comment in recovery-registry.example.json, corrected REQUIREMENTS.md with all checkboxes checked, and SUMMARY files using REQ-IDs in provides fields.
</objective>

<execution_context>
@/home/forge/.claude/get-shit-done/workflows/execute-plan.md
@/home/forge/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/PROJECT.md
@.planning/ROADMAP.md
@.planning/STATE.md
</context>

<tasks>

<task type="auto">
  <name>Task 1: Fix recovery-registry.example.json comment and REQUIREMENTS.md</name>
  <files>
    config/recovery-registry.example.json
    .planning/REQUIREMENTS.md
  </files>
  <action>
    In config/recovery-registry.example.json line 23:
    Change the `_comment_system_prompt` field value from:
    "Per-agent system_prompt always appends to config/default-system-prompt.txt content, never replaces it. Empty string means use only the default system prompt."
    To:
    "Per-agent system_prompt replaces config/default-system-prompt.txt content entirely when set. Empty string means use only the default system prompt (fallback)."

    In .planning/REQUIREMENTS.md:
    1. Change CONFIG-07 text on line 58 from:
       "- [ ] **CONFIG-07**: Per-agent system_prompt always appends to default (never replaces)"
       To:
       "- [x] **CONFIG-07**: Per-agent system_prompt replaces default entirely when set (CLI override > agent registry > default fallback)"

    2. Change ALL remaining `- [ ]` requirement checkboxes to `- [x]` — every requirement from HOOK-01 through DOCS-02 (38 total). Do not change any headings, descriptions, or table rows, only the `[ ]` in the bullet-point requirement lines.
  </action>
  <verify>
    grep "_comment_system_prompt" config/recovery-registry.example.json | grep -c "replacement"
    # Expected: 1

    grep "CONFIG-07" .planning/REQUIREMENTS.md | grep -c "\[x\]"
    # Expected: 1

    grep -- "- \[ \]" .planning/REQUIREMENTS.md | wc -l
    # Expected: 0 (no unchecked boxes)

    grep -- "- \[x\]" .planning/REQUIREMENTS.md | wc -l
    # Expected: 38
  </verify>
  <done>recovery-registry.example.json comment says "replaces" not "appends". REQUIREMENTS.md CONFIG-07 text reflects replacement model. All 38 requirement lines use [x].</done>
</task>

<task type="auto">
  <name>Task 2: Update SUMMARY provides fields to use REQ-IDs</name>
  <files>
    .planning/phases/03-launcher-updates/03-01-SUMMARY.md
    .planning/phases/03-launcher-updates/03-02-SUMMARY.md
    .planning/phases/04-cleanup/04-01-SUMMARY.md
    .planning/phases/05-documentation/05-01-SUMMARY.md
    .planning/phases/05-documentation/05-02-SUMMARY.md
  </files>
  <action>
    Each SUMMARY file has a YAML frontmatter block. Update the `provides` field in each:

    .planning/phases/03-launcher-updates/03-01-SUMMARY.md:
    Change the `provides` list under `dependency_graph` from concept descriptions to:
      provides: [SPAWN-01, SPAWN-02, SPAWN-03, SPAWN-04, SPAWN-05]

    .planning/phases/03-launcher-updates/03-02-SUMMARY.md:
    Change the `provides` list under `dependency_graph` from concept descriptions to:
      provides: [RECOVER-01, RECOVER-02]

    .planning/phases/04-cleanup/04-01-SUMMARY.md:
    Change the `provides` list under `dependency_graph` from concept descriptions to:
      provides: [CLEAN-01, CLEAN-02, CLEAN-03]

    .planning/phases/05-documentation/05-01-SUMMARY.md:
    Change the `provides` value from [DOCS-02] to [DOCS-01].
    (This plan implemented SKILL.md + docs/hooks.md which satisfies DOCS-01, not DOCS-02)

    .planning/phases/05-documentation/05-02-SUMMARY.md:
    Change the `provides` list from concept descriptions to:
      provides: [DOCS-02]

    Only modify the `provides` field in the dependency_graph section. Do not change any other content.
  </action>
  <verify>
    grep "provides" .planning/phases/03-launcher-updates/03-01-SUMMARY.md | grep -c "SPAWN-01"
    # Expected: 1

    grep "provides" .planning/phases/03-launcher-updates/03-02-SUMMARY.md | grep -c "RECOVER-01"
    # Expected: 1

    grep "provides" .planning/phases/04-cleanup/04-01-SUMMARY.md | grep -c "CLEAN-01"
    # Expected: 1

    grep "provides" .planning/phases/05-documentation/05-01-SUMMARY.md | grep -c "DOCS-01"
    # Expected: 1

    grep "provides" .planning/phases/05-documentation/05-02-SUMMARY.md | grep -c "DOCS-02"
    # Expected: 1
  </verify>
  <done>All five SUMMARY files have REQ-IDs in their provides field. No SUMMARY uses concept descriptions in provides.</done>
</task>

</tasks>

<verification>
After both tasks complete:

1. grep "_comment_system_prompt" config/recovery-registry.example.json
   Must contain "replaces" and must NOT contain "appends"

2. grep "CONFIG-07" .planning/REQUIREMENTS.md
   Must show [x] and "replacement" wording

3. grep -- "- \[ \]" .planning/REQUIREMENTS.md
   Must return empty (zero unchecked requirement lines)

4. For each SUMMARY file, grep the provides line and confirm REQ-IDs present:
   - 03-01: SPAWN-01 through SPAWN-05
   - 03-02: RECOVER-01, RECOVER-02
   - 04-01: CLEAN-01, CLEAN-02, CLEAN-03
   - 05-01: DOCS-01 (not DOCS-02)
   - 05-02: DOCS-02
</verification>

<success_criteria>
- recovery-registry.example.json _comment_system_prompt field describes replacement model, not append model
- REQUIREMENTS.md CONFIG-07 text says "replaces default entirely when set" with CLI override priority order
- All 38 requirement lines in REQUIREMENTS.md use [x] (zero [  ] remain)
- Five SUMMARY files provide REQ-IDs matching the requirements they satisfy
</success_criteria>

<output>
After completion, create `.planning/quick/2-fix-milestone-v1-0-tech-debt-documentati/2-SUMMARY.md`
</output>

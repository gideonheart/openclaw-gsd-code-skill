---
phase: quick-21
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - lib/paths.mjs
  - lib/queue-processor.mjs
  - lib/ask-user-question.mjs
autonomous: true
requirements: [DRY-REFACTOR]

must_haves:
  truths:
    - "resolvePendingAnswerFilePath is defined exactly once across the entire codebase"
    - "QUEUES_DIRECTORY is defined exactly once across the entire codebase"
    - "queue-processor.mjs and ask-user-question.mjs both import shared path helpers from paths.mjs"
    - "hook-context.mjs TMUX guard is present and correct"
    - "All existing behavior is preserved — no functional changes"
  artifacts:
    - path: "lib/paths.mjs"
      provides: "SKILL_ROOT, QUEUES_DIRECTORY, resolvePendingAnswerFilePath"
      exports: ["SKILL_ROOT", "QUEUES_DIRECTORY", "resolvePendingAnswerFilePath"]
    - path: "lib/queue-processor.mjs"
      provides: "Queue processing logic, imports path helpers from paths.mjs"
      contains: "import.*from.*paths.mjs"
    - path: "lib/ask-user-question.mjs"
      provides: "AskUserQuestion domain logic, imports path helpers from paths.mjs"
      contains: "import.*from.*paths.mjs"
  key_links:
    - from: "lib/queue-processor.mjs"
      to: "lib/paths.mjs"
      via: "import { QUEUES_DIRECTORY, resolvePendingAnswerFilePath }"
      pattern: "import.*QUEUES_DIRECTORY.*resolvePendingAnswerFilePath.*from.*paths"
    - from: "lib/ask-user-question.mjs"
      to: "lib/paths.mjs"
      via: "import { QUEUES_DIRECTORY, resolvePendingAnswerFilePath }"
      pattern: "import.*QUEUES_DIRECTORY.*resolvePendingAnswerFilePath.*from.*paths"
---

<objective>
Eliminate DRY violations: move `resolvePendingAnswerFilePath` and `QUEUES_DIRECTORY` to lib/paths.mjs (the canonical home for path constants). Remove duplicates from queue-processor.mjs and ask-user-question.mjs. Confirm the TMUX guard in hook-context.mjs is correct.

Purpose: Both queue-processor.mjs and ask-user-question.mjs define identical `QUEUES_DIRECTORY` constants and identical `resolvePendingAnswerFilePath` functions. The comment in queue-processor.mjs claims this avoids a circular dependency, but that is incorrect — paths.mjs has no circular dependency with either module. This is a textbook DRY violation.

Output: Three modified files, zero functional changes.
</objective>

<execution_context>
@/home/forge/.claude/get-shit-done/workflows/execute-plan.md
@/home/forge/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@lib/paths.mjs
@lib/queue-processor.mjs
@lib/ask-user-question.mjs
@lib/hook-context.mjs
@lib/index.mjs
</context>

<tasks>

<task type="auto">
  <name>Task 1: Move QUEUES_DIRECTORY and resolvePendingAnswerFilePath to paths.mjs</name>
  <files>lib/paths.mjs, lib/queue-processor.mjs, lib/ask-user-question.mjs</files>
  <action>
  **lib/paths.mjs** — Add two new exports:

  1. Add `import { resolve } from 'node:path';` at the top (paths.mjs currently only imports dirname and fileURLToPath).
  2. Export `QUEUES_DIRECTORY`:
     ```js
     export const QUEUES_DIRECTORY = resolve(SKILL_ROOT, 'logs', 'queues');
     ```
  3. Export `resolvePendingAnswerFilePath`:
     ```js
     export function resolvePendingAnswerFilePath(sessionName) {
       return resolve(QUEUES_DIRECTORY, `pending-answer-${sessionName}.json`);
     }
     ```
  4. Update the module-level JSDoc comment to mention the new exports.

  **lib/queue-processor.mjs** — Remove duplicates, import from paths.mjs:

  1. Change the import line from `import { SKILL_ROOT } from './paths.mjs';` to:
     `import { QUEUES_DIRECTORY, resolvePendingAnswerFilePath } from './paths.mjs';`
  2. Delete the local `QUEUES_DIRECTORY` const (line 21).
  3. Delete the entire local `resolvePendingAnswerFilePath` function (lines 23-35) including its JSDoc comment about "duplicated intentionally".
  4. Remove `resolve` from the `node:path` import since `QUEUES_DIRECTORY` no longer needs it locally. Keep `dirname` (used by writeQueueFileAtomically).
  5. Remove `SKILL_ROOT` import — no longer needed (QUEUES_DIRECTORY comes from paths.mjs now).

  **lib/ask-user-question.mjs** — Remove duplicates, import from paths.mjs:

  1. Change the import line from `import { SKILL_ROOT } from './paths.mjs';` to:
     `import { SKILL_ROOT, QUEUES_DIRECTORY, resolvePendingAnswerFilePath } from './paths.mjs';`
     Note: Keep SKILL_ROOT because `formatQuestionsForAgent` uses `resolve(SKILL_ROOT, 'bin', 'tui-driver-ask.mjs')` on line 91.
  2. Delete the local `QUEUES_DIRECTORY` const (line 27).
  3. Delete the entire local `resolvePendingAnswerFilePath` function (lines 39-47) including its JSDoc.
  4. Remove `resolve` from the `node:path` import ONLY IF no other usage remains. Check: `resolveQuestionFilePath` (line 36) uses `resolve(QUEUES_DIRECTORY, ...)` and `formatQuestionsForAgent` (line 91) uses `resolve(SKILL_ROOT, ...)`. So `resolve` is still needed — keep it.
  5. Remove `dirname` from the `node:path` import ONLY IF no other usage remains. Check: `writeFileAtomically` (line 57) uses `dirname(filePath)`. So `dirname` is still needed — keep it.

  **Do NOT touch lib/index.mjs.** The moved function (`resolvePendingAnswerFilePath`) is private in both consumer modules — neither re-exports it. No barrel export change needed.
  </action>
  <verify>
    <automated>cd /home/forge/.openclaw/workspace/skills/gsd-code-skill && node -e "import('./lib/paths.mjs').then(m => { const p = m.resolvePendingAnswerFilePath('test'); console.log('paths OK:', p.includes('pending-answer-test.json')); console.log('QUEUES_DIR OK:', m.QUEUES_DIRECTORY.includes('logs/queues')); })" && node -e "import('./lib/queue-processor.mjs').then(m => { console.log('queue-processor OK:', typeof m.processQueueForHook === 'function'); })" && node -e "import('./lib/ask-user-question.mjs').then(m => { console.log('ask-user-question OK:', typeof m.compareAnswerWithIntent === 'function'); })" && node -e "import('./lib/index.mjs').then(m => { console.log('barrel OK:', typeof m.isSessionInAskUserQuestionFlow === 'function' && typeof m.compareAnswerWithIntent === 'function'); })"</automated>
    <manual>grep -c "resolvePendingAnswerFilePath" lib/paths.mjs lib/queue-processor.mjs lib/ask-user-question.mjs — paths.mjs should have 1 definition, the other two should have 1 import reference each (no local definitions)</manual>
  </verify>
  <done>
  - resolvePendingAnswerFilePath defined once in lib/paths.mjs, imported by both consumers
  - QUEUES_DIRECTORY defined once in lib/paths.mjs, imported by both consumers
  - The misleading "duplicated intentionally to avoid circular dependency" comment is gone
  - All module imports resolve cleanly (node -e import checks pass)
  - No functional behavior changes — same paths computed, same exports available
  </done>
</task>

<task type="auto">
  <name>Task 2: Confirm TMUX guard in hook-context.mjs</name>
  <files>lib/hook-context.mjs</files>
  <action>
  Read lib/hook-context.mjs and confirm the TMUX guard is correct. The guard should be:

  ```js
  if (!process.env.TMUX) return null;
  ```

  This line must appear BEFORE the tmux display-message call (which would fail without TMUX set).
  It must be the FIRST check in readHookContext, before agent registry lookup and stdin read.

  Current state (already verified during context read): Line 31 has `if (!process.env.TMUX) return null;` as the first check inside `readHookContext`. The module JSDoc (lines 1-11) documents the order: "1. Check tmux (cheap, no stdin) -- bail if not in tmux".

  This is correct. No changes needed. Log confirmation in the SUMMARY.
  </action>
  <verify>
    <automated>cd /home/forge/.openclaw/workspace/skills/gsd-code-skill && node -e "import('./lib/hook-context.mjs').then(m => console.log('hook-context loads OK:', typeof m.readHookContext === 'function'))"</automated>
  </verify>
  <done>
  - TMUX guard confirmed present at line 31 of hook-context.mjs
  - Guard is the first check in readHookContext, before tmux display-message call
  - No changes needed — guard is correct as-is
  </done>
</task>

</tasks>

<verification>
1. All three modified files import cleanly: `node -e "import('./lib/index.mjs')"`
2. `resolvePendingAnswerFilePath` grep shows exactly 1 definition (in paths.mjs)
3. `QUEUES_DIRECTORY` grep shows exactly 1 definition (in paths.mjs)
4. hook-context.mjs TMUX guard is on line 31, first check in readHookContext
</verification>

<success_criteria>
- Zero DRY violations: resolvePendingAnswerFilePath and QUEUES_DIRECTORY each defined once
- Zero functional changes: all existing exports and behavior preserved
- All module imports resolve without errors
- TMUX guard confirmed correct in hook-context.mjs
</success_criteria>

<output>
After completion, create `.planning/quick/21-dry-refactor-move-resolvependinganswerfi/21-SUMMARY.md`
</output>

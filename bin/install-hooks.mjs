#!/usr/bin/env node

/**
 * bin/install-hooks.mjs — Install, update, or remove GSD hooks in ~/.claude/settings.json.
 *
 * Reads the canonical hook definitions from config/hooks.json, resolves the
 * {{SKILL_ROOT}} placeholder to the actual skill directory, then merges the
 * hooks into ~/.claude/settings.json (preserving all other settings like
 * statusLine, enabledPlugins, etc.).
 *
 * Usage:
 *   node bin/install-hooks.mjs           # Install or update hooks
 *   node bin/install-hooks.mjs --remove  # Remove all hooks from settings.json
 *   node bin/install-hooks.mjs --dry-run # Show what would change without writing
 */

import { readFileSync, writeFileSync, renameSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const SKILL_ROOT = dirname(dirname(fileURLToPath(import.meta.url)));
const SETTINGS_PATH = join(process.env.HOME, '.claude', 'settings.json');
const HOOKS_SOURCE_PATH = join(SKILL_ROOT, 'config', 'hooks.json');

const removeMode = process.argv.includes('--remove');
const dryRunMode = process.argv.includes('--dry-run');

function readSettingsFile() {
  try {
    return JSON.parse(readFileSync(SETTINGS_PATH, 'utf8'));
  } catch {
    return {};
  }
}

function readCanonicalHooks() {
  const rawContent = readFileSync(HOOKS_SOURCE_PATH, 'utf8');
  const resolvedContent = rawContent.replaceAll('{{SKILL_ROOT}}', SKILL_ROOT);
  return JSON.parse(resolvedContent).hooks;
}

function countHandlerEntries(hooksObject) {
  let handlerCount = 0;
  for (const eventEntries of Object.values(hooksObject)) {
    for (const entry of eventEntries) {
      for (const hook of entry.hooks || []) {
        if (hook.command && !hook.command.includes('hook-event-logger')) {
          handlerCount++;
        }
      }
    }
  }
  return handlerCount;
}

function writeSettingsAtomically(settingsObject) {
  const temporaryPath = SETTINGS_PATH + '.tmp';
  writeFileSync(temporaryPath, JSON.stringify(settingsObject, null, 2) + '\n');
  renameSync(temporaryPath, SETTINGS_PATH);
}

// --- Main ---

const settings = readSettingsFile();
const previousEventCount = settings.hooks ? Object.keys(settings.hooks).length : 0;

if (removeMode) {
  if (!settings.hooks) {
    console.log('No hooks found in settings.json — nothing to remove.');
    process.exit(0);
  }

  delete settings.hooks;

  if (dryRunMode) {
    console.log(`[dry-run] Would remove ${previousEventCount} hook events from settings.json`);
    process.exit(0);
  }

  writeSettingsAtomically(settings);
  console.log(`Removed ${previousEventCount} hook events from ${SETTINGS_PATH}`);
  process.exit(0);
}

const canonicalHooks = readCanonicalHooks();
const eventCount = Object.keys(canonicalHooks).length;
const handlerCount = countHandlerEntries(canonicalHooks);

if (dryRunMode) {
  console.log(`[dry-run] Would install ${eventCount} hook events (${handlerCount} handlers) to ${SETTINGS_PATH}`);
  console.log(`[dry-run] Source: ${HOOKS_SOURCE_PATH}`);
  console.log(`[dry-run] SKILL_ROOT: ${SKILL_ROOT}`);

  console.log('\nEvents with handlers:');
  for (const [eventName, eventEntries] of Object.entries(canonicalHooks)) {
    const handlers = eventEntries
      .flatMap(entry => entry.hooks || [])
      .filter(hook => !hook.command.includes('hook-event-logger'));
    if (handlers.length > 0) {
      const matcherNote = eventEntries.find(entry => entry.matcher) ? ` (matcher: ${eventEntries.find(entry => entry.matcher).matcher})` : '';
      console.log(`  ${eventName}${matcherNote}: ${handlers[0].command}`);
    }
  }
  process.exit(0);
}

settings.hooks = canonicalHooks;
writeSettingsAtomically(settings);

console.log(`Installed ${eventCount} hook events (${handlerCount} handlers) to ${SETTINGS_PATH}`);
console.log(`Source: ${HOOKS_SOURCE_PATH}`);
console.log(`SKILL_ROOT: ${SKILL_ROOT}`);

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
 *   node bin/install-hooks.mjs                # Install both logger + handlers
 *   node bin/install-hooks.mjs --handlers     # Install only event handlers (no logger)
 *   node bin/install-hooks.mjs --logger       # Install only debug logger (no handlers)
 *   node bin/install-hooks.mjs --remove       # Remove all hooks from settings.json
 *   node bin/install-hooks.mjs --dry-run      # Show what would change without writing
 *
 * Flags can be combined: --handlers --dry-run
 */

import { readFileSync, writeFileSync, renameSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const SKILL_ROOT = dirname(dirname(fileURLToPath(import.meta.url)));
const SETTINGS_PATH = join(process.env.HOME, '.claude', 'settings.json');
const HOOKS_SOURCE_PATH = join(SKILL_ROOT, 'config', 'hooks.json');

const removeMode = process.argv.includes('--remove');
const dryRunMode = process.argv.includes('--dry-run');
const handlersOnly = process.argv.includes('--handlers');
const loggerOnly = process.argv.includes('--logger');

function isLoggerHookEntry(hookEntry) {
  return hookEntry.hooks?.some(hook => hook.command?.includes('hook-event-logger'));
}

function isHandlerHookEntry(hookEntry) {
  return hookEntry.hooks?.some(hook => !hook.command?.includes('hook-event-logger'));
}

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

function filterHookEntries(allHooks) {
  if (!handlersOnly && !loggerOnly) return allHooks;

  const filteredHooks = {};
  for (const [eventName, eventEntries] of Object.entries(allHooks)) {
    const kept = eventEntries.filter(entry => {
      if (handlersOnly) return isHandlerHookEntry(entry);
      if (loggerOnly) return isLoggerHookEntry(entry);
      return true;
    });
    if (kept.length > 0) {
      filteredHooks[eventName] = kept;
    }
  }
  return filteredHooks;
}

function countByType(hooksObject) {
  let loggerCount = 0;
  let handlerCount = 0;
  for (const eventEntries of Object.values(hooksObject)) {
    for (const entry of eventEntries) {
      if (isLoggerHookEntry(entry)) loggerCount++;
      if (isHandlerHookEntry(entry)) handlerCount++;
    }
  }
  return { loggerCount, handlerCount };
}

function writeSettingsAtomically(settingsObject) {
  const temporaryPath = SETTINGS_PATH + '.tmp';
  writeFileSync(temporaryPath, JSON.stringify(settingsObject, null, 2) + '\n');
  renameSync(temporaryPath, SETTINGS_PATH);
}

function describeMode() {
  if (handlersOnly) return 'handlers only';
  if (loggerOnly) return 'logger only';
  return 'all (logger + handlers)';
}

// --- Main ---

if (handlersOnly && loggerOnly) {
  console.error('Cannot use --handlers and --logger together. Use neither for both.');
  process.exit(1);
}

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

const allCanonicalHooks = readCanonicalHooks();
const filteredHooks = filterHookEntries(allCanonicalHooks);
const eventCount = Object.keys(filteredHooks).length;
const { loggerCount, handlerCount } = countByType(filteredHooks);

if (dryRunMode) {
  console.log(`[dry-run] Mode: ${describeMode()}`);
  console.log(`[dry-run] Would install ${eventCount} hook events (${loggerCount} loggers, ${handlerCount} handlers)`);
  console.log(`[dry-run] Target: ${SETTINGS_PATH}`);
  console.log(`[dry-run] Source: ${HOOKS_SOURCE_PATH}`);

  if (handlerCount > 0) {
    console.log('\nEvent handlers:');
    for (const [eventName, eventEntries] of Object.entries(filteredHooks)) {
      for (const entry of eventEntries) {
        if (!isHandlerHookEntry(entry)) continue;
        const matcherLabel = entry.matcher ? ` [${entry.matcher}]` : '';
        const command = entry.hooks[0].command;
        console.log(`  ${eventName}${matcherLabel}: ${command}`);
      }
    }
  }

  if (loggerCount > 0) {
    console.log(`\nLogger: ${loggerCount} events`);
  }
  process.exit(0);
}

settings.hooks = filteredHooks;
writeSettingsAtomically(settings);

console.log(`Installed ${eventCount} hook events (${loggerCount} loggers, ${handlerCount} handlers) — mode: ${describeMode()}`);
console.log(`Target: ${SETTINGS_PATH}`);

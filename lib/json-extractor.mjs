/**
 * lib/json-extractor.mjs — Safe JSON field extraction with null fallback.
 *
 * Provides extractJsonField() that parses a JSON string and returns the value
 * of a named field. Returns null and logs a JSONL warning for invalid JSON
 * input or missing fields.
 */

import { appendJsonlEntry } from './logger.mjs';

/**
 * Safely extract a single field from a JSON string.
 *
 * @param {string} rawJsonString - The raw JSON string to parse.
 * @param {string} fieldName - The field name to extract from the parsed object.
 * @returns {*} The field value, or null if extraction fails.
 */
export function extractJsonField(rawJsonString, fieldName) {
  if (typeof rawJsonString !== 'string' || rawJsonString === '') {
    appendJsonlEntry({
      level: 'warn',
      source: 'extractJsonField',
      message: 'Invalid JSON input: not a string or empty',
      field: fieldName,
    });
    return null;
  }

  let parsedObject;
  try {
    parsedObject = JSON.parse(rawJsonString);
  } catch (parseError) {
    appendJsonlEntry({
      level: 'warn',
      source: 'extractJsonField',
      message: 'Failed to parse JSON',
      field: fieldName,
      error: parseError.message,
    });
    return null;
  }

  if (!Object.hasOwn(parsedObject, fieldName)) {
    appendJsonlEntry({
      level: 'warn',
      source: 'extractJsonField',
      message: 'Field not found in JSON',
      field: fieldName,
    });
    return null;
  }

  return parsedObject[fieldName];
}

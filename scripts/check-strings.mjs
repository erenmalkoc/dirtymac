#!/usr/bin/env node
// Compares the strings the Swift compiler extracted from the app
// (*.stringsdata, written because SWIFT_EMIT_LOC_STRINGS = YES) with
// dirtymac/Localizable.xcstrings. Run it after a Debug build:
//
//     node scripts/check-strings.mjs build/ci
//
// Xcode only syncs the catalog when the project is built in the IDE, so
// a string added from any other editor never reaches the catalog and
// ships in English. This fails the build when code uses a key the
// catalog lacks, and when the catalog keeps a key no code uses.
// Translation completeness is checked by StringCatalogTests.

import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';

const buildRoot = process.argv[2] ?? 'build/ci';
const catalogPath = 'dirtymac/Localizable.xcstrings';
const table = 'Localizable';

function findStringsData(dir, out = []) {
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const path = join(dir, entry.name);
    if (entry.isDirectory()) findStringsData(path, out);
    else if (entry.name.endsWith('.stringsdata')) out.push(path);
  }
  return out;
}

const searchRoot = [join(buildRoot, 'Build', 'Intermediates.noindex'), buildRoot].find(existsSync);
if (!searchRoot) {
  console.log(`::error::${buildRoot} does not exist; run the Debug build first`);
  process.exit(1);
}

// Only the app target emits localizable strings; skip the test bundle.
const files = findStringsData(searchRoot).filter(
  (p) => p.includes('dirtymac.build') && !p.includes('dirtymacTests.build'),
);
if (files.length === 0) {
  console.log(`::error::no .stringsdata files under ${searchRoot}; is SWIFT_EMIT_LOC_STRINGS still on?`);
  process.exit(1);
}

const used = new Map(); // key -> source file that uses it
for (const file of files) {
  const text = readFileSync(file, 'utf8');
  let data;
  try {
    data = JSON.parse(text);
  } catch (error) {
    console.log(`::error::cannot parse ${file}: ${error.message}`);
    console.log(text.slice(0, 400));
    process.exit(1);
  }
  for (const entry of data.tables?.[table] ?? []) {
    if (typeof entry.key !== 'string') {
      console.log(`::error::unexpected .stringsdata entry in ${file}: ${JSON.stringify(entry)}`);
      process.exit(1);
    }
    if (!used.has(entry.key)) used.set(entry.key, data.source ?? file);
  }
}

const catalog = JSON.parse(readFileSync(catalogPath, 'utf8'));
const keys = new Set(Object.keys(catalog.strings));

const missing = [...used.keys()].filter((key) => !keys.has(key)).sort();
const unused = [...keys].filter((key) => !used.has(key)).sort();

console.log(`${used.size} localizable strings in code (${files.length} .stringsdata files), ${keys.size} keys in ${catalogPath}`);

for (const key of missing) {
  console.log(`::error file=${catalogPath}::"${key}" is used in ${used.get(key)} but missing from the catalog`);
}
for (const key of unused) {
  console.log(`::error file=${catalogPath}::"${key}" is in the catalog but no code uses it; delete it`);
}

if (missing.length || unused.length) process.exit(1);
console.log('String catalog matches the code.');

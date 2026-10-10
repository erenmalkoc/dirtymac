#!/usr/bin/env node
// Prints the unit-test counts from an xcresult summary and fails when
// fewer tests ran than are declared in dirtymacTests/. Without it a test
// file the target never compiles, or a host crash before the suite
// starts, leaves CI green while `xcodebuild test -quiet` prints nothing.
//
//     xcrun xcresulttool get test-results summary --path X.xcresult > summary.json
//     node scripts/ci-test-summary.mjs summary.json

import { appendFileSync, readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';

const testsDir = 'dirtymacTests';
const summary = JSON.parse(readFileSync(process.argv[2], 'utf8'));

// XCTest runs instance methods named test… that take no arguments.
const declared = readdirSync(testsDir)
  .filter((name) => name.endsWith('.swift'))
  .flatMap((name) => readFileSync(join(testsDir, name), 'utf8').match(/^\s*func test\w*\(\)/gm) ?? [])
  .length;

const count = (key) => Number(summary[key] ?? 0);
const total = count('totalTestCount');
const passed = count('passedTests');
const failed = count('failedTests');
const skipped = count('skippedTests');

const line = `Unit tests: ${total} ran, ${passed} passed, ${failed} failed, ${skipped} skipped (${declared} declared in ${testsDir}/)`;
console.log(line);
if (process.env.GITHUB_STEP_SUMMARY) appendFileSync(process.env.GITHUB_STEP_SUMMARY, `${line}\n`);

for (const failure of summary.testFailures ?? []) {
  const text = String(failure.failureText ?? '').replace(/\s+/g, ' ');
  console.log(`::error title=${failure.testName ?? 'test failure'}::${text}`);
}

if (total === 0 || total < declared) {
  console.log(`::error::only ${total} of ${declared} declared tests ran`);
  process.exit(1);
}
if (failed > 0) process.exit(1);

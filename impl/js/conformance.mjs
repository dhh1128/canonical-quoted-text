#!/usr/bin/env node
// Conformance harness for the JavaScript port of CQT 2.17.
//
// Reads the normative vectors in ../../goldens/cqt2.17.json and checks that
// algorithm_2_17 produces byte-identical UTF-8 output for every one of them.
// Exits 0 when every vector passes and 1 otherwise, so CI can gate on it.
//
//   node conformance.mjs            # summary only
//   node conformance.mjs --verbose  # one line per vector

import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const require = createRequire(import.meta.url);

const { algorithm_2_17, UNICODE_VERSION } = require(join(here, 'cqt.js'));

const goldenPath = join(here, '..', '..', 'goldens', 'cqt2.17.json');
const golden = JSON.parse(readFileSync(goldenPath, 'utf8'));

const verbose = process.argv.includes('--verbose');

function hex(bytes) {
  return Array.from(bytes, (b) => b.toString(16).padStart(2, '0')).join(' ');
}

// Show a string with every non-printable-ASCII scalar spelled out, so a
// divergence in an invisible character is legible in the diff.
function show(text) {
  let out = '';
  for (const ch of text) {
    const cp = ch.codePointAt(0);
    if (cp === 0x0a) out += '\\n';
    else if (cp === 0x0d) out += '\\r';
    else if (cp === 0x09) out += '\\t';
    else if (cp < 0x20 || cp === 0x7f) out += `<${cp.toString(16).toUpperCase().padStart(4, '0')}>`;
    else if (cp > 0x7e && !/\p{L}|\p{N}|\p{P}|\p{S}/u.test(ch)) out += `<${cp.toString(16).toUpperCase().padStart(4, '0')}>`;
    else out += ch;
  }
  return out;
}

function equalBytes(a, b) {
  if (a.length !== b.length) return false;
  for (let i = 0; i < a.length; i += 1) if (a[i] !== b[i]) return false;
  return true;
}

const encoder = new TextEncoder();
const failures = [];
let passed = 0;

if (golden.algorithm !== 'cqt2.17') {
  console.error(`golden file declares algorithm ${golden.algorithm}, expected cqt2.17`);
  process.exit(1);
}
if (golden.unicode_version !== UNICODE_VERSION) {
  console.error(
    `golden file declares Unicode ${golden.unicode_version}, port declares ${UNICODE_VERSION}`,
  );
  process.exit(1);
}

for (const testCase of golden.cases) {
  const expected = encoder.encode(testCase.output);
  let actual;
  let threw = null;
  try {
    actual = algorithm_2_17(testCase.input);
  } catch (error) {
    threw = error;
  }

  if (threw === null && equalBytes(actual, expected)) {
    passed += 1;
    if (verbose) console.log(`ok   ${testCase.id}`);
    continue;
  }

  failures.push({ testCase, expected, actual, threw });
  if (verbose) console.log(`FAIL ${testCase.id}`);
}

const total = golden.cases.length;

for (const { testCase, expected, actual, threw } of failures) {
  console.log('');
  console.log(`--- ${testCase.id}`);
  console.log(`  input    ${show(testCase.input)}`);
  if (threw) {
    console.log(`  threw    ${threw && threw.stack ? threw.stack : threw}`);
    continue;
  }
  console.log(`  expected ${show(testCase.output)}`);
  console.log(`  actual   ${show(new TextDecoder().decode(actual))}`);
  console.log(`  expected bytes ${hex(expected)}`);
  console.log(`  actual   bytes ${hex(actual)}`);
}

console.log('');
console.log(`${passed}/${total} vectors pass (Unicode ${process.versions.unicode}, ICU ${process.versions.icu})`);

process.exit(failures.length === 0 ? 0 : 1);

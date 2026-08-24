// The interactive tool at form.html is the only published artifact with no
// test behind it. It broke silently once already: the port renamed its entry
// point from algorithm_1_14 to algorithm_2_17 and moved to impl/js/, and
// neither the conformance suite nor the Pages build could see that the page
// was calling a function that no longer existed.
//
// This checks the two things that can drift: the script path form.html loads,
// and the global name it calls. It loads cqt.js the way a browser does -- as a
// classic script with no module machinery -- and runs one vector through it.

import { readFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createContext, runInContext } from 'node:vm';

const here = dirname(fileURLToPath(import.meta.url));
const repo = resolve(here, '..', '..');
const form = readFileSync(join(repo, 'form.html'), 'utf8');

const fail = (message) => { console.error(`FAIL  ${message}`); process.exitCode = 1; };

// 1. the script tag points at a file that exists
const src = form.match(/<script src="([^"]+\.js)"><\/script>/)?.[1];
if (!src) fail('form.html has no local <script src="...cqt.js">');
let source;
try {
  source = readFileSync(join(repo, src), 'utf8');
  console.log(`ok    form.html loads ${src}`);
} catch {
  fail(`form.html loads ${src}, which does not exist`);
}

// 2. the global it calls is the one the script actually defines
const called = form.match(/const canonical = (\w+)\(/)?.[1];
if (!called) fail('form.html does not call a canonicalize function the expected way');

if (source && called) {
  // a browser gives it a window and the text encoders; nothing else
  const window = {};
  runInContext(source, createContext({ window, TextEncoder, TextDecoder }));
  if (typeof window[called] !== 'function') {
    fail(`form.html calls ${called}(), but ${src} defines no such global`
       + ` (it defines: ${Object.keys(window).join(', ') || 'nothing'})`);
  } else {
    console.log(`ok    ${src} defines window.${called}`);
    const { cases } = JSON.parse(readFileSync(join(repo, 'goldens', 'cqt2.17.json'), 'utf8'));
    const probe = cases.find((c) => c.id === 'identity-ascii') ?? cases[0];
    const got = new TextDecoder().decode(window[called](probe.input));
    if (got !== probe.output) {
      fail(`vector ${probe.id}: expected ${JSON.stringify(probe.output)}, got ${JSON.stringify(got)}`);
    } else {
      console.log(`ok    window.${called} passes vector ${probe.id}`);
    }
  }
}

if (!process.exitCode) console.log('\nthe interactive tool loads and runs');

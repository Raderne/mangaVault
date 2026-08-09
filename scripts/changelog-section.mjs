#!/usr/bin/env node
// Prints the CHANGELOG.md section for one version, to be used as a GitHub
// release body.
//
// The app parses that body back into colour-coded entries, so the release notes
// and the changelog can never drift: there is one source, sliced at release
// time. Everything above the first `## [x.y.z]` heading (the file's preamble
// and the format guide) and the link-reference footer are dropped.
//
//   node scripts/changelog-section.mjs 1.2.0 [path/to/CHANGELOG.md]
//
// Exits non-zero when the version has no section, which fails the release
// rather than publishing an APK with empty notes.

import { readFileSync } from 'node:fs';

const version = (process.argv[2] ?? '').replace(/^v/, '');
const path = process.argv[3] ?? 'CHANGELOG.md';

if (!version) {
  console.error('usage: changelog-section.mjs <version> [changelog path]');
  process.exit(2);
}

const lines = readFileSync(path, 'utf8').split(/\r?\n/);

// Matches `## [1.2.0] - 2026-08-09`, `## 1.2.0`, `## v1.2.0 – date`.
const heading = /^##\s+\[?v?([0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?)\]?/;

let start = -1;
let end = lines.length;

for (let i = 0; i < lines.length; i++) {
  const match = heading.exec(lines[i]);
  if (!match) continue;
  if (start === -1) {
    if (match[1] === version) start = i + 1;
  } else {
    end = i;
    break;
  }
}

if (start === -1) {
  console.error(`No "## [${version}]" section in ${path}.`);
  process.exit(1);
}

const body = lines
  .slice(start, end)
  // Drop the trailing link-reference block (`[1.0.0]: https://…`).
  .filter((line) => !/^\[[^\]]+\]:\s+https?:\/\//.test(line))
  .join('\n')
  .trim();

if (!body) {
  console.error(`The "${version}" section in ${path} is empty.`);
  process.exit(1);
}

process.stdout.write(`${body}\n`);

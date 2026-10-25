import { readFileSync, readdirSync } from 'node:fs';
import { join, resolve } from 'node:path';

const root = resolve(import.meta.dirname, '..');
const repo = resolve(root, '..');

function fail(message) {
  console.error(`Batch D structural check failed: ${message}`);
  process.exitCode = 1;
}

function sourceFiles(dir) {
  return readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
    const path = join(dir, entry.name);
    return entry.isDirectory() ? sourceFiles(path) : entry.name.endsWith('.ts') ? [path] : [];
  });
}

// Normalize CRLF -> LF before every structural assertion. On Windows the
// repository is checked out with CRLF until `.gitattributes` (eol=lf) is
// re-applied, and every regex below assumes `\n` line starts. Reading raw
// text made this script pass in CI and fail on the maintainer's machine.
function readNormalized(path) {
  return readFileSync(path, 'utf8').replace(/\r\n/g, '\n');
}

const runtimeSource = sourceFiles(join(root, 'src'))
  .map((path) => readNormalized(path))
  .join('\n');
const importRoute = readNormalized(join(root, 'src/routes/playlist-import.ts'));
const wrangler = readNormalized(join(root, 'wrangler.toml'));
const project = readNormalized(join(repo, 'ios/Runner.xcodeproj/project.pbxproj'));

if (/\b(?:CREATE|ALTER|DROP)\s+(?:TABLE|INDEX)\b/i.test(runtimeSource)) {
  fail('workers/src still contains request-time DDL');
}
if (!importRoute.includes('const allResults = await Promise.all(')) {
  fail('anonymous preview fan-out changed');
}
if (!importRoute.includes('No hard cap on playlist size.')) {
  fail('unbounded Phase 2 song behavior changed');
}
if (/MAX_(?:BODY|SONGS|PLAYLIST)|songs\.length\s*>|content-length/i.test(importRoute)) {
  fail('an excluded playlist-import bound was introduced');
}
if (!wrangler.includes('compatibility_date = "2026-07-29"')) {
  fail('compatibility date is not 2026-07-29');
}
if (!wrangler.includes('[observability.logs]') || !wrangler.includes('[observability.traces]')) {
  fail('sampled logs and traces are not configured');
}
const privacyFileRefs = [
  ...project.matchAll(
    /^\t\t([A-F0-9]{24}) \/\* PrivacyInfo\.xcprivacy \*\/ = \{isa = PBXFileReference;[^\n]*path = PrivacyInfo\.xcprivacy;/gm,
  ),
];
const privacyBuildFiles = [
  ...project.matchAll(
    /^\t\t([A-F0-9]{24}) \/\* PrivacyInfo\.xcprivacy in Resources \*\/ = \{isa = PBXBuildFile; fileRef = ([A-F0-9]{24}) \/\* PrivacyInfo\.xcprivacy \*\/; \};$/gm,
  ),
];
const privacyGroupEntries = [
  ...project.matchAll(/^\t\t\t\t([A-F0-9]{24}) \/\* PrivacyInfo\.xcprivacy \*\/,$/gm),
];
const runnerTarget = project.match(
  /\/\* Runner \*\/ = \{\n\t\t\tisa = PBXNativeTarget;[\s\S]*?buildPhases = \(([\s\S]*?)\);[\s\S]*?\n\t\t\tname = Runner;/,
);
const runnerResourcesPhase = runnerTarget?.[1].match(/([A-F0-9]{24}) \/\* Resources \*/);
const runnerResourcesBody = runnerResourcesPhase
  ? project.match(
      new RegExp(
        `${runnerResourcesPhase[1]} /\\* Resources \\*/ = \\{[\\s\\S]*?files = \\(([\\s\\S]*?)\\);`,
      ),
    )
  : null;
const runnerPrivacyResources = runnerResourcesBody
  ? [...runnerResourcesBody[1].matchAll(/([A-F0-9]{24}) \/\* PrivacyInfo\.xcprivacy in Resources \*/g)]
  : [];
const privacyFileId = privacyFileRefs[0]?.[1];
const privacyBuildId = privacyBuildFiles[0]?.[1];
if (
  privacyFileRefs.length !== 1 ||
  privacyBuildFiles.length !== 1 ||
  privacyBuildFiles[0][2] !== privacyFileId ||
  privacyGroupEntries.length !== 1 ||
  privacyGroupEntries[0][1] !== privacyFileId ||
  !runnerResourcesPhase ||
  runnerPrivacyResources.length !== 1 ||
  runnerPrivacyResources[0][1] !== privacyBuildId
) {
  fail('PrivacyInfo.xcprivacy is not referenced once in file, group, and Runner resources');
}
if (/console\.(?:log|error|warn)\([^\n]*(?:Authorization|ADMIN_PASSWORD|TINYAPI_KEY|password|token)/i.test(runtimeSource)) {
  fail('runtime logging may include credentials');
}

// Migration ordering: wrangler applies migrations in lexicographic filename
// order and records applied names in `d1_migrations`. Two files sharing a
// numeric prefix (0003_add_rbac.sql / 0003_scope_love_song_uniqueness.sql)
// only work by accident of the alphabet, and any future insert becomes a
// coin flip. Renaming an already-applied migration would make wrangler run it
// a second time on existing databases, so the historical pair is grandfathered
// in and only *new* duplicates are rejected.
const GRANDFATHERED_DUPLICATE_PREFIXES = new Set(['0003']);
const migrationFiles = readdirSync(join(root, 'migrations'))
  .filter((name) => name.endsWith('.sql'))
  .sort();
const prefixCounts = new Map();
for (const name of migrationFiles) {
  const match = name.match(/^(\d+)_/);
  if (!match) {
    fail(`migration "${name}" does not start with a numeric prefix`);
    continue;
  }
  const prefix = match[1];
  prefixCounts.set(prefix, (prefixCounts.get(prefix) ?? 0) + 1);
}
for (const [prefix, count] of prefixCounts) {
  if (count > 1 && !GRANDFATHERED_DUPLICATE_PREFIXES.has(prefix)) {
    fail(`migration prefix ${prefix} is used by ${count} files; prefixes must be unique`);
  }
}
const sortedPrefixes = [...prefixCounts.keys()].sort();
if (JSON.stringify(sortedPrefixes) !== JSON.stringify([...new Set(sortedPrefixes)].sort())) {
  fail('migration prefixes are not written in zero-padded sortable form');
}

if (!process.exitCode) console.log('Batch D structural checks passed.');

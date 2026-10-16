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

const runtimeSource = sourceFiles(join(root, 'src'))
  .map((path) => readFileSync(path, 'utf8'))
  .join('\n');
const importRoute = readFileSync(join(root, 'src/routes/playlist-import.ts'), 'utf8');
const wrangler = readFileSync(join(root, 'wrangler.toml'), 'utf8');
const project = readFileSync(join(repo, 'ios/Runner.xcodeproj/project.pbxproj'), 'utf8');

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

if (!process.exitCode) console.log('Batch D structural checks passed.');

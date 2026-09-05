import { readdir, readFile } from 'node:fs/promises';
import path from 'node:path';
import process from 'node:process';

const root = process.cwd();
const workflowDirectory = path.join(root, '.github', 'workflows');
const workflowNames = (await readdir(workflowDirectory))
  .filter((name) => name.endsWith('.yml') || name.endsWith('.yaml'))
  .sort();

const failures = [];

for (const workflowName of workflowNames) {
  const relativePath = path.posix.join('.github', 'workflows', workflowName);
  const contents = await readFile(
    path.join(workflowDirectory, workflowName),
    'utf8',
  );
  const lines = contents.split(/\r?\n/);

  if (!/^permissions:\s*\r?\n  contents: read\s*$/m.test(contents)) {
    failures.push(`${relativePath}: top-level permissions must be contents: read`);
  }

  if (/^(?:build-(?:android|ios|windows)|ci)\.ya?ml$/.test(workflowName)) {
    for (const requiredCommand of [
      'dart format --output=none --set-exit-if-changed lib test',
      'flutter analyze --fatal-infos --fatal-warnings',
      'flutter pub get --enforce-lockfile',
      'flutter test --exclude-tags live',
    ]) {
      if (!contents.includes(requiredCommand)) {
        failures.push(`${relativePath}: missing quality gate: ${requiredCommand}`);
      }
    }
  }

  if (/^(?:ci|deploy-workers)\.ya?ml$/.test(workflowName)) {
    const auditCommand = 'npm audit --package-lock-only --audit-level=high';
    if (!contents.includes(auditCommand)) {
      failures.push(`${relativePath}: missing locked dependency audit gate`);
    }
  }

  if (/^build-(?:android|ios|windows)\.yml$/.test(workflowName)) {
    if (!contents.includes('run: git merge-base --is-ancestor HEAD origin/main') ||
        !contents.includes('needs: verify-release-source')) {
      failures.push(`${relativePath}: build must verify source ancestry on main`);
    }
    if (!contents.includes('environment: release')) {
      failures.push(`${relativePath}: release environment is required`);
    }
  }

  if (workflowName === 'deploy-workers.yml' &&
      (!contents.includes("if: github.ref == 'refs/heads/main'") ||
       !contents.includes('environment: production'))) {
    failures.push(`${relativePath}: production deployment requires main and production environment`);
  }

  if (workflowName === 'ci.yml') {
    for (const command of [
      'flutter build apk --debug --no-pub',
      'flutter build ios --release --no-codesign --no-pub',
      'flutter build windows --release --no-pub',
    ]) {
      if (!contents.includes(command)) {
        failures.push(`${relativePath}: missing native PR build: ${command}`);
      }
    }
  }

  if (
    workflowName === 'deploy-workers.yml' &&
    !/^  deploy:\s*\r?\n    needs: validate\s*$/m.test(contents)
  ) {
    failures.push(`${relativePath}: deployment must depend on the validation job`);
  }

  let currentJob = '';
  let runBlockIndent = -1;
  for (let index = 0; index < lines.length; index += 1) {
    const line = lines[index];
    const jobMatch = line.match(/^  ([a-zA-Z0-9_-]+):\s*$/);
    if (jobMatch) currentJob = jobMatch[1];

    const indentation = line.length - line.trimStart().length;
    if (runBlockIndent >= 0 && line.trim() && indentation <= runBlockIndent) {
      runBlockIndent = -1;
    }
    if (/^\s+run:\s*[|>]\s*$/.test(line)) runBlockIndent = indentation;
    if (
      line.includes('${{ secrets.') &&
      (runBlockIndent >= 0 || /^\s+run:/.test(line))
    ) {
      failures.push(
        `${relativePath}:${index + 1}: pass secrets through step env, never expression-interpolate them into shell code`,
      );
    }

    const usesMatch = line.match(/^\s*-?\s*uses:\s*([^\s#]+)(?:\s+#\s*(.+))?\s*$/);
    if (usesMatch) {
      const [, action, versionComment] = usesMatch;
      if (!/^[^@\s]+@[0-9a-f]{40}$/.test(action)) {
        failures.push(
          `${relativePath}:${index + 1}: action must use a full 40-character commit SHA`,
        );
      }
      if (!/^v\d+\.\d+\.\d+(?:\s|$)/.test(versionComment?.trim() ?? '')) {
        failures.push(
          `${relativePath}:${index + 1}: pinned action must retain an exact semver comment`,
        );
      }

      if (action.startsWith('actions/checkout@')) {
        const stepIndent = indentation;
        let stepEnd = index + 1;
        while (stepEnd < lines.length) {
          const next = lines[stepEnd];
          const nextIndent = next.length - next.trimStart().length;
          if (next.trim() && nextIndent <= stepIndent && /^\s*-\s/.test(next)) break;
          stepEnd += 1;
        }
        const checkoutStep = lines.slice(index, stepEnd).join('\n');
        if (!/^\s+persist-credentials:\s*false\s*$/m.test(checkoutStep)) {
          failures.push(
            `${relativePath}:${index + 1}: checkout must set persist-credentials: false`,
          );
        }
      }
    }

    if (/^\s+contents:\s*write\s*$/.test(line) && !currentJob.startsWith('release-')) {
      failures.push(
        `${relativePath}:${index + 1}: contents: write is restricted to release-* jobs`,
      );
    }
    if (/^\s+contents:\s*write\s*$/.test(line) && currentJob.startsWith('release-')) {
      const tagGuard = new RegExp(
        `^  ${currentJob}:\\s*\\r?\\n    if: startsWith\\(github\\.ref, 'refs/tags/v'\\)\\s*$`,
        'm',
      );
      if (!tagGuard.test(contents)) {
        failures.push(
          `${relativePath}:${index + 1}: release write permission requires a v* tag guard`,
        );
      }
    }

    if (/\bnpx\s+(?!--no-install\b)/.test(line)) {
      failures.push(
        `${relativePath}:${index + 1}: npx must use --no-install to prevent implicit downloads`,
      );
    }
  }
}

if (failures.length > 0) {
  console.error(failures.join('\n'));
  process.exitCode = 1;
} else {
  console.log(`Workflow security policy passed for ${workflowNames.length} files.`);
}

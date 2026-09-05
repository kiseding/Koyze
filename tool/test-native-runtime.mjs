import { readFileSync } from 'node:fs';
import { fileURLToPath, pathToFileURL } from 'node:url';
import path from 'node:path';
import { spawnSync } from 'node:child_process';

const configPath = path.resolve('.dart_tool/package_config.json');
const config = JSON.parse(readFileSync(configPath, 'utf8'));
const plugin = config.packages.find((entry) => entry.name === 'flutter_js');
if (!plugin) throw new Error('Run flutter pub get before native runtime tests');
const root = fileURLToPath(new URL(plugin.rootUri, pathToFileURL(configPath)));
const env = { ...process.env };
const pathKey = Object.keys(env).find((key) => key.toLowerCase() === 'path') ?? 'PATH';
env[pathKey] = path.join(root, 'windows/shared') + path.delimiter + (env[pathKey] ?? '');
env.LIBQUICKJSC_TEST_PATH = path.join(root, 'linux/shared/libquickjs_c_bridge_plugin.so');
const result = spawnSync(
  process.platform === 'win32' ? 'flutter.bat' : 'flutter',
  ['test', 'tool/native_runtime_network_test.dart', '--no-pub', '--reporter', 'expanded'],
  { env, stdio: 'inherit', shell: process.platform === 'win32', timeout: 120_000 },
);
if (result.error) throw result.error;
process.exitCode = result.status ?? 1;

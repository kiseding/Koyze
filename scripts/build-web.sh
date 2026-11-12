#!/usr/bin/env bash
# 构建 Koyze Web 版。
#
# 设计目标：主仓库 lib/ 一行不改。所有 Web 差异都在临时构建副本里施加，
# 现有 Android / iOS / Windows / macOS / Linux / HarmonyOS 六个平台完全不受
# 影响，也不需要为 Web 维护一套并行 UI。
#
#   ./scripts/build-web.sh            # 构建并把产物放进 webapp/public/
#   FLUTTER_BIN=/path/to/flutter ./scripts/build-web.sh
#
# 产物随后由 webapp/ 的 Node 服务托管（同端口提供 API + 静态界面），
# 也可以直接 docker compose up --build 打进镜像。

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="${KOYZE_WEB_WORKDIR:-$ROOT/build/web-workspace}"
PATCH="$ROOT/scripts/web-patch"
OUT="$ROOT/webapp/public"

FLUTTER="${FLUTTER_BIN:-flutter}"
if ! command -v "$FLUTTER" >/dev/null 2>&1; then
  echo "error: flutter not found. Set FLUTTER_BIN=/path/to/flutter/bin/flutter" >&2
  exit 1
fi

echo "[1/6] syncing build copy: $WORK"
# 之前是 rm -rf 重建，沙箱/CI 里对上千文件的批量删除会被拦。
# 改成增量同步：先把副本里上游已删除的条目剪掉（通常 0 个），再整体覆盖。
mkdir -p "$WORK"
python3 - "$ROOT" "$WORK" <<'PY'
import os, shutil, sys
root, work = sys.argv[1], sys.argv[2]
# 只同步构建需要的目录，跳过 build/、.git/ 和各平台原生工程。
items = ['lib', 'assets', 'pubspec.yaml', 'pubspec.lock',
         'analysis_options.yaml', 'l10n.yaml', '.metadata', 'third_party']

def prune_and_copy(relative):
    src = os.path.join(root, relative)
    dst = os.path.join(work, relative)
    if not os.path.exists(src):
        return 0
    if os.path.isfile(src):
        os.makedirs(os.path.dirname(dst) or work, exist_ok=True)
        shutil.copy2(src, dst)
        return 0
    removed = 0
    if os.path.isdir(dst):
        for base, dirs, files in os.walk(dst):
            inner = os.path.relpath(base, dst)
            for name in files:
                if not os.path.exists(os.path.join(src, inner, name)):
                    os.remove(os.path.join(base, name))
                    removed += 1
            for name in list(dirs):
                if not os.path.isdir(os.path.join(src, inner, name)):
                    shutil.rmtree(os.path.join(base, name))
                    removed += 1
    shutil.copytree(src, dst, dirs_exist_ok=True)
    return removed

total = sum(prune_and_copy(item) for item in items)
print(f'  synced {len(items)} item(s), pruned {total} stale file(s)')
PY

echo "[2/6] applying web patches inside the copy"
# .metadata 里的 ohos 是自定义平台，官方 SDK 的 migrate 解析会抛
# "Bad state: No element"，副本里移除该条目即可。
python3 - "$WORK/.metadata" <<'PY'
import re, sys
p = sys.argv[1]
t = open(p, encoding='utf-8').read()
t = re.sub(r'\n    - platform: ohos\n(?:      [^\n]*\n)+', '\n', t)
open(p, 'w', encoding='utf-8').write(t)
PY

# dart:io 在 dart2js 下有类型 stub，编译能过，但 Platform._operatingSystem
# 在运行时会抛 Unsupported operation，启动链必崩。
# 把 import 收敛到 io_shim：保留 dart:io 全部类型，只换成 Web 安全的 Platform。
# 48 个文件的逻辑一行不改，原生构建也完全不受影响（只改副本）。
python3 - "$WORK/lib" <<'PY'
import os, sys
root = sys.argv[1]
count = 0
for base, _, files in os.walk(root):
    for name in files:
        if not name.endswith('.dart'):
            continue
        p = os.path.join(base, name)
        t = open(p, encoding='utf-8').read()
        if "import 'dart:io';" not in t and 'import "dart:io";' not in t:
            continue
        t = t.replace("import 'dart:io';",
                      "import 'package:koyze/core/web/io_shim.dart';")
        t = t.replace('import "dart:io";',
                      "import 'package:koyze/core/web/io_shim.dart';")
        open(p, 'w', encoding='utf-8').write(t)
        count += 1
print('  rewrote', count, 'dart:io imports -> io_shim')
PY

# 覆盖/新增 Web 专用实现
cp -r "$PATCH/lib/." "$WORK/lib/"
[ -f "$PATCH/pubspec_web.yaml" ] && cp "$PATCH/pubspec_web.yaml" "$WORK/pubspec.yaml"

# Web 版多一个直接依赖：`archive`。dart:io 的 zlib 在 dart2js 下是空壳，
# QRC 歌词解压要用 archive 的纯 Dart inflate。它本来就已经是 image 包的
# 传递依赖（lock 里锁着 4.5.2），这里只是提升为直接依赖，不会引入新版本。
python3 - "$WORK/pubspec.yaml" <<'PY'
import sys
p = sys.argv[1]
t = open(p, encoding='utf-8').read()
if '\n  archive:' not in t:
    anchor = '\n  # 工具\n'
    if anchor not in t:
        raise SystemExit('archive dependency anchor not found')
    t = t.replace(anchor, '\n  # Web: QRC 歌词的 zlib 解压（dart:io 的 zlib 在 dart2js 下不可用）\n'
                          '  archive: ^4.5.2\n' + anchor, 1)
    open(p, 'w', encoding='utf-8').write(t)
    print('  added archive dependency for web build')
PY

# 剩下三处必须动到主源码：链接导入改走服务端、首启登录页隐藏侧栏。
# 用锚点替换而不是整文件覆盖，上游改动会让构建直接失败而不是静默跑旧逻辑。
echo "  applying surgical edits"
python3 "$PATCH/edits.py" "$WORK"

echo "[3/6] generating web platform skeleton"
(cd "$WORK" && "$FLUTTER" create --platforms=web --project-name koyze --org com.koyze . >/dev/null)
# create 会写默认 index.html / manifest，用仓库版本覆盖
[ -d "$PATCH/web" ] && cp -r "$PATCH/web/." "$WORK/web/"
# `flutter create` 塞的是默认 Flutter logo，用仓库里的正式图标重绘整套。
python3 "$PATCH/make_web_icons.py" "$WORK/web"
echo "[4/6] flutter pub get"
(cd "$WORK" && "$FLUTTER" pub get)

echo "[5/6] flutter build web"
(cd "$WORK" && "$FLUTTER" build web --release --no-tree-shake-icons -t lib/main_web.dart)

echo "[6/6] copying artifacts to $OUT"
rm -rf "$OUT"
mkdir -p "$OUT"
cp -r "$WORK/build/web/." "$OUT/"
echo "done. Web bundle is in $OUT"
echo "next: cd webapp && docker compose up --build   (or: node server/index.js)"

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 文档死链检查（`.github/scripts/check_md_links.sh`）的回归测试。
///
/// ## 为什么这条检查需要测试
///
/// 它本身是"检查别人的检查器"：判断逻辑一旦误判，红的是整个 Quality gate，
/// 而报错信息看起来像是文档写错了，很容易被当成"改个链接就好"。
///
/// 5.1.0 发版后就真的踩了一次：CHANGELOG 描述反调试指纹时写了
/// `` `['toString']()` ``，旧实现用 `grep -oP '\]\(\K[^)]+'` 直接扫全文，
/// 把代码片段里的 `](` 当成了链接，于是 CI 报「引用的文件不存在：
/// `['toString'](`」——一个根本不存在的路径。文档本身没有任何问题。
///
/// 所以这里钉住三件事：
/// 1. 真实死链必须报出来（检查器不能变成永远绿的空转）
/// 2. 代码块 / 行内代码里的 `](` 不能被当成链接（那次误报的形状）
/// 3. 仓库里现存的文档必须全部通过（现状守卫）
///
/// 这些用例会真的调用 bash 脚本，所以带 `skip` 兜底：Windows 以外的精简 CI
/// 环境如果没有 bash/awk，跳过而不是失败——检查本身在 Linux runner 上跑得到。
void main() {
  // 相对路径在临时目录里作为 workingDirectory 时会失效，钉成绝对路径。
  // 测试进程的 cwd 就是仓库根目录（flutter test 的约定），先取绝对路径。
  final script = File(
    '.github/scripts/check_md_links.sh',
  ).absolute.path;

  /// 在临时目录里造一个最小仓库（脚本用 `git rev-parse` 定位根目录，
  /// 失败时回退到 pwd，所以不需要真的 git init）。
  Directory makeRepo(Map<String, String> files) {
    final tmp = Directory.systemTemp.createTempSync('mdlinks_');
    for (final entry in files.entries) {
      final file = File('${tmp.path}/${entry.key}');
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(entry.value);
    }
    return tmp;
  }

  /// 用 `bash script <files...>` 跑检查，返回 (退出码, stderr)。
  (int, String) runCheck(Directory root, List<String> paths) {
    final result = Process.runSync(
      'bash',
      [script, ...paths],
      workingDirectory: root.path,
    );
    return (result.exitCode, '${result.stderr}');
  }

  // 先在当前仓库根目录跑一次，确认 bash 可用；不可用就整组跳过。
  bool bashAvailable;
  try {
    bashAvailable =
        Process.runSync('bash', ['-c', 'command -v awk']).exitCode == 0;
  } on ProcessException {
    bashAvailable = false;
  }

  group('check_md_links.sh', () {
    test('真实死链会被报出来', () {
      final root = makeRepo({
        'docs/a.md': '[坏链接](./missing.md)\n',
        'docs/missing-note.txt': '', // 无关文件，确保不是空目录
      });
      addTearDown(() => root.deleteSync(recursive: true));

      final (code, stderr) = runCheck(root, ['docs/a.md']);
      expect(code, 1, reason: '死链必须让检查失败');
      expect(stderr, contains('missing.md'));
    }, skip: !bashAvailable);

    test('行内代码里的 ]( 不算链接（5.1.0 的真实误报形状）', () {
      final root = makeRepo({
        'docs/b.md':
            // 反引号包住的代码片段，里面的 ]( 不是 Markdown 链接
            "过滤掉 `` `['toString'](` `` 这种指纹。\n"
            '还有 `utils.crypto.md5(x)` 也不算。\n'
            '[真链接](./real.md)\n',
        'docs/real.md': '# ok\n',
      });
      addTearDown(() => root.deleteSync(recursive: true));

      final (code, stderr) = runCheck(root, ['docs/b.md']);
      expect(code, 0, reason: '代码片段导致误报会让整个 Quality gate 变红，stderr=$stderr');
      expect(stderr, isEmpty);
    }, skip: !bashAvailable);

    test('围栏代码块里的 ]( 不算链接', () {
      final root = makeRepo({
        'docs/c.md': '示例：\n\n```dart\n// 这里写 [x](not-a-link.md) 只是示意\n```\n',
      });
      addTearDown(() => root.deleteSync(recursive: true));

      final (code, _) = runCheck(root, ['docs/c.md']);
      expect(code, 0);
    }, skip: !bashAvailable);

    test('链接相对于所在文件目录，不是仓库根目录', () {
      final root = makeRepo({
        'docs/adr/0001-x.md': '[上级](../../workers/README.md)\n',
        'workers/README.md': '# workers\n',
      });
      addTearDown(() => root.deleteSync(recursive: true));

      // 从仓库根看 ../../workers 是错的，从 docs/adr/ 看才是对的
      final (code, stderr) = runCheck(root, ['docs/adr/0001-x.md']);
      expect(code, 0, reason: '相对路径基准算错会把所有 ADR 都判成死链，stderr=$stderr');
    }, skip: !bashAvailable);

    test('third_party 不在校验范围内', () {
      final root = makeRepo({
        'third_party/live_activities/CHANGELOG.md': '[截图](./missing.png)\n',
      });
      addTearDown(() => root.deleteSync(recursive: true));

      final (code, _) = runCheck(root, [
        'third_party/live_activities/CHANGELOG.md',
      ]);
      expect(code, 0, reason: 'vendored 上游的坏链接不该阻塞本仓库');
    }, skip: !bashAvailable);

    test('仓库现有文档全部通过', () {
      final result = Process.runSync('bash', [script]);
      expect(
        result.exitCode,
        0,
        reason: '现存文档有死链：\n${result.stderr}\n'
            '本地可直接跑 `bash $script` 复现。',
      );
    }, skip: !bashAvailable);
  });
}

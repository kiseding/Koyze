import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 发版校验和流水线（`.github/scripts/write_platform_checksums.sh` +
/// `.github/workflows/release-checksums.yml`）的回归测试。
///
/// ## 为什么这个也需要测试
///
/// 5.1.1 发版后 Release 里的 `SHA256SUMS.txt` **只包含两个 .hap 的哈希**，
/// 另外 7 个产物（3 个 APK、3 个桌面包、1 个 IPA）一个都没覆盖，而且路径写的
/// 是构建机上的相对目录（`build/harmonyos-release/...`）。用户照着它校验
/// 必然对不上——提供了校验文件却校验不过，比不提供更误导人。
///
/// 根因是「每个 workflow 各自生成一份同名 SHA256SUMS.txt」这个设计：
/// 7 个平台并行上传同一个 Release，谁最后传谁的内容会留下，先到的那份被
/// 覆盖。而实际上只有鸿蒙那一个 workflow 会写这个文件，所以结果就是只有
/// HAP 的哈希。
///
/// 现在的设计是：
///   - 各平台 → `SHA256SUMS.<platform>.txt`（互不覆盖）
///   - 汇总   → `release-checksums.yml` 取齐所有分片，拼成唯一的
///     `SHA256SUMS.txt`
///
/// 这组测试钉住三件事：
/// 1. 分片内容只写 basename，且 `sha256sum -c` 能直接校验通过
/// 2. 分片会排除文本文件（否则 SHA256SUMS.txt 会把自己的哈希也算进去）
/// 3. 每个会上传产物的 workflow 都调用了分片脚本（少一个就会有产物漏掉）
void main() {
  final script = File(
    '.github/scripts/write_platform_checksums.sh',
  ).absolute.path;

  bool toolAvailable;
  try {
    toolAvailable =
        Process.runSync('bash', ['-c', 'command -v awk']).exitCode == 0;
  } on ProcessException {
    toolAvailable = false;
  }

  /// 造一个含若干二进制/文本文件的临时产物目录。
  Directory makeDist(Map<String, String> files) {
    final tmp = Directory.systemTemp.createTempSync('cksums_');
    for (final e in files.entries) {
      File('${tmp.path}/${e.key}')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(e.value);
    }
    return tmp;
  }

  group('write_platform_checksums.sh', () {
    test('只写文件名，且 sha256sum -c 能校验通过', () {
      final dist = makeDist({
        'Koyze-1.0-arm64.apk': 'apk-content',
        'Koyze-1.0-x86_64.apk': 'apk-content-2',
      });
      addTearDown(() => dist.deleteSync(recursive: true));

      final gen = Process.runSync('bash', [script, dist.path, 'android']);
      expect(gen.exitCode, 0, reason: '生成分片失败：${gen.stderr}');

      final shard = File('${dist.path}/SHA256SUMS.android.txt');
      expect(shard.existsSync(), isTrue);
      final text = shard.readAsStringSync();

      // 关键：不能出现构建机上的绝对路径或父目录，只能是 basename
      expect(text, isNot(contains(dist.path)));
      expect(text, isNot(contains('/')));
      expect(text, contains('*Koyze-1.0-arm64.apk'));
      expect(text, contains('*Koyze-1.0-x86_64.apk'));

      // 真正的判据：拿它去校验必须全过
      final check = Process.runSync('sha256sum', ['-c', 'SHA256SUMS.android.txt'],
          workingDirectory: dist.path);
      expect(
        check.exitCode,
        0,
        reason: '用户照这份文件校验必须能过：\n${check.stdout}${check.stderr}',
      );
    }, skip: !toolAvailable);

    test('不把自己和文本文件算进哈希', () {
      final dist = makeDist({
        'a.apk': 'x',
        'notes.txt': 'hello',
        'SHA256SUMS.android.txt': 'stale',
      });
      addTearDown(() => dist.deleteSync(recursive: true));

      final gen = Process.runSync('bash', [script, dist.path, 'android']);
      expect(gen.exitCode, 0, reason: '${gen.stderr}');

      final text = File('${dist.path}/SHA256SUMS.android.txt').readAsStringSync();
      expect(text.trim().split('\n').length, 1,
          reason: '只应有一行（a.apk），实际：\n$text');
      expect(text, contains('*a.apk'));
      expect(text, isNot(contains('notes.txt')));
      expect(text, isNot(contains('SHA256SUMS')));
    }, skip: !toolAvailable);

    test('产物目录为空时失败，而不是产出空分片', () {
      final dist = makeDist({});
      addTearDown(() => dist.deleteSync(recursive: true));

      final gen = Process.runSync('bash', [script, dist.path, 'android']);
      expect(gen.exitCode, isNot(0),
          reason: '空分片会让汇总阶段静默漏掉整个平台');

      // 关键断言：**不能**留下空的正式分片。空文件被汇总 workflow 当成
      // 「该平台已完成」，整个平台的产物就会静默缺席。
      //
      // 这条在最初实现上是失败的：那时先 `: > "$out"` 再算，失败时靠
      // `rm -f` 清理，而某些环境（本机有 safe-delete 包装）会拒绝删除
      // 含盘符的路径，rm 静默失败 → 空分片残留。现在改成写 .tmp.<pid>
      // 全部成功后才 mv，所以正式文件名根本不会出现。
      final shard = File('${dist.path}/SHA256SUMS.android.txt');
      expect(
        shard.existsSync(),
        isFalse,
        reason: '空分片不能出现在正式文件名上——汇总 workflow 会把它当成'
            '「该平台已完成」，整个平台的产物就此静默缺席。',
      );
    }, skip: !toolAvailable);

    test('平台标识不合法时拒绝执行', () {
      final dist = makeDist({'a.apk': 'x'});
      addTearDown(() => dist.deleteSync(recursive: true));

      // 大写、下划线、空格都可能拼出奇怪文件名，一律拒绝
      for (final bad in ['Android', 'and_roid', 'android ios']) {
        final gen = Process.runSync('bash', [script, dist.path, bad]);
        expect(gen.exitCode, isNot(0), reason: '应拒绝平台标识 "$bad"');
      }
    }, skip: !toolAvailable);
  });

  group('发版工作流覆盖检查', () {
    // 这条是静态检查，不依赖 bash。
    //
    // 判断依据很直接：一个 workflow 只要用 action-gh-release 往 Release 传
    // 产物，就必须也调 write_platform_checksums.sh，否则它的产物在
    // SHA256SUMS.txt 里会缺席——正是 5.1.1 那个 bug 的形状。
    //
    // Build Web image 是唯一例外：它产出 Docker 镜像，不传 Release 文件。
    test('每个上传 Release 产物的 workflow 都生成校验和分片', () {
      final dir = Directory('.github/workflows');
      expect(dir.existsSync(), isTrue);

      // 只看**真的执行了**脚本的行，不能在注释里提一句就算数。
      //
      // 这个坑我踩过：最初用的是 `src.contains('write_platform_checksums.sh')`，
      // 而我在每个 workflow 里都加了「各平台只出自己那份…原因见
      // .github/scripts/write_platform_checksums.sh」这样的说明注释。
      // 结果把真正的 run 行删掉之后测试依然是绿的——检查形同虚设。
      // 所以现在跳过 YAML 注释行，只认 `bash ... write_platform_checksums.sh`。
      bool reallyInvokes(String src) {
        final codeLines = src
            .split('\n')
            .where((l) => !l.trimLeft().startsWith('#'));
        return codeLines.any(
          (l) => RegExp(r'bash\s+\S*write_platform_checksums\.sh\b').hasMatch(l),
        );
      }

      final offenders = <String>[];
      for (final f in dir.listSync().whereType<File>()) {
        if (!f.path.endsWith('.yml') && !f.path.endsWith('.yaml')) continue;
        final src = f.readAsStringSync();
        final uploadsRelease = src.contains('softprops/action-gh-release');
        if (!uploadsRelease) continue;
        if (!reallyInvokes(src)) {
          offenders.add(f.uri.pathSegments.last);
        }
      }

      expect(
        offenders,
        isEmpty,
        reason: '这些 workflow 往 Release 传了产物却没生成 SHA256SUMS 分片，'
            '它们的产物会在汇总时缺席（5.1.1 的 HAP-only 就是这么来的）：'
            '${offenders.join(", ")}',
      );
    });

    test('汇总 workflow 覆盖了所有会上传产物的 workflow 名称', () {
      final checksums =
          File('.github/workflows/release-checksums.yml').readAsStringSync();

      // 提取 workflow_run.workflows 里列出的名字
      final declared = RegExp(r'^\s+-\s+(.+)$', multiLine: true)
          .allMatches(
            checksums.substring(
              checksums.indexOf('workflows:'),
              checksums.indexOf('types:'),
            ),
          )
          .map((m) => m.group(1)!.trim())
          .toSet();

      final uploading = <String>{};
      for (final f in Directory('.github/workflows').listSync().whereType<File>()) {
        if (!f.path.endsWith('.yml')) continue;
        final src = f.readAsStringSync();
        if (!src.contains('softprops/action-gh-release')) continue;
        final nameMatch = RegExp(r'^name:\s*(.+)$', multiLine: true).firstMatch(src);
        if (nameMatch != null) uploading.add(nameMatch.group(1)!.trim());
      }

      // 汇总 workflow 自己不该出现在列表里
      uploading.remove('Assemble release checksums');

      final missing = uploading.difference(declared);
      expect(
        missing,
        isEmpty,
        reason: '这些会上传产物的 workflow 不在 workflow_run 列表里，'
            '它们的完成事件不会触发汇总，分片可能永远等不齐：'
            '${missing.join(", ")}',
      );
    });
  });
}

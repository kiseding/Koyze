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
/// 这组测试钉住这几件事：
/// 1. 分片内容只写 basename，且 `sha256sum -c` 能直接校验通过
/// 2. 分片会排除文本文件（否则 SHA256SUMS.txt 会把自己的哈希也算进去）
/// 3. 每个会上传产物的 workflow 都调用了分片脚本（少一个就会有产物漏掉）
/// 4. 分片确实出现在 action-gh-release 的 files: 列表里（生成了≠传上去了）
/// 5. 汇总 workflow 等待的平台名与各平台传入的标识一致（否则永远等不齐）
/// 6. 汇总 workflow 的 workflow_run 列表覆盖所有上传产物的 workflow
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
        'Koyze-1.0-arm64.apk': 'x',
        'notes.txt': 'hello',
        'SHA256SUMS.android.txt': 'stale',
      });
      addTearDown(() => dist.deleteSync(recursive: true));

      final gen = Process.runSync('bash', [script, dist.path, 'android']);
      expect(gen.exitCode, 0, reason: '${gen.stderr}');

      final text = File('${dist.path}/SHA256SUMS.android.txt').readAsStringSync();
      expect(text.trim().split('\n').length, 1,
          reason: '只应有一行（Koyze-1.0-arm64.apk），实际：\n$text');
      expect(text, contains('*Koyze-1.0-arm64.apk'));
      expect(text, isNot(contains('notes.txt')));
      expect(text, isNot(contains('SHA256SUMS')));
    }, skip: !toolAvailable);

    // 5.2.0 第二次汇总失败的原因：分片里混进了构建残留。
    //
    // `flutter build macos/ios/windows` 会在产物目录的同一层留下
    // `pod_inputs.fingerprint`、`framework_public_headers.fingerprint`、
    // `info.plist`、`app.so`。它们被算进分片后，汇总阶段拿分片去
    // `sha256sum -c`（分片里的每个名字都必须在 Release 上真实存在）就报
    // `No such file or directory`，整份 SHA256SUMS.txt 发不出去。
    //
    // 修法是正向白名单：只给 `Koyze-*` 算哈希。这条测试同时钉住改名/新增
    // 产物时的行为——不叫 Koyze- 的东西一律不进分片。
    test('产物目录里的构建残留不进分片', () {
      final dist = makeDist({
        'Koyze-1.0-arm64.apk': 'x',
        'pod_inputs.fingerprint': 'junk',
        'framework_public_headers.fingerprint': 'junk',
        'info.plist': 'junk',
        'app.so': 'junk',
      });
      addTearDown(() => dist.deleteSync(recursive: true));

      final gen = Process.runSync('bash', [script, dist.path, 'android']);
      expect(gen.exitCode, 0, reason: '${gen.stderr}');

      final text = File('${dist.path}/SHA256SUMS.android.txt').readAsStringSync();
      expect(text.trim().split('\n').length, 1,
          reason: '只应有一行，构建残留必须被排除，实际：\n$text');
      for (final junk in [
        'pod_inputs.fingerprint',
        'framework_public_headers.fingerprint',
        'info.plist',
        'app.so',
      ]) {
        expect(text, isNot(contains(junk)),
            reason: '$junk 不是产物，进分片会让汇总阶段报 No such file');
      }
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
      // 用真实的产物名：目录里只有构建残留时脚本会以「没有产物」退出，
      // 那是另一种失败，会让这条断言变成假阳性
      final dist = makeDist({'Koyze-1.0-arm64.apk': 'x'});
      addTearDown(() => dist.deleteSync(recursive: true));

      // 大写、下划线、空格都可能拼出奇怪文件名，一律拒绝；
      // 空串也要拒绝，否则会产出 `SHA256SUMS..txt` 这种没人认得出的分片名
      for (final bad in ['Android', 'and_roid', 'android ios', '']) {
        final gen = Process.runSync('bash', [script, dist.path, bad]);
        expect(gen.exitCode, isNot(0), reason: '应拒绝平台标识 "$bad"');
      }
    }, skip: !toolAvailable);

    // 这条是 5.2.0 发版时踩出来的：iOS job 在 macOS 上跑这套测试，
    // `case "$platform" in *[!a-z-]*)` 在那里**放过了 "Android"**（期望非 0，
    // 实际 0），于是整个 iOS 构建卡在测试步骤，IPA 没能发出去。
    //
    // 原因是 bash 3.2（macOS 自带 /bin/bash）解析括号表达式时把结尾的 `-`
    // 当成区间起点，`-`(0x2D) 到 `]`(0x5D) 之间整段 ASCII 都成了「合法字符」，
    // 大写字母正好在里面。开发机上是 bash 4/5，会正确拒绝，所以功能测试在
    // 本地永远绿——只能再加一条静态检查，把「别用 case 字符区间校验平台名」
    // 钉在源码上，免得以后又写回去。
    test('平台标识校验不依赖 case 的字符区间（bash 3.2 会放行大写）', () {
      final src = File('.github/scripts/write_platform_checksums.sh')
          .readAsStringSync();
      final code = src
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('#'))
          .join('\n');

      expect(
        RegExp(r'case\s+"?\$(platform|2)"?\s+in').hasMatch(code),
        isFalse,
        reason: 'bash 3.2 解析 `[!a-z-]` 会把结尾的 - 当成区间起点，'
            '大写字母也能通过。用 LC_ALL=C + 显式白名单的正则代替。',
      );
      expect(
        code,
        contains('LC_ALL=C'),
        reason: '平台名校验要固定在 C locale 下，'
            '否则 [a-z] 的语义随 runner 的 locale 漂移',
      );
    }, skip: !toolAvailable);

    // 这个脚本要在 ubuntu / macOS / Windows(Git Bash) 三种 runner 上跑。
    // macOS 上是 BSD 版 sort/find，且没装 coreutils，所以 GNU 专属的
    // `sort -z` / `find -print0 | sort -z` 一类写法会直接让 macOS 发版挂掉。
    // 我曾为了「免疫文件名带换行」加上 -z，发现这个问题后又撤回——换成
    // 一条静态检查把它钉死，免得以后又有人图省事加回来。
    test('脚本不用 GNU 专属的 sort/find 选项（macOS 会挂）', () {
      final src = File('.github/scripts/write_platform_checksums.sh')
          .readAsStringSync();
      final code = src
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('#'))
          .join('\n');

      // sort -z / --zero-terminated、find -print0 都不在 BSD sort 的保证范围
      expect(
        RegExp(r'sort\s+(-[a-zA-Z]*z|--zero-terminated)').hasMatch(code),
        isFalse,
        reason: 'sort -z 在 macOS runner 的 BSD sort 上不可靠，'
            '用它会直接让 macOS 发版失败',
      );
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

    // 第二条静态检查，钉住「分片真的会被传上去」这件事。
    //
    // 上面那条只检查「workflow 会不会生成分片」，但生成了不等于传上去了。
    // 4 个桌面/移动平台的 action-gh-release 原本写的是单个文件：
    //
    //   files: build/ios/Koyze-Apple-ID-Sideload.ipa
    //
    // 分片虽然被生成在 build/ios/ 下，却不在上传列表里，于是 Release 上
    // 永远没有 SHA256SUMS.ios.txt。汇总 workflow 的等待循环会一直空转到
    // 25 分钟超时，报「缺少平台分片」——看上去像 GitHub 慢，实际是配置
    // 少了一行。Android 和鸿蒙用目录通配（dir/*）碰巧带上了分片，掩盖了
    // 这个问题，所以更要单独钉一条。
    test('往 Release 传产物的 workflow 把分片也一起上传', () {
      final offenders = <String>[];

      for (final f in Directory('.github/workflows').listSync().whereType<File>()) {
        if (!f.path.endsWith('.yml') && !f.path.endsWith('.yaml')) continue;
        final src = f.readAsStringSync();
        if (!src.contains('softprops/action-gh-release')) continue;

        // 取出 action-gh-release 那一步的 files: 区块
        final idx = src.indexOf('softprops/action-gh-release');
        var body = src.substring(idx);
        final filesIdx = body.indexOf('files:');
        if (filesIdx < 0) {
          offenders.add('${f.uri.pathSegments.last}（没有 files:）');
          continue;
        }
        body = body.substring(filesIdx);
        // files: 的值到下一个同级 key 或文件结尾为止
        final endIdx = body.indexOf(RegExp(r'\n\s{0,8}[a-z_]+:', multiLine: true));
        final filesBlock = endIdx > 0 ? body.substring(0, endIdx) : body;

        // 目录通配（path/* 或 path/**）会自动带上分片，视为通过。
        //
        // 不能只匹配 `files:` 后面第一个非空白串：鸿蒙写的是
        // `build/harmonyos-${{ env.HAP_BUILD_MODE }}/*`，中间有空格，
        // 用 \S* 会在空格处截断、把带通配的那行漏掉。
        final usesGlob = filesBlock.split('\n').any((l) => l.contains('*'));
        final listsShard = filesBlock.contains('SHA256SUMS.');
        if (!usesGlob && !listsShard) {
          offenders.add(f.uri.pathSegments.last);
        }
      }

      expect(
        offenders,
        isEmpty,
        reason: '这些 workflow 生成了分片却没上传到 Release，汇总 workflow '
            '会一直等不到它们、25 分钟后超时失败：${offenders.join(", ")}',
      );
    });

    // 第三条静态检查：两边对「平台」的命名必须完全一致。
    //
    // 各平台调脚本时传的平台标识（android / harmonyos / ...）决定分片文件名；
    // 汇总 workflow 的 expected 列表决定它在等哪些文件。任何一边改了名字而
    // 另一边没跟上，等待循环就会空转到超时。这种错配完全不会在本地暴露，
    // 只有发版时才炸，因此值得钉死。
    test('等待的平台名与各 workflow 实际生成的分片名一致', () {
      final checksums =
          File('.github/workflows/release-checksums.yml').readAsStringSync();

      final expectedLine = RegExp(r'expected="([^"]+)"').firstMatch(checksums);
      expect(expectedLine, isNotNull, reason: '汇总 workflow 里找不到 expected= 列表');
      final expected = expectedLine!.group(1)!.split(RegExp(r'\s+')).toSet();

      // 从各 workflow 抓 `write_platform_checksums.sh <path> <platform>` 的
      // 最后一个参数。跳过 YAML 注释行，避免注释里举例的平台名混进来。
      const tagPattern = r'write_platform_checksums\.sh\s+(\S+|\$out)\s+([a-z][a-z-]*)';
      final actual = <String>{};
      for (final f in Directory('.github/workflows').listSync().whereType<File>()) {
        if (!f.path.endsWith('.yml') && !f.path.endsWith('.yaml')) continue;
        for (final line in f.readAsLinesSync()) {
          if (line.trimLeft().startsWith('#')) continue;
          final m = RegExp(tagPattern).firstMatch(line);
          if (m != null) actual.add(m.group(2)!);
        }
      }

      expect(actual, isNotEmpty, reason: '没有从任何 workflow 抓到平台标识');
      expect(
        actual.difference(expected),
        isEmpty,
        reason: '这些分片会被生成，但汇总 workflow 不在等它们（永远等不齐）：'
            '${actual.difference(expected).join(", ")}',
      );
      expect(
        expected.difference(actual),
        isEmpty,
        reason: '汇总 workflow 在等这些分片，但没有任何 workflow 会生成它们'
            '（必然超时）：${expected.difference(actual).join(", ")}',
      );
    });

    // 覆盖完整性检查：`sha256sum -c` 只校验分片里**列了**的文件，没列的
    // 一概不管。假如鸿蒙先完成就触发了汇总，此时 Release 上只有 HAP，两个
    // HAP 的哈希与分片完全一致，"校验通过"了，但据此发布的 SHA256SUMS.txt
    // 只有 2 行——5.1.1 那个 bug 换个方式重演。所以汇总里有一道
    // "分片列出的文件集合 == Release 上实际的文件集合" 的比对。
    test('汇总时会检查分片是否覆盖 Release 上的全部产物', () {
      final src = File('.github/workflows/release-checksums.yml').readAsStringSync();
      expect(
        src.contains(r'[ "$listed" != "$present" ]'),
        isTrue,
        reason: '缺少「分片 vs 实际产物」的集合比对，'
            '部分平台先完成时可能发布一份只覆盖部分产物的校验文件',
      );
      // 文件名可能含空格，不能用 awk '{print $2}' 取第二列当文件名。
      // 注意 `awk '{print $1}'` 是**正确**的（sha256sum 输出第一列就是哈希），
      // 所以只禁 $2 这一种写法，并且跳过注释行——注释里正是在解释为什么不用它。
      final code = src
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('#'))
          .join('\n');
      expect(
        code.contains(r"awk '{print $2}'"),
        isFalse,
        reason: '取文件名不能用 awk 按空白切分，含空格的名字会被截断',
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

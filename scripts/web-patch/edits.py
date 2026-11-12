#!/usr/bin/env python3
"""对构建副本做「外科式」修改。

为什么不是整文件覆盖：像 `independent_side_rail.dart`（1200 行）和
`custom_source_service.dart`（700 行）这种文件，整份复制进 web-patch/ 之后
上游一改就静默偏离，Web 版会悄悄跑旧逻辑。这里改为按锚点做字符串替换，
每个锚点必须**恰好命中一次**，上游改动了锚点会立刻构建失败，而不是生成一个
行为不对的包。

用法：
    python3 edits.py <workdir>            # 施加修改
    python3 edits.py <workdir> --dry-run  # 只校验锚点
"""

import sys
import pathlib

# (文件, 说明, [(原文, 替换后), ...])
EDITS = [
    (
        'lib/features/custom_source/domain/custom_source_service.dart',
        '链接导入改走同源服务端（浏览器没有 HttpClient）',
        [
            (
                "import '../../../core/logging/app_log.dart';",
                "import '../../../core/web/web_source_import.dart';\n"
                "import '../../../core/logging/app_log.dart';",
            ),
            (
                "      final importUri = normalizeCustomSourceScriptUrl(parsedUri);\n"
                "      return await () async {\n"
                "        final response = await _importSandbox.request(importUri, const {\n"
                "          'method': 'GET',\n"
                "          'timeout': 15000,\n"
                "          'httpsOnly': true,\n"
                "        }, cancellation: cancel);\n"
                "        final script = await withSourceResponseLease(response, (owned) async {\n"
                "          if (owned.statusCode != 200) return null;\n"
                "          return utf8.decode(owned.bytes, allowMalformed: false);\n"
                "        });\n",
                "      final importUri = normalizeCustomSourceScriptUrl(parsedUri);\n"
                "      return await () async {\n"
                "        // Web: 浏览器里没有 dart:io HttpClient（构造即抛 Unsupported\n"
                "        // operation），链接导入一律交给同源服务端代取，顺带绕开 CORS。\n"
                "        final String? script;\n"
                "        if (isWebBuild) {\n"
                "          script = await fetchSourceScriptViaServer(importUri);\n"
                "        } else {\n"
                "          final response = await _importSandbox.request(importUri, const {\n"
                "            'method': 'GET',\n"
                "            'timeout': 15000,\n"
                "            'httpsOnly': true,\n"
                "          }, cancellation: cancel);\n"
                "          script = await withSourceResponseLease<String?>(\n"
                "              response, (owned) async {\n"
                "            if (owned.statusCode != 200) return null;\n"
                "            return utf8.decode(owned.bytes, allowMalformed: false);\n"
                "          });\n"
                "        }\n",
            ),
        ],
    ),
    (
        'lib/features/custom_source/domain/custom_source_file_import.dart',
        'Web 上跳过 blob: 路径读取，直接用 bytes',
        [
            (
                "import '../../../core/io/bounded_input.dart';",
                "import '../../../core/web/web_source_import.dart';\n"
                "import '../../../core/io/bounded_input.dart';",
            ),
            (
                "  final path = file.path;\n"
                "  Object? pathError;\n"
                "  if (path != null && path.isNotEmpty) {",
                "  final path = file.path;\n"
                "  Object? pathError;\n"
                "  // Web: file_picker 给的 path 是 blob: URL，dart:io 的 File.openRead()\n"
                "  // 在浏览器里会从 StreamController 的 zone 抛错，绕过下面的 catch，\n"
                "  // 整个导入流程直接中断（表现为「点了导入什么也没发生」）。\n"
                "  // 浏览器里 withData 已经给到 bytes，不需要走路径。\n"
                "  if (!isWebBuild && path != null && path.isNotEmpty) {",
            ),
        ],
    ),
    (
        'lib/features/source_check/domain/media_probe.dart',
        '音源检测的媒体探测改走浏览器 Range 请求',
        [
            (
                "import '../../../core/network/source_media_transport.dart';",
                "import '../../../core/web/web_source_import.dart';\n"
                "import '../../../core/network/source_media_transport.dart';",
            ),
            (
                "    final stopwatch = Stopwatch()..start();\n"
                "    final responseHeaders = <String, String>{};\n"
                "    try {\n"
                "      final bytes = await _transport\n",
                "    final stopwatch = Stopwatch()..start();\n"
                "    final responseHeaders = <String, String>{};\n"
                "    // Web: SourceMediaTransport 用的是 dart:io 的 pinned HttpClient，\n"
                "    // 浏览器里构造就失败，检测会一律 0/N。改由浏览器直接发 Range 请求\n"
                "    // （同源 /api/stream，Range 与防盗链头都由服务端转发）。\n"
                "    if (isWebBuild) {\n"
                "      final probed = await probeMediaViaServer(\n"
                "        url,\n"
                "        maxBytes: sampleBytes,\n"
                "        timeout: timeout,\n"
                "      );\n"
                "      stopwatch.stop();\n"
                "      if (probed.error != null) {\n"
                "        return MediaProbeResult.failed(\n"
                "          probed.error!,\n"
                "          latencyMs: stopwatch.elapsedMilliseconds,\n"
                "          timedOut: probed.timedOut,\n"
                "        );\n"
                "      }\n"
                "      return classify(\n"
                "        url: url,\n"
                "        bytes: probed.bytes,\n"
                "        responseHeaders: probed.headers,\n"
                "        latencyMs: stopwatch.elapsedMilliseconds,\n"
                "      );\n"
                "    }\n"
                "    try {\n"
                "      final bytes = await _transport\n",
            ),
        ],
    ),
    (
        'lib/core/music_source/platform/qrc_decoder.dart',
        'QRC 歌词的 zlib 解压改用 archive 的纯 Dart inflate',
        [
            (
                "import 'dart:typed_data';\n",
                "import 'dart:typed_data';\n"
                "\n"
                "import 'package:archive/archive.dart';\n",
            ),
            (
                "Uint8List _inflate(List<int> data) {\n"
                "  try {\n"
                "    return Uint8List.fromList(zlib.decode(data));\n"
                "  } catch (_) {\n"
                "    // The decrypted stream may carry zero-byte block padding; retry after\n"
                "    // trimming it and fall back to raw deflate for robustness.\n"
                "  }\n"
                "  var end = data.length;\n"
                "  while (end > 0 && data[end - 1] == 0) {\n"
                "    end--;\n"
                "  }\n"
                "  final trimmed = Uint8List.fromList(data.sublist(0, end));\n"
                "  try {\n"
                "    return Uint8List.fromList(zlib.decode(trimmed));\n"
                "  } catch (_) {\n"
                "    return Uint8List.fromList(ZLibCodec(raw: true).decode(trimmed));\n"
                "  }\n"
                "}\n",
                "// Web: `dart:io` 的 zlib / ZLibCodec 在 dart2js 下只是类型 stub，\n"
                "// 一调用就抛 `UnsupportedError: _newZLibInflateFilter`。`archive`\n"
                "// 用条件导入做了平台分流（Web 走纯 Dart inflate），这里直接用它。\n"
                "// 与原生版严格同序：先 zlib 头；失败后去掉尾部零填充再试 zlib；\n"
                "// 最后才试裸 deflate。顺序错了会把可解的数据判成坏数据。\n"
                "Uint8List _inflate(List<int> data) {\n"
                "  const decoder = ZLibDecoderWeb();\n"
                "  try {\n"
                "    return decoder.decodeBytes(data, verify: false);\n"
                "  } catch (_) {}\n"
                "  var end = data.length;\n"
                "  while (end > 0 && data[end - 1] == 0) {\n"
                "    end--;\n"
                "  }\n"
                "  final trimmed = data.sublist(0, end);\n"
                "  try {\n"
                "    return decoder.decodeBytes(trimmed, verify: false);\n"
                "  } catch (_) {}\n"
                "  return decoder.decodeBytes(trimmed, verify: false, raw: true);\n"
                "}\n",
            ),
        ],
    ),
    (
        'lib/core/audio/playback_command_coordinator.dart',
        'Web 上 setAudioSource 的时长不可信，改用播放器实际时长',
        [
            (
                "import 'dart:async';\n",
                "import 'dart:async';\n"
                "import 'package:koyze/core/web/web_source_import.dart';\n",
            ),
            (
                "          final duration = await _player\n"
                "              .setAudioSource(\n"
                "                desiredSource.source!,\n"
                "                initialPosition: desiredSource.position,\n"
                "              )\n"
                "              .timeout(_sourceLoadTimeout);\n"
                "          if (duration != null && duration < minimumResolvedAudioDuration) {\n"
                "            throw ResolvedAudioTooShortException(duration);\n"
                "          }\n",
                "          final duration = await _player\n"
                "              .setAudioSource(\n"
                "                desiredSource.source!,\n"
                "                initialPosition: desiredSource.position,\n"
                "              )\n"
                "              .timeout(_sourceLoadTimeout);\n"
                "          // Web: just_audio_web 的 setAudioSource 会在 <audio> 元数据\n"
                "          // 就绪前返回，拿到的是按已缓冲字节估出来的假时长（同一首\n"
                "          // 歌每次都得到相同的偏小值），于是每首都被下面这道\n"
                "          // 「至少 15 秒」的试听片段保护拦掉。这里改为等播放器\n"
                "          // 真正报出时长再判；等不到就放行，让浏览器自己播。\n"
                "          var effectiveDuration = duration;\n"
                "          if (isWebBuild) {\n"
                "            if (effectiveDuration == null ||\n"
                "                effectiveDuration < minimumResolvedAudioDuration) {\n"
                "              // 注意不能只等「非 null」：流里已经有那个偏小的估算值，\n"
                "              // firstWhere 会立刻返回它。要等一个明确够长的值，\n"
                "              // 或者等到元数据加载完（processingState != loading）。\n"
                "              try {\n"
                "                effectiveDuration = await _player.durationStream\n"
                "                    .firstWhere(\n"
                "                      (value) =>\n"
                "                          value != null &&\n"
                "                          value >= minimumResolvedAudioDuration,\n"
                "                    )\n"
                "                    .timeout(const Duration(seconds: 8));\n"
                "              } on TimeoutException {\n"
                "                effectiveDuration = _player.duration;\n"
                "              }\n"
                "            }\n"
                "            // 浏览器没给出可信时长（null/零/仍然偏小）时放行：\n"
                "            // 这一层是拦试听片段的，不该把能正常播放的歌一起拦掉。\n"
                "            if (effectiveDuration != null &&\n"
                "                effectiveDuration < minimumResolvedAudioDuration) {\n"
                "              effectiveDuration = null;\n"
                "            }\n"
                "          }\n"
                "          if (effectiveDuration != null &&\n"
                "              effectiveDuration < minimumResolvedAudioDuration) {\n"
                "            throw ResolvedAudioTooShortException(effectiveDuration);\n"
                "          }\n",
            ),
        ],
    ),
    (
        'lib/features/sync/presentation/startup_cloud_login_prompt.dart',
        '把门控状态广播出去，让侧栏让位',
        [
            (
                "import '../../cloud/presentation/cloud_provider.dart';",
                "import '../../../core/web/startup_gate_state.dart';\n"
                "import '../../cloud/presentation/cloud_provider.dart';",
            ),
            (
                "    setState(() => _showLogin = !seen && !session.loggedIn);",
                "    final showLogin = !seen && !session.loggedIn;\n"
                "    ref.read(startupLoginGateActiveProvider.notifier).state = showLogin;\n"
                "    setState(() => _showLogin = showLogin);",
            ),
            (
                "    if (!mounted) return;\n"
                "    setState(() => _showLogin = false);",
                "    if (!mounted) return;\n"
                "    ref.read(startupLoginGateActiveProvider.notifier).state = false;\n"
                "    setState(() => _showLogin = false);",
            ),
        ],
    ),
    (
        'lib/core/widgets/artwork_image.dart',
        '封面字节改走同源代理（浏览器没有 dart:io HttpClient）',
        [
            (
                "import 'package:flutter/material.dart';\n",
                "import 'package:flutter/material.dart';\n"
                "import 'package:koyze/core/web/artwork_web.dart';\n",
            ),
            (
                "  ) async {\n"
                "    final client = createClient();\n"
                "    try {\n"
                "      return await _loadWithClient(\n",
                "  ) async {\n"
                "    // Web: dart:io 的 HttpClient() 在浏览器里一构造就抛\n"
                "    // \"Unsupported operation\"，而且这句原本在 try 之外，异常会直接\n"
                "    // 冒到 ImageProvider 的 catch 里被静默吞掉 —— 所有封面都退化成\n"
                "    // 占位图标，控制台一条日志都没有。改走同源 /api/stream：服务端\n"
                "    // 代发请求并注入 UA / Referer，既绕 CORS 也满足防盗链\n"
                "    // （浏览器里 Referer 是 forbidden header，根本设不上）。\n"
                "    if (isWebBuild) {\n"
                "      return loadArtworkBytesViaBrowser(\n"
                "        uri,\n"
                "        maximumBytes: maximumBytes,\n"
                "        timeout: timeout,\n"
                "        onProgress: onProgress,\n"
                "      );\n"
                "    }\n"
                "    final client = createClient();\n"
                "    try {\n"
                "      return await _loadWithClient(\n",
            ),
        ],
    ),
    (
        'lib/core/widgets/artwork_disk_cache.dart',
        'Web 上没有文件系统：缓存退回纯内存，先落内存再尝试写盘',
        [
            (
                "import '../network/outbound_url.dart';\n",
                "import 'package:koyze/core/web/artwork_web.dart';\n"
                "import '../network/outbound_url.dart';\n",
            ),
            (
                "  Future<void> _init() async {\n"
                "    final base =\n",
                "  Future<void> _init() async {\n"
                "    // Web: path_provider 没有浏览器实现，\n"
                "    // getApplicationSupportDirectory() 会抛 UnimplementedError，\n"
                "    // 而 bytesForUrl() 一进来就 await ensureReady()，于是**每一张**\n"
                "    // 封面都在这里失败。_root 保持 null，退回纯内存缓存。\n"
                "    if (isWebBuild) {\n"
                "      _root = null;\n"
                "      return;\n"
                "    }\n"
                "    final base =\n",
            ),
            (
                "  Future<File?> put(String url, Uint8List bytes) async {\n"
                "    await ensureReady();\n"
                "    final root = _root;\n"
                "    if (root == null) return null;\n"
                "    final key = _keyFor(url);\n",
                "  Future<File?> put(String url, Uint8List bytes) async {\n"
                "    await ensureReady();\n"
                "    final key = _keyFor(url);\n"
                "    // 先落内存再尝试写盘：Web 上 _root 恒为 null，原来那句\n"
                "    // `if (root == null) return null;` 会让内存缓存也一起跳过，\n"
                "    // 列表每帧都要重新下载同一张封面。\n"
                "    _memory.set(key, bytes);\n"
                "    final root = _root;\n"
                "    if (root == null) return null;\n",
            ),
        ],
    ),
    (
        'lib/core/theme/cover_palette.dart',
        '封面取色在 Web 上直接走同源代理',
        [
            (
                "import '../widgets/artwork_disk_cache.dart';\n",
                "import 'package:koyze/core/web/artwork_web.dart';\n"
                "import '../widgets/artwork_disk_cache.dart';\n",
            ),
            (
                "    final cached = await ArtworkDiskCache.instance.bytesForUrl(url);\n"
                "    if (cached != null && cached.isNotEmpty) return cached;\n"
                "    final file = await ArtworkDiskCache.instance.ensureLocalFile(url);\n",
                "    final cached = await ArtworkDiskCache.instance.bytesForUrl(url);\n"
                "    if (cached != null && cached.isNotEmpty) return cached;\n"
                "    // Web: 没有磁盘，ensureLocalFile() 永远返回 null，取色会一直失败，\n"
                "    // 主题色只剩用户手选那一档。这里直接走同源代理取一次字节。\n"
                "    if (isWebBuild) {\n"
                "      try {\n"
                "        final bytes = await loadArtworkBytesViaBrowser(\n"
                "          Uri.parse(url),\n"
                "          maximumBytes: 8 * 1024 * 1024,\n"
                "          timeout: const Duration(seconds: 12),\n"
                "        );\n"
                "        await ArtworkDiskCache.instance.put(url, bytes);\n"
                "        return bytes;\n"
                "      } catch (_) {\n"
                "        return null;\n"
                "      }\n"
                "    }\n"
                "    final file = await ArtworkDiskCache.instance.ensureLocalFile(url);\n",
            ),
        ],
    ),
    (
        'lib/core/widgets/koyze_sheet.dart',
        '弹窗封面改用 ArtworkImage（Image.network 在 Web 上过不了 CORS/防盗链）',
        [
            (
                "import '../motion/motion_tokens.dart';\n",
                "import 'artwork_image.dart';\n"
                "import '../motion/motion_tokens.dart';\n",
            ),
            (
                "                  child: hasCover\n"
                "                      ? Image.network(\n"
                "                          artwork!,\n"
                "                          fit: BoxFit.cover,\n",
                "                  child: hasCover\n"
                "                      ? ArtworkImage(\n"
                "                          artwork!,\n"
                "                          fit: BoxFit.cover,\n",
            ),
        ],
    ),
    (
        'lib/features/lyric/presentation/lyric_share_card.dart',
        '分享卡封面改用 ArtworkImage（Image.network 在 Web 上过不了 CORS/防盗链）',
        [
            (
                "import '../../../core/theme/app_colors.dart';\n",
                "import '../../../core/theme/app_colors.dart';\n"
                "import '../../../core/widgets/artwork_image.dart';\n",
            ),
            (
                "            : Image.network(\n"
                "                source,\n"
                "                fit: BoxFit.cover,\n"
                "                gaplessPlayback: true,\n",
                "            : ArtworkImage(\n"
                "                source,\n"
                "                fit: BoxFit.cover,\n",
            ),
        ],
    ),
    (
        'lib/features/home/presentation/independent_side_rail.dart',
        '首启登录页不显示侧栏',
        [
            (
                "import '../../../core/widgets/root_shell_layout.dart';",
                "import '../../../core/web/startup_gate_state.dart';\n"
                "import '../../../core/widgets/root_shell_layout.dart';",
            ),
            (
                "  Widget build(BuildContext context) {\n"
                "    final media = MediaQuery.of(context);",
                "  Widget build(BuildContext context) {\n"
                "    // 首启登录门控占满整屏时不留侧栏：此时还没进主界面，\n"
                "    // 导航点击无处可去，留着只会把登录页挤到右边。\n"
                "    if (ref.watch(startupLoginGateActiveProvider)) return widget.child;\n"
                "    final media = MediaQuery.of(context);",
            ),
        ],
    ),
]


def main() -> int:
    if len(sys.argv) < 2:
        print('usage: edits.py <workdir> [--dry-run]', file=sys.stderr)
        return 2
    root = pathlib.Path(sys.argv[1])
    dry_run = '--dry-run' in sys.argv[2:]

    failed = 0
    for relative, description, pairs in EDITS:
        target = root / relative
        if not target.exists():
            print(f'  MISSING {relative}', file=sys.stderr)
            failed += 1
            continue
        # 仓库里部分文件是 CRLF；统一成 LF 再匹配，副本写成 LF 更省事。
        text = target.read_text(encoding='utf-8').replace('\r\n', '\n')
        original = text

        ok = True
        for old, new in pairs:
            hits = text.count(old)
            if hits != 1:
                snippet = old.strip().splitlines()[0][:70]
                print(
                    f'  ANCHOR {hits} hit(s) in {relative}: "{snippet}"',
                    file=sys.stderr,
                )
                ok = False
                break
            text = text.replace(old, new, 1)

        if not ok:
            failed += 1
            continue

        if not dry_run and text != original:
            target.write_text(text, encoding='utf-8')
        print(f'  patched {relative}  <- {description}')

    if failed:
        print(f'{failed} file(s) failed; aborting build', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())

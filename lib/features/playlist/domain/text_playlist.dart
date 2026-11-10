/// 通用文本歌单解析。
///
/// 歌单文件本来就是一份「曲目清单」，不是音频。各家播放器写出来的清单
/// 都是纯文本，只是语法不同：
///
/// - M3U / M3U8：`#EXTINF` 逐行标注，跨平台最通用（foobar2000、VLC、车机）；
/// - PLS：INI 风格，Winamp 时代流媒体与本地清单都在用；
/// - XSPF：XML 标准，VLC / foobar2000 支持，元数据最完整；
/// - WPL：Windows Media Player 的原生清单；
/// - ASX：Windows Media 的流清单，老播放器仍在用；
/// - TXT：一行一首的纯文本，人眼可读，也是各家迁移工具导出的兜底格式。
///
/// 这些格式解析完都落到 [M3uDocument]，后面的「对本地曲库」逻辑只有一份。
library;

import 'package:xml/xml.dart';

import 'm3u_playlist.dart';

/// 支持读取的文本歌单扩展名。UI 的说明文案与文件筛选都以此为准。
const List<String> kTextPlaylistExtensions = <String>[
  'm3u',
  'm3u8',
  'pls',
  'xspf',
  'wpl',
  'asx',
  'wax',
  'txt',
];

/// 常见音频扩展名。选到这些文件时直接给出「这是音频，不是歌单」的提示，
/// 而不是把二进制当文本硬解析出一堆乱码条目。
const Set<String> kAudioFileExtensions = <String>{
  'mp3',
  'flac',
  'm4a',
  'aac',
  'wav',
  'wave',
  'ogg',
  'oga',
  'opus',
  'wma',
  'ape',
  'aiff',
  'aif',
  'alac',
  'dsf',
  'dff',
  'mka',
  'mp4',
  'm4v',
  'mov',
  'mkv',
  'avi',
  'webm',
  'ts',
};

enum PlaylistTextFormat {
  m3u('M3U'),
  m3u8('M3U8'),
  pls('PLS'),
  xspf('XSPF'),
  wpl('WPL'),
  asx('ASX'),
  txt('TXT'),
  unknown('');

  const PlaylistTextFormat(this.label);

  /// 展示给用户看的格式名（也用于提示文案）。
  final String label;
}

/// 读取/解析失败的原因。UI 按枚举给出本地化文案，不在 domain 层写死中文。
enum PlaylistReadFailure { audioFile, binaryFile, empty, malformed }

class PlaylistFileException implements Exception {
  const PlaylistFileException(this.failure);

  final PlaylistReadFailure failure;
}

class TextPlaylist {
  const TextPlaylist({required this.format, required this.document});

  final PlaylistTextFormat format;
  final M3uDocument document;
}

/// 按扩展名优先、内容兜底判断格式。
///
/// 只看扩展名不够：有些导出工具会把 PLS 写成 `.txt`，XSPF 也可能被存成
/// `.xml`。内容特征足够强时以内容为准，避免把能读的文件判成未知格式。
PlaylistTextFormat detectPlaylistFormat(String fileName, String content) {
  final extension = playlistExtensionOf(fileName);
  final byExtension = switch (extension) {
    'm3u' => PlaylistTextFormat.m3u,
    'm3u8' => PlaylistTextFormat.m3u8,
    'pls' => PlaylistTextFormat.pls,
    'xspf' => PlaylistTextFormat.xspf,
    'wpl' => PlaylistTextFormat.wpl,
    'asx' || 'wax' => PlaylistTextFormat.asx,
    'txt' => PlaylistTextFormat.txt,
    _ => PlaylistTextFormat.unknown,
  };

  final sniffed = _sniffFormat(content);
  if (byExtension == PlaylistTextFormat.unknown) return sniffed;
  // 扩展名说是 TXT、内容却明确是 PLS/XSPF 的，按内容走。
  if (byExtension == PlaylistTextFormat.txt &&
      sniffed != PlaylistTextFormat.txt &&
      sniffed != PlaylistTextFormat.unknown) {
    return sniffed;
  }
  return byExtension;
}

/// 扩展名小写，不含点。取不到时返回空串。
String playlistExtensionOf(String fileName) {
  final slash = fileName.lastIndexOf(RegExp(r'[/\\]'));
  final name = slash >= 0 ? fileName.substring(slash + 1) : fileName;
  final dot = name.lastIndexOf('.');
  if (dot <= 0 || dot == name.length - 1) return '';
  return name.substring(dot + 1).toLowerCase();
}

PlaylistTextFormat _sniffFormat(String content) {
  final head = content.trimLeft().toLowerCase();
  if (head.isEmpty) return PlaylistTextFormat.unknown;
  if (head.startsWith('#extm3u') || head.contains('#extinf:')) {
    return PlaylistTextFormat.m3u;
  }
  if (head.contains('[playlist]')) return PlaylistTextFormat.pls;
  if (head.startsWith('<')) {
    if (head.contains('<playlist') &&
        (head.contains('xspf') || head.contains('<tracklist'))) {
      return PlaylistTextFormat.xspf;
    }
    if (head.contains('<wpl')) return PlaylistTextFormat.wpl;
    if (head.contains('<asx') || head.contains('<entry')) {
      return PlaylistTextFormat.asx;
    }
  }
  return PlaylistTextFormat.txt;
}

/// 解析文本歌单。
///
/// 音频文件、二进制文件与空清单分别抛出 [PlaylistFileException]，让 UI 能
/// 给出「这是音频文件」这类准确提示，而不是一句笼统的「导入失败」。
TextPlaylist parseTextPlaylist({
  required String fileName,
  required String content,
  String? baseDirectory,
}) {
  final extension = playlistExtensionOf(fileName);
  if (kAudioFileExtensions.contains(extension)) {
    throw const PlaylistFileException(PlaylistReadFailure.audioFile);
  }
  if (_looksBinary(content)) {
    throw const PlaylistFileException(PlaylistReadFailure.binaryFile);
  }

  final format = detectPlaylistFormat(fileName, content);
  final document = switch (format) {
    PlaylistTextFormat.m3u ||
    PlaylistTextFormat.m3u8 => parseM3u(content, baseDirectory: baseDirectory),
    PlaylistTextFormat.pls => parsePls(content, baseDirectory: baseDirectory),
    PlaylistTextFormat.xspf => parseXspf(content, baseDirectory: baseDirectory),
    PlaylistTextFormat.wpl => parseWpl(content, baseDirectory: baseDirectory),
    PlaylistTextFormat.asx => parseAsx(content, baseDirectory: baseDirectory),
    PlaylistTextFormat.txt || PlaylistTextFormat.unknown => parseTxt(
      content,
      baseDirectory: baseDirectory,
    ),
  };
  if (document.entries.isEmpty) {
    throw const PlaylistFileException(PlaylistReadFailure.empty);
  }
  return TextPlaylist(format: format, document: document);
}

/// 二进制嗅探。
///
/// 音频、压缩包一旦被当文本读，会得到一整屏乱码条目；这里靠控制字符占比
/// 与常见音频文件头提前拦住。文本歌单里允许换行/制表符，其他 C0 控制符
/// 基本不会出现。
bool _looksBinary(String content) {
  if (content.isEmpty) return false;
  if (content.startsWith('ID3') ||
      content.startsWith('fLaC') ||
      content.startsWith('OggS') ||
      content.startsWith('RIFF')) {
    return true;
  }
  final sample = content.length > 1024 ? content.substring(0, 1024) : content;
  var control = 0;
  for (final unit in sample.codeUnits) {
    if (unit == 0) return true;
    if (unit < 9 || (unit > 13 && unit < 32)) control++;
  }
  return control > sample.length * 0.1;
}

// ==================== PLS ====================

/// `[playlist]` + `FileN=/TitleN=/LengthN=` 的 INI 风格清单。
///
/// 键名大小写不敏感；序号不连续也能读（有的播放器删歌后不重排编号）。
M3uDocument parsePls(String content, {String? baseDirectory}) {
  final locations = <int, String>{};
  final titles = <int, String>{};
  final artists = <int, String>{};
  final durations = <int, Duration>{};
  var dropped = 0;

  for (final rawLine in content.split(RegExp(r'\r\n|\r|\n'))) {
    final line = rawLine.trim();
    if (line.isEmpty || line.startsWith(';') || line.startsWith('#')) continue;
    if (line.startsWith('[')) continue;
    final separator = line.indexOf('=');
    if (separator <= 0) continue;

    final key = line.substring(0, separator).trim().toLowerCase();
    final value = line.substring(separator + 1).trim();
    final match = RegExp(r'^([a-z]+)(\d+)$').firstMatch(key);
    if (match == null) continue;

    final index = int.tryParse(match.group(2)!);
    if (index == null) continue;
    switch (match.group(1)!) {
      case 'file':
        if (value.isEmpty) {
          dropped++;
        } else {
          locations[index] = resolvePlaylistLocation(value, baseDirectory);
        }
      case 'title':
        final split = splitArtistTitle(value);
        artists[index] = split.$1 ?? '';
        titles[index] = split.$2;
      case 'length':
        final seconds = int.tryParse(value);
        if (seconds != null && seconds > 0) {
          durations[index] = Duration(seconds: seconds);
        }
    }
  }

  final indexes = locations.keys.toList()..sort();
  return M3uDocument(
    entries: [
      for (final index in indexes)
        M3uEntry(
          location: locations[index]!,
          title: titles[index],
          artist: artists[index],
          duration: durations[index],
        ),
    ],
    droppedLines: dropped,
  );
}

// ==================== XSPF ====================

/// `trackList/track` 里的 `location` / `title` / `creator` / `duration`。
///
/// XSPF 的 `duration` 单位是毫秒，和 M3U 的秒不同，这里直接换算好。
M3uDocument parseXspf(String content, {String? baseDirectory}) {
  final root = _parseXml(content);
  final entries = <M3uEntry>[];
  var dropped = 0;

  for (final track in _descendants(root, 'track')) {
    final location = _childText(track, 'location');
    if (location == null || location.trim().isEmpty) {
      dropped++;
      continue;
    }
    final milliseconds = int.tryParse(_childText(track, 'duration') ?? '');
    entries.add(
      M3uEntry(
        location: _normalizeLocation(location, baseDirectory),
        title: _childText(track, 'title'),
        artist: _childText(track, 'creator'),
        duration: milliseconds != null && milliseconds > 0
            ? Duration(milliseconds: milliseconds)
            : null,
      ),
    );
  }

  return M3uDocument(entries: entries, droppedLines: dropped);
}

// ==================== WPL ====================

/// Windows Media Player 的 `<media src="..."/>` 清单。
///
/// WPL 不记录曲名，只记路径；这里从文件名里推断标题与歌手，至少让
/// 「文件挪过位置」的清单还能靠歌名匹配上。
M3uDocument parseWpl(String content, {String? baseDirectory}) {
  final root = _parseXml(content);
  final entries = <M3uEntry>[];
  var dropped = 0;

  for (final media in _descendants(root, 'media')) {
    final source = _attribute(media, 'src')?.trim();
    if (source == null || source.isEmpty) {
      dropped++;
      continue;
    }
    final location = _normalizeLocation(source, baseDirectory);
    final meta = _trackFromFileName(location);
    entries.add(M3uEntry(location: location, title: meta.$2, artist: meta.$1));
  }

  return M3uDocument(entries: entries, droppedLines: dropped);
}

// ==================== ASX ====================

/// `<ENTRY><REF HREF="..."/></ENTRY>`；`DURATION` 是 `H:MM:SS` 或 `MM:SS`。
M3uDocument parseAsx(String content, {String? baseDirectory}) {
  final root = _parseXml(content);
  final entries = <M3uEntry>[];
  var dropped = 0;

  final blocks = _descendants(root, 'entry').toList(growable: false);
  for (final block in blocks) {
    final refs = _descendants(block, 'ref').toList(growable: false);
    if (refs.isEmpty) {
      dropped++;
      continue;
    }
    final title = _childText(block, 'title');
    final author = _childText(block, 'author');
    // ASX 的时长写在 `DURATION value="0:04:05"` 属性上，个别导出器
    // 也会写成元素文本，两种都认。
    final durationNode = _firstChild(block, 'duration');
    final duration = _asxDuration(
      _attribute(durationNode, 'value') ?? durationNode?.innerText.trim(),
    );
    for (final ref in refs) {
      final href = _attribute(ref, 'href')?.trim();
      if (href == null || href.isEmpty) {
        dropped++;
        continue;
      }
      final location = _normalizeLocation(href, baseDirectory);
      final meta = _trackFromFileName(location);
      entries.add(
        M3uEntry(
          location: location,
          title: title ?? meta.$2,
          artist: author ?? meta.$1,
          duration: duration,
        ),
      );
    }
  }

  // 少数清单把 REF 直接写在 ASX 根下，没有 ENTRY 包裹。
  if (blocks.isEmpty) {
    for (final ref in _descendants(root, 'ref')) {
      final href = _attribute(ref, 'href')?.trim();
      if (href == null || href.isEmpty) {
        dropped++;
        continue;
      }
      final location = _normalizeLocation(href, baseDirectory);
      final meta = _trackFromFileName(location);
      entries.add(
        M3uEntry(location: location, title: meta.$2, artist: meta.$1),
      );
    }
  }

  return M3uDocument(entries: entries, droppedLines: dropped);
}

Duration? _asxDuration(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  final parts = value
      .trim()
      .split(':')
      .map((part) => int.tryParse(part.trim()))
      .toList(growable: false);
  if (parts.any((part) => part == null)) return null;
  final numbers = parts.cast<int>();
  return switch (numbers.length) {
    3 => Duration(hours: numbers[0], minutes: numbers[1], seconds: numbers[2]),
    2 => Duration(minutes: numbers[0], seconds: numbers[1]),
    _ => null,
  };
}

// ==================== TXT ====================

/// 一行一首的纯文本清单。
///
/// 两种写法都认：
/// - 带路径的（`D:\Music\晴天.flac`、`/mnt/music/a.mp3`），按文件路径匹配；
/// - 只写文字的（`周杰伦 - 晴天`、`晴天`），按歌名歌手匹配。
///
/// 行首的序号（`1.`、`01、`）与注释行（`#`、`//`）会先剥掉，导出的
/// 人 readable 清单常常带这些装饰。
M3uDocument parseTxt(String content, {String? baseDirectory}) {
  final entries = <M3uEntry>[];

  for (final rawLine in content.split(RegExp(r'\r\n|\r|\n'))) {
    var line = rawLine.trim();
    if (line.isEmpty) continue;
    if (line.startsWith('#') || line.startsWith('//') || line.startsWith(';')) {
      continue;
    }
    line = line.replaceFirst(RegExp(r'^\d{1,3}[.)、]\s*'), '').trim();
    if (line.isEmpty) continue;

    if (_looksLikeLocation(line)) {
      final location = resolvePlaylistLocation(line, baseDirectory);
      final meta = _trackFromFileName(location);
      entries.add(
        M3uEntry(location: location, title: meta.$2, artist: meta.$1),
      );
    } else {
      final split = splitArtistTitle(line);
      entries.add(M3uEntry(location: '', title: split.$2, artist: split.$1));
    }
  }

  return M3uDocument(entries: entries, droppedLines: 0);
}

bool _looksLikeLocation(String line) {
  if (line.contains('://')) return true;
  if (line.contains('/') || line.contains(r'\')) return true;
  final extension = playlistExtensionOf(line);
  return extension.isNotEmpty &&
      (kAudioFileExtensions.contains(extension) || extension == 'mp3');
}

// ==================== 共用 ====================

XmlElement _parseXml(String content) {
  try {
    return XmlDocument.parse(content).rootElement;
  } on XmlException {
    throw const PlaylistFileException(PlaylistReadFailure.malformed);
  }
}

Iterable<XmlElement> _descendants(XmlElement root, String localName) sync* {
  final target = localName.toLowerCase();
  for (final node in root.descendantElements) {
    // ASX 的标签全是大写（ENTRY / REF / TITLE），XSPF 与 WPL 是小写；
    // 统一按小写比较，一套解析代码能吃两种写法。
    if (node.name.local.toLowerCase() == target) yield node;
  }
}

XmlElement? _firstChild(XmlElement parent, String localName) {
  final target = localName.toLowerCase();
  for (final child in parent.childElements) {
    if (child.name.local.toLowerCase() == target) return child;
  }
  return null;
}

/// 属性名同样大小写不敏感：ASX 写 `HREF` / `VALUE`，WPL 写 `src`。
String? _attribute(XmlElement? element, String name) {
  if (element == null) return null;
  final target = name.toLowerCase();
  for (final attribute in element.attributes) {
    if (attribute.name.local.toLowerCase() == target) {
      return attribute.value;
    }
  }
  return null;
}

String? _childText(XmlElement parent, String localName) {
  final child = _firstChild(parent, localName);
  if (child == null) return null;
  final text = child.innerText.trim();
  return text.isEmpty ? null : text;
}

/// XSPF 的 `location` 多是 `file:///C:/...` 的 URI；WPL/ASX 则可能直接写
/// Windows 路径。统一转成匹配层能用的本地路径，http(s) 原样保留。
String _normalizeLocation(String location, String? baseDirectory) {
  final trimmed = location.trim();
  final uri = Uri.tryParse(trimmed);
  if (uri != null && uri.hasScheme) {
    if (uri.scheme == 'file') {
      try {
        return uri.toFilePath();
      } catch (_) {
        return resolvePlaylistLocation(trimmed, baseDirectory);
      }
    }
    return trimmed;
  }
  return resolvePlaylistLocation(trimmed, baseDirectory);
}

/// 从路径里猜 (歌手, 歌名)。
///
/// 常见命名是 `01 - 周杰伦 - 晴天.flac`、`01. 晴天.mp3`。先去扩展名与
/// 行首序号，再按「 - 」拆；拆不出来时整段当标题。
(String?, String?) _trackFromFileName(String location) {
  final path = location.replaceAll('\\', '/');
  final name = path.substring(path.lastIndexOf('/') + 1);
  var stem = name.replaceFirst(RegExp(r'\.[^.]+$'), '');
  stem = stem.replaceFirst(RegExp(r'^\d{1,3}[\s._-]+'), '').trim();
  if (stem.isEmpty) return (null, null);
  final split = splitArtistTitle(stem);
  return (split.$1, split.$2.isEmpty ? null : split.$2);
}

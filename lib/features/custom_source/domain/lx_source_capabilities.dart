class LxSourceCapabilities {
  static const supportedPlatforms = {'kw', 'kg', 'tx', 'wy', 'mg', 'local'};
  static const supportedActions = {'musicUrl', 'lyric', 'pic'};
  static const supportedQualities = {
    '128k',
    '320k',
    'flac',
    'flac24bit',
    'hires',
  };

  const LxSourceCapabilities._(this._actions, this._qualities);

  final Map<String, Set<String>> _actions;
  final Map<String, Set<String>> _qualities;

  bool get isEmpty => _actions.isEmpty;

  static bool hasSupportedSource(dynamic data) {
    if (data is! Map || data['sources'] is! Map) return false;
    return (data['sources'] as Map).entries.any(
      (entry) =>
          supportedPlatforms.contains(entry.key.toString().toLowerCase()) &&
          entry.value is Map,
    );
  }

  static bool requiresDeclaration(String action) {
    return supportedActions.contains(action);
  }

  bool allowsAction(String source, String action) {
    return !requiresDeclaration(action) || supports(source, action);
  }

  bool supports(String source, String action, [String? quality]) {
    final platform = source.toLowerCase();
    if (_actions[platform]?.contains(action) != true) return false;
    // musicUrl:??? qualitys ??????????(?????)
    if (action != 'musicUrl' || quality == null) return true;
    final qs = _qualities[platform];
    if (qs == null || qs.isEmpty) return true;
    return qs.contains(quality.toLowerCase());
  }

  /// 声明了某个动作的平台（保持脚本里的声明顺序）。
  ///
  /// 音源检测靠它决定「这个脚本能测哪几个平台」——`effectiveQuality` 只能逐平台问，
  /// 问不到「有哪些平台」。
  Set<String> platformsFor(String action) => {
    for (final entry in _actions.entries)
      if (entry.value.contains(action)) entry.key,
  };

  /// 某个平台声明过的音质，按 [order] 给出的优先级排序。
  ///
  /// 脚本没写 `qualitys` 时返回空表，调用方据此回落到「默认音质」。
  List<String> qualitiesFor(String platform, List<String> order) {
    final declared = _qualities[platform.toLowerCase()];
    if (declared == null || declared.isEmpty) return const <String>[];
    return order.where(declared.contains).toList(growable: false);
  }

  /// Returns the best quality this source actually declares for a request.
  /// A source may expose only lossy formats while the app preference is FLAC.
  String? effectiveQuality(String source, String action, String requested) {
    final platform = source.toLowerCase();
    if (_actions[platform]?.contains(action) != true) return null;
    if (action != 'musicUrl') return requested;
    final declared = _qualities[platform];
    if (declared == null || declared.isEmpty || declared.contains(requested)) {
      return requested;
    }
    const order = ['hires', 'flac24bit', 'flac', '320k', '192k', '128k'];
    const fallbackOrder = ['hires', 'flac24bit', 'flac', '320k', '128k'];
    final requestedIndex = order.indexOf(requested);
    final candidates = fallbackOrder
        .where(declared.contains)
        .toList(growable: false);
    if (candidates.isEmpty) return null;
    if (requestedIndex < 0) return candidates.first;
    final atOrBelow = candidates
        .where((quality) => order.indexOf(quality) >= requestedIndex)
        .toList(growable: false);
    return atOrBelow.isNotEmpty ? atOrBelow.first : candidates.last;
  }

  static LxSourceCapabilities fromInitData(dynamic data) {
    final actions = <String, Set<String>>{};
    final qualities = <String, Set<String>>{};
    if (data is! Map || data['sources'] is! Map) {
      return LxSourceCapabilities._(actions, qualities);
    }

    for (final entry in (data['sources'] as Map).entries) {
      final platform = entry.key.toString().toLowerCase();
      if (!supportedPlatforms.contains(platform) || entry.value is! Map) {
        continue;
      }
      final config = entry.value as Map;
      final declaredActions = <String>{};
      for (final action in supportedActions) {
        if (config[action] == true ||
            (config['actions'] is List &&
                (config['actions'] as List).contains(action))) {
          declaredActions.add(action);
        }
      }
      if (declaredActions.isNotEmpty) actions[platform] = declaredActions;

      final declaredQualities = config['qualitys'] ?? config['qualities'];
      if (declaredQualities is List) {
        qualities[platform] = declaredQualities
            .map((quality) => quality.toString().toLowerCase())
            .where(supportedQualities.contains)
            .toSet();
      }
    }
    return LxSourceCapabilities._(actions, qualities);
  }
}

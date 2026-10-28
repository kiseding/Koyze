// Copyright 2024 Koyze Contributors
// Licensed under the Apache License, Version 2.0

import 'dart:convert';

import '../../custom_source/domain/custom_source.dart';
import '../../player/domain/music_item.dart';
import '../../recommend/domain/recommendation_engine.dart';
import '../../recommend/domain/recommendation_tuning.dart';
import '../../source_check/domain/source_check_report.dart';
import 'ai_action_ports.dart';
import 'ai_config.dart';
import 'ai_schedule.dart';

/// 模型每次发起工具调用时回调一次，界面用它显示「AI 正在做什么」。
typedef AiToolObserver = void Function(AiToolCall call);

/// 工具的归属分组。界面只按分组显示一句话，不必为每个工具写一份文案。
enum AiToolCategory {
  library,
  playback,
  playlist,
  download,
  source,
  recommendation,
  settings,
}

/// 一个可被模型调用的操作。
///
/// [mutating] 为真表示它会改变用户数据或播放状态，只有 [AiToolbox.allowActions]
/// 打开时才下发给模型。所有 [run] 都直接打到服务层，不经过界面。
class AiTool {
  const AiTool({
    required this.name,
    required this.category,
    required this.description,
    required this.parameters,
    required this.run,
    this.mutating = false,
  });

  final String name;
  final AiToolCategory category;
  final String description;
  final Map<String, dynamic> parameters;
  final Future<Object?> Function(Map<String, dynamic> args) run;
  final bool mutating;

  Map<String, dynamic> get spec => {
    'type': 'function',
    'function': {
      'name': name,
      'description': description,
      'parameters': parameters,
    },
  };
}

/// 开放给模型的全部操作。
///
/// 覆盖面按「人在应用里能做的事」来定：播放控制、队列、歌单增删改排序、收藏、
/// 下载、音源开关与检测、界面设置。每个操作都通过 [AiToolbox] 注入的端口落到
/// 真实服务上，既不模拟点击也不依赖哪个页面正开着。
class AiToolbox {
  AiToolbox({
    required this.playback,
    required this.playlists,
    required this.downloads,
    required this.sources,
    required this.recommendations,
    required this.settings,
    required this.search,
    required this.equalizer,
    required this.stats,
    required this.lyrics,
    required this.charts,
    required this.schedules,
    required this.local,
    this.allowActions = true,
  });

  final AiPlaybackPort playback;
  final AiPlaylistPort playlists;
  final AiDownloadPort downloads;
  final AiSourcePort sources;
  final AiRecommendationPort recommendations;
  final AiSettingsPort settings;
  final AiEqualizerPort equalizer;
  final AiStatsPort stats;
  final AiLyricPort lyrics;
  final AiChartPort charts;
  final AiSchedulePort schedules;
  final AiLocalPort local;

  /// 曲库搜索：`query` 与 `limit`。
  final Future<List<MusicItem>> Function(String query, int limit) search;

  /// 是否允许改变状态的操作。关掉后只保留只读工具。
  final bool allowActions;

  static const String searchLibrary = 'search_library';
  static const String listPlaylists = 'list_playlists';
  static const String getPlaylist = 'get_playlist';
  static const String nowPlaying = 'get_now_playing';
  static const String getQueue = 'get_queue';
  static const String sourceStatus = 'source_status';
  static const String listDownloads = 'list_downloads';

  static const String playSong = 'play_song';
  static const String playPlaylistTool = 'play_playlist';
  static const String playerControl = 'player_control';
  static const String seekTool = 'seek';
  static const String setVolumeTool = 'set_volume';
  static const String setPlayMode = 'set_play_mode';
  static const String markDislikedTool = 'mark_disliked';
  static const String setSleepTimerTool = 'set_sleep_timer';
  static const String queueSongs = 'queue_songs';

  static const String createPlaylistTool = 'create_playlist';
  static const String updatePlaylistTool = 'update_playlist';
  static const String deletePlaylistTool = 'delete_playlist';
  static const String addSongsTool = 'add_songs_to_playlist';
  static const String removeSongsTool = 'remove_songs_from_playlist';
  static const String sortPlaylistTool = 'sort_playlist';
  static const String setFavoriteTool = 'set_favorite';

  static const String downloadSongsTool = 'download_songs';
  static const String deleteDownloadTool = 'delete_download';
  static const String clearDownloadCacheTool = 'clear_download_cache';

  static const String toggleSourceTool = 'toggle_source';
  static const String runSourceCheckTool = 'run_source_check';

  static const String getRecommendationsTool = 'get_recommendations';
  static const String editRecommendationsTool = 'edit_recommendations';

  static const String setAppSettingTool = 'set_app_setting';

  static const String getEqualizerTool = 'get_equalizer';
  static const String setEqualizerTool = 'set_equalizer';

  static const String listeningStatsTool = 'get_listening_stats';
  static const String lyricsTool = 'get_lyrics';

  static const String listChartsTool = 'list_charts';
  static const String playChartTool = 'play_chart';

  static const String listSchedulesTool = 'list_ai_schedules';
  static const String manageScheduleTool = 'manage_ai_schedule';

  static const String rescanLocalTool = 'rescan_local_music';
  static const String writeLocalTagsTool = 'write_local_tags';

  static const int _maxSearchResults = 20;
  static const int _maxSongsPerCall = 40;
  static const int _maxQueuePreview = 50;

  static const Map<String, dynamic> _songArray = {
    'type': 'array',
    'description': '歌曲列表，元素可以是 "歌名 歌手" 字符串，也可以是 {title, artist} 对象',
    'items': {
      'type': 'object',
      'properties': {
        'title': {'type': 'string', 'description': '歌名'},
        'artist': {'type': 'string', 'description': '歌手'},
        'id': {'type': 'string', 'description': '已知歌曲 id 时可直接给，免去再搜一次'},
      },
      'required': ['title'],
    },
  };

  late final List<AiTool> _tools = _buildTools();

  /// 交给接口的 `tools[]`：无权限时写操作整个不下发。
  List<Map<String, dynamic>> get specs => [
    for (final tool in _tools)
      if (allowActions || !tool.mutating) tool.spec,
  ];

  AiTool? toolNamed(String name) {
    for (final tool in _tools) {
      if (tool.name == name) return tool;
    }
    return null;
  }

  /// 当前播放状态的一句话摘要，随系统提示一起发出去，省掉一次查询。
  String get stateLine {
    final song = playback.currentSong;
    return [
      song == null ? '当前没有播放中的歌曲' : '正在播放《${song.name}》- ${song.singer}',
      playback.isPlaying ? '播放中' : '已暂停',
      '音量 ${(playback.volume * 100).round()}%',
      '随机${playback.shuffleEnabled ? '开' : '关'}',
      '循环 ${_repeatLabel(playback.repeatMode)}',
      '队列 ${playback.queue.length} 首',
      if (playback.sleepTimerRemaining case final remaining?)
        '睡眠定时 ${(remaining.inSeconds / 60).ceil()} 分钟后',
    ].join('，');
  }

  /// 执行一次调用。失败也返回 JSON（带 `error`），让模型自己重试或换参数。
  Future<String> call(AiToolCall call) async {
    final tool = toolNamed(call.name);
    if (tool == null) return jsonEncode({'error': '未知工具：${call.name}'});
    if (tool.mutating && !allowActions) {
      return jsonEncode({'error': '执行权限已关闭，只能用文字告诉用户该怎么做'});
    }
    try {
      return _limitedJson(await tool.run(call.arguments));
    } catch (error) {
      return jsonEncode({'error': error.toString()});
    }
  }

  /// 单次工具结果的上限（字符）。结果会原样回填给模型，一个 40 首的歌单就是
  /// 几 KB，连着几轮很容易顶爆上下文——那时候接口只会回一句
  /// 「返回内容无法解析」，用户完全看不出是对话太长了。
  static const int _maxToolResultChars = 4000;

  static String _limitedJson(Object? result) {
    final text = jsonEncode(result);
    if (text.length <= _maxToolResultChars) return text;
    var shrunk = _shrink(result);
    var encoded = jsonEncode(shrunk);
    while (encoded.length > _maxToolResultChars) {
      final next = _shrink(shrunk);
      final nextEncoded = jsonEncode(next);
      // 已经压不动（空列表 / 短字符串），再转也是同一个长度。
      if (nextEncoded.length >= encoded.length) break;
      shrunk = next;
      encoded = nextEncoded;
    }
    return encoded;
  }

  /// 折半列表、截断长字符串，保留 JSON 结构，模型仍然读得懂。
  static Object? _shrink(Object? value) {
    if (value is String) {
      return value.length <= 320 ? value : '${value.substring(0, 320)}…';
    }
    if (value is List) {
      if (value.isEmpty) return value;
      final keep = (value.length / 2).ceil();
      return [
        for (var index = 0; index < keep; index++) _shrink(value[index]),
        if (keep < value.length)
          {
            'omitted': value.length - keep,
            'note': '结果太长，其余 ${value.length - keep} 条已省略',
          },
      ];
    }
    if (value is Map) {
      return {
        for (final entry in value.entries)
          entry.key.toString(): _shrink(entry.value),
      };
    }
    return value;
  }

  List<AiTool> _buildTools() => [
    // ---------------------------------------------------------------- 只读
    AiTool(
      name: searchLibrary,
      category: AiToolCategory.library,
      description:
          '在用户的曲库里搜索歌曲。要播歌、加歌单、收藏、下载之前先用它确认歌名和歌手能搜到，'
          '不要凭记忆编造。返回 id、歌名、歌手、专辑和平台。',
      parameters: {
        'type': 'object',
        'properties': {
          'query': {'type': 'string', 'description': '搜索词，通常是「歌名 歌手」'},
          'limit': {'type': 'integer', 'description': '返回条数，1-20，默认 8'},
        },
        'required': ['query'],
      },
      run: _runSearch,
    ),
    AiTool(
      name: listPlaylists,
      category: AiToolCategory.library,
      description: '列出用户已有的歌单：id、名称、歌曲数。system 标记为真的歌单不能删除。',
      parameters: {'type': 'object', 'properties': <String, dynamic>{}},
      run: _runListPlaylists,
    ),
    AiTool(
      name: getPlaylist,
      category: AiToolCategory.library,
      description: '读取某个歌单里的歌曲。用歌单 id 或名称指定，返回每首歌的 id、歌名与歌手。',
      parameters: {
        'type': 'object',
        'properties': {
          'playlist': {'type': 'string', 'description': '歌单 id 或名称'},
        },
        'required': ['playlist'],
      },
      run: _runGetPlaylist,
    ),
    AiTool(
      name: nowPlaying,
      category: AiToolCategory.library,
      description: '查看当前播放的歌曲、进度、音量、随机与循环状态、队列长度。',
      parameters: {'type': 'object', 'properties': <String, dynamic>{}},
      run: _runNowPlaying,
    ),
    AiTool(
      name: getQueue,
      category: AiToolCategory.library,
      description: '查看播放队列里有哪些歌，以及当前播放到第几首。',
      parameters: {'type': 'object', 'properties': <String, dynamic>{}},
      run: _runQueue,
    ),
    AiTool(
      name: sourceStatus,
      category: AiToolCategory.library,
      description: '查看已导入音源脚本的启用状态与上次检测结果，用来判断现在能不能搜到、取到播放地址。',
      parameters: {'type': 'object', 'properties': <String, dynamic>{}},
      run: _runSourceStatus,
    ),
    AiTool(
      name: listDownloads,
      category: AiToolCategory.library,
      description: '列出下载任务：任务 id、歌名、歌手、状态与进度。',
      parameters: {
        'type': 'object',
        'properties': {
          'status': {
            'type': 'string',
            'description':
                '只看某个状态：pending / downloading / completed / failed / paused',
          },
        },
      },
      run: _runListDownloads,
    ),

    // ---------------------------------------------------------------- 播放
    _write(
      playSong,
      AiToolCategory.playback,
      '搜索并立即播放一首歌。先用 search_library 确认过的歌名与歌手直接传进来即可。',
      {
        'title': {'type': 'string', 'description': '歌名'},
        'artist': {'type': 'string', 'description': '歌手，尽量给'},
      },
      _runPlaySong,
      required: ['title'],
    ),
    _write(
      playPlaylistTool,
      AiToolCategory.playback,
      '播放一个已保存的歌单，从头开始或从指定序号开始。',
      {
        'playlist': {'type': 'string', 'description': '歌单 id 或名称'},
        'index': {'type': 'integer', 'description': '从第几首开始，从 0 计，默认 0'},
      },
      _runPlayPlaylist,
      required: ['playlist'],
    ),
    _write(
      playerControl,
      AiToolCategory.playback,
      '播放控制：播放、暂停、播放/暂停切换、上一首、下一首、停止。',
      {
        'action': {
          'type': 'string',
          'description': 'play / pause / toggle / next / previous / stop',
        },
      },
      _runPlayerControl,
      required: ['action'],
    ),
    _write(seekTool, AiToolCategory.playback, '把当前歌曲跳到指定位置。给秒数，或给百分比。', {
      'seconds': {'type': 'number', 'description': '目标位置（秒）'},
      'percent': {
        'type': 'number',
        'description': '目标位置百分比 0-100，和 seconds 二选一',
      },
    }, _runSeek),
    _write(
      setVolumeTool,
      AiToolCategory.playback,
      '设置播放音量，0-100。',
      {
        'percent': {'type': 'number', 'description': '音量百分比 0-100'},
      },
      _runSetVolume,
      required: ['percent'],
    ),
    _write(setPlayMode, AiToolCategory.playback, '设置随机播放与循环模式。只传要改的那一项即可。', {
      'shuffle': {'type': 'boolean', 'description': '是否随机播放'},
      'repeat': {
        'type': 'string',
        'description': 'off（顺序）/ all（列表循环）/ one（单曲循环）',
      },
    }, _runSetPlayMode),
    _write(
      markDislikedTool,
      AiToolCategory.playback,
      '标记或取消标记「不感兴趣」。标记过的歌自动播放时会跳过。不传 songs 且 current_song=true 时作用于正在播放的那首。',
      {
        'songs': _songArray,
        'current_song': {'type': 'boolean', 'description': '是否作用于当前播放的歌曲'},
        'disliked': {'type': 'boolean', 'description': 'true 标记（默认），false 取消'},
      },
      _runMarkDisliked,
    ),
    _write(
      setSleepTimerTool,
      AiToolCategory.playback,
      '开睡眠定时：minutes 分钟后自动暂停；minutes 给 0 就取消定时。',
      {
        'minutes': {'type': 'number', 'description': '多少分钟后暂停，0 表示取消'},
      },
      _runSetSleepTimer,
      required: ['minutes'],
    ),
    _write(
      queueSongs,
      AiToolCategory.playback,
      '把歌加进播放队列：position=next 插到当前歌曲后面下一首播放，position=end 追加到队尾。',
      {
        'songs': _songArray,
        'position': {'type': 'string', 'description': 'next / end，默认 end'},
      },
      _runQueueSongs,
      required: ['songs'],
    ),

    // ---------------------------------------------------------------- 歌单
    _write(
      createPlaylistTool,
      AiToolCategory.playlist,
      '创建一个新歌单。给出歌名和歌曲列表，工具会逐首在曲库里核实，搜不到的会跳过并告诉你。',
      {
        'name': {'type': 'string', 'description': '歌单名'},
        'description': {'type': 'string', 'description': '一句话介绍'},
        'songs': _songArray,
      },
      _runCreatePlaylist,
      required: ['name', 'songs'],
    ),
    _write(
      updatePlaylistTool,
      AiToolCategory.playlist,
      '重命名歌单或改它的介绍。',
      {
        'playlist': {'type': 'string', 'description': '歌单 id 或名称'},
        'name': {'type': 'string', 'description': '新名称'},
        'description': {'type': 'string', 'description': '新介绍'},
      },
      _runUpdatePlaylist,
      required: ['playlist'],
    ),
    _write(
      deletePlaylistTool,
      AiToolCategory.playlist,
      '删除一个歌单。不可撤销，只有用户明确要求删除时才能调用；收藏、最近播放、本地音乐不能被删除。',
      {
        'playlist': {'type': 'string', 'description': '歌单 id 或名称'},
      },
      _runDeletePlaylist,
      required: ['playlist'],
    ),
    _write(
      addSongsTool,
      AiToolCategory.playlist,
      '把歌曲加进指定歌单，加在末尾。已经在歌单里的会跳过。',
      {
        'playlist': {'type': 'string', 'description': '歌单 id 或名称'},
        'songs': _songArray,
      },
      _runAddSongs,
      required: ['playlist', 'songs'],
    ),
    _write(
      removeSongsTool,
      AiToolCategory.playlist,
      '从歌单里移除歌曲。用 get_playlist 拿到的 id，或歌名 + 歌手都可以。',
      {
        'playlist': {'type': 'string', 'description': '歌单 id 或名称'},
        'songs': _songArray,
      },
      _runRemoveSongs,
      required: ['playlist', 'songs'],
    ),
    _write(
      sortPlaylistTool,
      AiToolCategory.playlist,
      '按歌名、歌手或时长给歌单排序。',
      {
        'playlist': {'type': 'string', 'description': '歌单 id 或名称'},
        'by': {'type': 'string', 'description': 'name / artist / duration'},
        'ascending': {'type': 'boolean', 'description': '是否升序，默认 true'},
      },
      _runSortPlaylist,
      required: ['playlist', 'by'],
    ),
    _write(
      setFavoriteTool,
      AiToolCategory.playlist,
      '收藏或取消收藏歌曲。不传 songs 且 current_song=true 时操作正在播放的那首。',
      {
        'songs': _songArray,
        'current_song': {'type': 'boolean', 'description': '是否作用于当前播放的歌曲'},
        'favorite': {
          'type': 'boolean',
          'description': 'true 收藏（默认），false 取消收藏',
        },
      },
      _runSetFavorite,
    ),

    // ---------------------------------------------------------------- 下载
    _write(
      downloadSongsTool,
      AiToolCategory.download,
      '把歌曲加入下载任务。可以给歌曲列表，也可以给一个歌单名（最多下载前 40 首）。',
      {
        'songs': _songArray,
        'playlist': {'type': 'string', 'description': '歌单 id 或名称，和 songs 二选一'},
      },
      _runDownloadSongs,
    ),
    _write(
      deleteDownloadTool,
      AiToolCategory.download,
      '删除一个下载任务和它已下载的文件。可用任务 id，也可用歌名匹配。',
      {
        'task_id': {'type': 'string', 'description': '下载任务 id'},
        'title': {'type': 'string', 'description': '歌名，task_id 未知时用'},
      },
      _runDeleteDownload,
    ),
    _write(
      clearDownloadCacheTool,
      AiToolCategory.download,
      '清空下载缓存目录里已经下载的文件。不可撤销。',
      <String, dynamic>{},
      _runClearDownloadCache,
    ),

    // ---------------------------------------------------------------- 音源
    _write(
      toggleSourceTool,
      AiToolCategory.source,
      '启用或停用一个音源脚本。停用后这个脚本不再参与搜索与取播放地址。',
      {
        'source': {'type': 'string', 'description': '脚本 id 或名称'},
        'enabled': {'type': 'boolean', 'description': 'true 启用，false 停用'},
      },
      _runToggleSource,
      required: ['source', 'enabled'],
    ),
    _write(
      runSourceCheckTool,
      AiToolCategory.source,
      '跑一次音源检测（真实取一次音频地址）。不传 source 就检测全部脚本，可能比较慢。',
      {
        'source': {'type': 'string', 'description': '只检测这个脚本（id 或名称）'},
      },
      _runRunSourceCheck,
    ),

    // ------------------------------------------------------------ 猜你喜欢
    AiTool(
      name: getRecommendationsTool,
      category: AiToolCategory.recommendation,
      description:
          '读取「猜你喜欢」当前推荐了哪些歌，以及已经设过的调整（置顶、屏蔽、口味提示）。'
          '用户问「猜你喜欢推荐了什么」「为什么给我推这首」时先用它。',
      parameters: {
        'type': 'object',
        'properties': {
          'limit': {'type': 'integer', 'description': '返回条数，1-30，默认 15'},
        },
      },
      run: _runGetRecommendations,
    ),
    _write(
      editRecommendationsTool,
      AiToolCategory.recommendation,
      '调整「猜你喜欢」：把歌顶到最前、把歌或歌手挡掉、写一句口味提示。'
      '改完会自动重算，返回新的推荐。用 clear 撤销之前的调整。',
      {
        'pin': _songArray,
        'exclude': _songArray,
        'exclude_artists': {
          'type': 'array',
          'description': '不想再看到的歌手名',
          'items': {'type': 'string'},
        },
        'focus': {
          'type': 'string',
          'description': '口味提示，例如「多来点粤语老歌」。传空串表示清除',
        },
        'clear': {
          'type': 'array',
          'description':
              '要撤销的部分：pinned / excluded / artists / focus / all',
          'items': {'type': 'string'},
        },
      },
      _runEditRecommendations,
    ),

    // ---------------------------------------------------------------- 设置
    _write(
      setAppSettingTool,
      AiToolCategory.settings,
      '修改应用设置。key：audio_quality（low/high/lossless/lossless24/hires）、'
      'download_quality（同上）、wifi_only_download（true/false）、theme（system/light/dark）。',
      {
        'key': {'type': 'string', 'description': '设置项名称'},
        'value': {
          'type': 'string',
          'description': '新的值。布尔项传 "true" / "false"',
        },
      },
      _runSetAppSetting,
      required: ['key', 'value'],
    ),

    // ------------------------------------------------------------ 声音与偏好
    AiTool(
      name: getEqualizerTool,
      category: AiToolCategory.settings,
      description:
          '查看均衡器状态：这个平台支不支持、开关、当前预设、各频段增益（Hz 与 dB）。'
          '用户说「低音太重」「听着闷」时先看一眼当前曲线再调。',
      parameters: {'type': 'object', 'properties': <String, dynamic>{}},
      run: _runGetEqualizer,
    ),
    _write(
      setEqualizerTool,
      AiToolCategory.settings,
      '调均衡器：开关、选预设（flat/pop/rock/jazz/classical/electronic/folk/vocal/bass/treble）、'
      '按频率改某个频段的增益，或 reset 恢复平直。几项可以同时给，按「开关 → 预设 → 频段」顺序生效。',
      {
        'enabled': {'type': 'boolean', 'description': '是否开启均衡器'},
        'preset': {
          'type': 'string',
          'description': '预设 id，例如 bass / vocal / rock；传 custom 表示保持手动曲线',
        },
        'bands': {
          'type': 'array',
          'description': '要改的频段：hz 是频段中心频率，gain_db 是增益（dB）',
          'items': {
            'type': 'object',
            'properties': {
              'hz': {'type': 'number', 'description': '中心频率，例如 60'},
              'gain_db': {'type': 'number', 'description': '增益，单位 dB，例如 3'},
            },
            'required': ['hz', 'gain_db'],
          },
        },
        'reset': {'type': 'boolean', 'description': '是否恢复平直曲线'},
      },
      _runSetEqualizer,
    ),

    // ---------------------------------------------------------------- 洞察
    AiTool(
      name: listeningStatsTool,
      category: AiToolCategory.library,
      description:
          '读听歌统计：播放次数、总时长、活跃天数，以及歌曲 / 歌手 / 专辑排行。'
          'range 取 week / month / year / all，默认 week。',
      parameters: {
        'type': 'object',
        'properties': {
          'range': {'type': 'string', 'description': 'week / month / year / all'},
          'limit': {'type': 'integer', 'description': '每张榜返回几条，1-20，默认 10'},
        },
      },
      run: _runListeningStats,
    ),
    AiTool(
      name: lyricsTool,
      category: AiToolCategory.library,
      description:
          '取一首歌的歌词（带时间戳）。不传参数就是正在播放的那首；也可以给 title / artist。'
          '取不到就返回 error，不要自己编歌词。',
      parameters: {
        'type': 'object',
        'properties': {
          'current_song': {'type': 'boolean', 'description': '是否取当前播放的歌'},
          'title': {'type': 'string', 'description': '歌名'},
          'artist': {'type': 'string', 'description': '歌手'},
          'max_lines': {'type': 'integer', 'description': '最多返回多少行，默认 60'},
        },
      },
      run: _runLyrics,
    ),

    // ---------------------------------------------------------------- 榜单
    AiTool(
      name: listChartsTool,
      category: AiToolCategory.library,
      description:
          '列出可用的排行榜（QQ 音乐、酷我、网易云、酷狗等平台的榜单）。'
          '返回的 id 可以直接喂给 play_chart。',
      parameters: {
        'type': 'object',
        'properties': {
          'platform': {
            'type': 'string',
            'description': '只看某个平台，例如 qq / kw / wy / kg；不传则全部',
          },
        },
      },
      run: _runListCharts,
    ),
    _write(
      playChartTool,
      AiToolCategory.playback,
      '播放一个排行榜。chart 给 id 或名称都行（先用 list_charts 拿 id 更稳）。',
      {
        'chart': {'type': 'string', 'description': '榜单 id（platform:id）或名称'},
        'index': {'type': 'integer', 'description': '从第几首开始，从 0 计，默认 0'},
      },
      _runPlayChart,
      required: ['chart'],
    ),

    // ------------------------------------------------------------ 定时任务
    AiTool(
      name: listSchedulesTool,
      category: AiToolCategory.settings,
      description: '列出已经建好的 AI 定时任务：id、名称、到点时间、重复方式、开关与上次结果。',
      parameters: {'type': 'object', 'properties': <String, dynamic>{}},
      run: _runListSchedules,
    ),
    _write(
      manageScheduleTool,
      AiToolCategory.settings,
      '管理 AI 定时任务。action=create 需要 title、prompt、time(HH:mm)，cadence 取 '
      'daily / weekdays / weekly（weekly 还要 weekday 1-7）；run 立刻跑一次；'
      'pause / resume 开关；remove 删除。id 从 list_ai_schedules 取。',
      {
        'action': {
          'type': 'string',
          'description': 'create / run / pause / resume / remove',
        },
        'id': {'type': 'string', 'description': '任务 id，除 create 外都要'},
        'title': {'type': 'string', 'description': '任务名，例如「早间通勤歌单」'},
        'prompt': {
          'type': 'string',
          'description': '到点时执行的那句话，要能独立看懂',
        },
        'time': {'type': 'string', 'description': 'HH:mm，例如 08:00'},
        'cadence': {'type': 'string', 'description': 'daily / weekdays / weekly'},
        'weekday': {'type': 'integer', 'description': '周几，1=周一 … 7=周日'},
      },
      _runManageSchedule,
      required: ['action'],
    ),

    _write(
      rescanLocalTool,
      AiToolCategory.library,
      '重新扫描本地曲库（用户选的文件夹，Android 上还包括系统媒体库）。'
      '用户说「我刚拷了几首歌进去」时用；可能比较慢，返回这次新增的曲目数。',
      <String, dynamic>{},
      _runRescanLocal,
    ),

    _write(
      writeLocalTagsTool,
      AiToolCategory.library,
      '把标题 / 歌手 / 专辑写进本地音乐文件本身的 tag（ID3 / Vorbis 等），'
      '不是只改应用内的显示。song_id 用 get_playlist 读「本地音乐」（id 为 local）'
      '拿到的 local: 前缀 id。只传要改的字段，其余保持不变；album 传空串表示清空。'
      'wav / ape 这类只读容器会写失败并说明原因。',
      {
        'song_id': {
          'type': 'string',
          'description': '本地歌曲 id（local: 前缀），来自「本地音乐」歌单',
        },
        'title': {'type': 'string', 'description': '新的标题，不改就不传'},
        'artist': {'type': 'string', 'description': '新的歌手，不改就不传'},
        'album': {'type': 'string', 'description': '新的专辑，不改就不传；空串表示清空'},
      },
      _runWriteLocalTags,
      required: ['song_id'],
    ),
  ];

  AiTool _write(
    String name,
    AiToolCategory category,
    String description,
    Map<String, dynamic> properties,
    Future<Object?> Function(Map<String, dynamic> args) run, {
    List<String> required = const [],
  }) => AiTool(
    name: name,
    category: category,
    description: description,
    parameters: {
      'type': 'object',
      'properties': properties,
      if (required.isNotEmpty) 'required': required,
    },
    run: run,
    mutating: true,
  );

  // ------------------------------------------------------------------ 只读

  Future<Object?> _runSearch(Map<String, dynamic> args) async {
    final query = (args['query'] ?? '').toString().trim();
    if (query.isEmpty) return {'error': 'query 不能为空'};
    final limit = _intOf(
      args['limit'],
      fallback: 8,
    ).clamp(1, _maxSearchResults);
    final results = await search(query, limit);
    return {
      'query': query,
      'songs': [for (final item in results.take(limit)) _songJson(item)],
    };
  }

  Future<Object?> _runListPlaylists(Map<String, dynamic> _) async {
    final list = await playlists.loadPlaylists();
    return {
      'playlists': [
        for (final playlist in list)
          {
            'id': playlist.id,
            'name': playlist.name,
            'songs': playlist.songCount,
            if (_systemPlaylistIds.contains(playlist.id)) 'system': true,
          },
      ],
    };
  }

  Future<Object?> _runGetPlaylist(Map<String, dynamic> args) async {
    final query = _playlistQuery(args);
    if (query.isEmpty) return {'error': '需要 playlist'};
    final found = await playlists.findPlaylist(query);
    if (found == null) return {'error': '没有找到这个歌单'};
    final songs = await playlists.songsOf(found.id);
    return {
      'id': found.id,
      'name': found.name,
      if ((found.description ?? '').isNotEmpty)
        'description': found.description,
      if (_systemPlaylistIds.contains(found.id)) 'system': true,
      'songs': [
        for (final item in songs.take(_maxSongsPerCall)) _songJson(item),
      ],
      'total': songs.length,
    };
  }

  Future<Object?> _runNowPlaying(Map<String, dynamic> _) async {
    final song = playback.currentSong;
    return {
      'playing': playback.isPlaying,
      if (song != null) 'song': _songJson(song),
      'positionSeconds': playback.position.inSeconds,
      if (song != null) 'durationSeconds': song.duration.inSeconds,
      'volumePercent': (playback.volume * 100).round(),
      'shuffle': playback.shuffleEnabled,
      'repeat': playback.repeatMode,
      'queueLength': playback.queue.length,
      if (song != null) 'disliked': await playback.isDisliked(song),
      if (playback.sleepTimerRemaining case final remaining?)
        'sleepTimerMinutes': (remaining.inSeconds / 60).ceil(),
    };
  }

  Future<Object?> _runQueue(Map<String, dynamic> _) async {
    final queue = playback.queue;
    final current = playback.currentSong;
    final currentIndex = current == null
        ? -1
        : queue.indexWhere((item) => item.identityKey == current.identityKey);
    return {
      'total': queue.length,
      'currentIndex': currentIndex,
      'songs': [
        for (
          var index = 0;
          index < queue.length && index < _maxQueuePreview;
          index++
        )
          {'index': index, ..._songJson(queue[index])},
      ],
    };
  }

  Future<Object?> _runSourceStatus(Map<String, dynamic> _) async {
    final book = sources.checkBook;
    return {
      'sources': [
        for (final source in sources.sources) _sourceJson(source, book),
      ],
    };
  }

  Future<Object?> _runListDownloads(Map<String, dynamic> args) async {
    final status = (args['status'] ?? '').toString().trim();
    final tasks = [
      for (final task in downloads.tasks)
        if (status.isEmpty || task.status.name == status)
          {
            'id': task.id,
            'title': task.name,
            'artist': task.singer,
            'status': task.status.name,
            'progressPercent': (task.progress * 100).round(),
            if (task.quality != null) 'quality': task.quality,
          },
    ];
    return {
      'total': tasks.length,
      'downloads': tasks.take(_maxSongsPerCall).toList(),
    };
  }

  static Map<String, dynamic> _sourceJson(
    CustomSource source,
    SourceCheckBook book,
  ) {
    final report = book.forSource(source.id);
    final tested = report != null && report.perPlatform.isNotEmpty;
    return {
      'id': source.id,
      'name': source.name,
      'enabled': source.isEnabled,
      'tested': tested,
      if (report != null && tested) 'okPlatforms': report.okPlatformCount,
      if (report != null && tested) 'totalPlatforms': report.perPlatform.length,
      if (report != null && tested)
        'platforms': report.perPlatform.keys.toList(growable: false),
    };
  }

  // ------------------------------------------------------------------ 播放

  Future<Object?> _runPlaySong(Map<String, dynamic> args) async {
    final title = (args['title'] ?? args['query'] ?? '').toString().trim();
    final artist = (args['artist'] ?? '').toString().trim();
    if (title.isEmpty) return {'error': 'title 不能为空'};
    final song = await _resolve(title, artist);
    if (song == null) {
      return {
        'error': '曲库里没搜到这首歌',
        'query': artist.isEmpty ? title : '$title $artist',
      };
    }
    await playback.playSongs([song]);
    return {'playing': _songJson(song)};
  }

  Future<Object?> _runPlayPlaylist(Map<String, dynamic> args) async {
    final query = _playlistQuery(args);
    if (query.isEmpty) return {'error': '需要 playlist'};
    final playlist = await playlists.findPlaylist(query);
    if (playlist == null) return {'error': '没有找到这个歌单'};
    if (playlist.songCount == 0) return {'error': '歌单是空的'};
    final index = _intOf(
      args['index'],
      fallback: 0,
    ).clamp(0, playlist.songCount - 1);
    await playback.playPlaylist(playlist.id, index: index);
    return {
      'playing': playlist.name,
      'songs': playlist.songCount,
      'from': index,
    };
  }

  Future<Object?> _runPlayerControl(Map<String, dynamic> args) async {
    final action = (args['action'] ?? '').toString().trim().toLowerCase();
    switch (action) {
      case 'play':
        await playback.play();
        break;
      case 'pause':
        await playback.pause();
        break;
      case 'toggle':
        if (playback.isPlaying) {
          await playback.pause();
        } else {
          await playback.play();
        }
        break;
      case 'next':
        await playback.next();
        break;
      case 'previous':
        await playback.previous();
        break;
      case 'stop':
        await playback.stop();
        break;
      default:
        return {
          'error': 'action 只能是 play / pause / toggle / next / previous / stop',
        };
    }
    return _runNowPlaying(const {});
  }

  Future<Object?> _runSeek(Map<String, dynamic> args) async {
    final song = playback.currentSong;
    if (song == null) return {'error': '当前没有播放中的歌曲'};
    final percent = _doubleOf(args['percent']);
    final seconds = _doubleOf(args['seconds']);
    Duration target;
    if (percent != null) {
      target = Duration(
        milliseconds: (song.duration.inMilliseconds * percent / 100)
            .clamp(0, song.duration.inMilliseconds)
            .round(),
      );
    } else if (seconds != null) {
      target = Duration(milliseconds: (seconds * 1000).round());
    } else {
      return {'error': '需要 seconds 或 percent'};
    }
    await playback.seek(target);
    return {'positionSeconds': target.inSeconds};
  }

  Future<Object?> _runSetVolume(Map<String, dynamic> args) async {
    var percent = _doubleOf(args['percent']);
    if (percent == null) {
      final raw = _doubleOf(args['volume']);
      if (raw == null) return {'error': '需要 percent'};
      percent = raw <= 1 ? raw * 100 : raw;
    }
    final value = percent.clamp(0, 100) / 100;
    await playback.setVolume(value);
    return {'volumePercent': (value * 100).round()};
  }

  Future<Object?> _runSetPlayMode(Map<String, dynamic> args) async {
    final shuffle = args['shuffle'];
    final repeat = (args['repeat'] ?? '').toString().trim().toLowerCase();
    if (shuffle == null && repeat.isEmpty) {
      return {'error': '需要 shuffle 或 repeat'};
    }
    if (shuffle is bool) await playback.setShuffle(shuffle);
    if (repeat.isNotEmpty) {
      if (!const {'off', 'all', 'one'}.contains(repeat)) {
        return {'error': 'repeat 只能是 off / all / one'};
      }
      await playback.setRepeat(repeat);
    }
    return _runNowPlaying(const {});
  }

  Future<Object?> _runMarkDisliked(Map<String, dynamic> args) async {
    final disliked = args['disliked'] != false;
    final songs = <MusicItem>[];
    final skipped = <String>[];
    if (args['current_song'] == true) {
      final current = playback.currentSong;
      if (current == null) return {'error': '当前没有播放中的歌曲'};
      songs.add(current);
    } else {
      final (picked, missing) = await _resolveMany(args['songs']);
      songs.addAll(picked);
      skipped.addAll(missing);
    }
    if (songs.isEmpty) {
      return {'error': '没有可操作的歌曲', 'skipped': skipped};
    }
    for (final song in songs) {
      await playback.setDisliked(song, disliked);
    }
    return {
      'ok': true,
      'disliked': disliked,
      'songs': [for (final song in songs) song.name],
      'skipped': skipped,
    };
  }

  Future<Object?> _runSetSleepTimer(Map<String, dynamic> args) async {
    final minutes = _doubleOf(args['minutes']);
    if (minutes == null) return {'error': 'minutes 需要数字'};
    if (minutes <= 0) {
      await playback.setSleepTimer(null);
      return {'active': false};
    }
    final duration = Duration(seconds: (minutes * 60).round());
    await playback.setSleepTimer(duration);
    return {'active': true, 'minutes': duration.inMinutes};
  }

  Future<Object?> _runQueueSongs(Map<String, dynamic> args) async {
    final (picked, skipped) = await _resolveMany(args['songs']);
    if (picked.isEmpty) {
      return {'error': '这些歌在曲库里都没找到', 'skipped': skipped};
    }
    final position = (args['position'] ?? 'end')
        .toString()
        .trim()
        .toLowerCase();
    if (position != 'next' && position != 'end') {
      return {'error': 'position 只能是 next 或 end'};
    }
    await playback.enqueue(picked, playNext: position == 'next');
    return {'queued': picked.length, 'position': position, 'skipped': skipped};
  }

  // ------------------------------------------------------------------ 歌单

  Future<Object?> _runCreatePlaylist(Map<String, dynamic> args) async {
    final name = (args['name'] ?? '').toString().trim();
    if (name.isEmpty) return {'error': 'name 不能为空'};
    final (picked, skipped) = await _resolveMany(args['songs']);
    if (picked.isEmpty) {
      return {'error': '这些歌在曲库里都没找到，未创建歌单', 'skipped': skipped};
    }
    final description = (args['description'] ?? '').toString().trim();
    final created = await playlists.create(
      name: name,
      description: description.isEmpty ? null : description,
      songs: picked,
    );
    return {
      'created': true,
      'id': created.id,
      'name': created.name,
      'added': picked.length,
      'skipped': skipped,
    };
  }

  Future<Object?> _runUpdatePlaylist(Map<String, dynamic> args) async {
    final query = _playlistQuery(args);
    if (query.isEmpty) return {'error': '需要 playlist'};
    final playlist = await playlists.findPlaylist(query);
    if (playlist == null) return {'error': '没有找到这个歌单'};
    final name = (args['name'] ?? '').toString().trim();
    final description = (args['description'] ?? '').toString().trim();
    if (name.isEmpty && description.isEmpty) {
      return {'error': '需要 name 或 description'};
    }
    final updated = await playlists.update(
      id: playlist.id,
      name: name.isEmpty ? null : name,
      description: description.isEmpty ? null : description,
    );
    return {'ok': true, 'id': updated.id, 'name': updated.name};
  }

  Future<Object?> _runDeletePlaylist(Map<String, dynamic> args) async {
    final query = _playlistQuery(args);
    if (query.isEmpty) return {'error': '需要 playlist'};
    final playlist = await playlists.findPlaylist(query);
    if (playlist == null) return {'error': '没有找到这个歌单'};
    if (_systemPlaylistIds.contains(playlist.id)) {
      return {'error': '系统歌单不能删除'};
    }
    await playlists.delete(playlist.id);
    return {'deleted': true, 'id': playlist.id, 'name': playlist.name};
  }

  Future<Object?> _runAddSongs(Map<String, dynamic> args) async {
    final query = _playlistQuery(args);
    if (query.isEmpty) return {'error': '需要 playlist'};
    final playlist = await playlists.findPlaylist(query);
    if (playlist == null) return {'error': '没有找到这个歌单'};
    final (picked, skipped) = await _resolveMany(args['songs']);
    if (picked.isEmpty) {
      return {'error': '这些歌在曲库里都没找到', 'skipped': skipped};
    }
    final added = await playlists.addSongs(playlist.id, picked);
    return {
      'ok': true,
      'playlist': playlist.name,
      'added': added,
      'skipped': skipped,
    };
  }

  Future<Object?> _runRemoveSongs(Map<String, dynamic> args) async {
    final query = _playlistQuery(args);
    if (query.isEmpty) return {'error': '需要 playlist'};
    final playlist = await playlists.findPlaylist(query);
    if (playlist == null) return {'error': '没有找到这个歌单'};
    final rawSongs = args['songs'];
    if (rawSongs is! List || rawSongs.isEmpty) {
      return {'error': 'songs 不能为空'};
    }
    final existing = await playlists.songsOf(playlist.id);
    final tokens = <String>[];
    final missing = <String>[];
    for (final raw in rawSongs.take(_maxSongsPerCall)) {
      final directId = raw is Map ? (raw['id'] ?? '').toString().trim() : '';
      if (directId.isNotEmpty) {
        tokens.add(directId);
        continue;
      }
      final (title, artist) = _songRequestOf(raw);
      if (title.isEmpty) continue;
      final matched = _matchInPlaylist(existing, title, artist);
      if (matched == null) {
        missing.add(artist.isEmpty ? title : '$title · $artist');
      } else {
        tokens.add(matched.playlistItemId ?? matched.identityKey);
      }
    }
    if (tokens.isEmpty) {
      return {'error': '歌单里没有这些歌', 'missing': missing};
    }
    final removed = await playlists.removeSongs(playlist.id, tokens);
    return {
      'ok': true,
      'playlist': playlist.name,
      'removed': removed,
      'missing': missing,
    };
  }

  Future<Object?> _runSortPlaylist(Map<String, dynamic> args) async {
    final query = _playlistQuery(args);
    if (query.isEmpty) return {'error': '需要 playlist'};
    final playlist = await playlists.findPlaylist(query);
    if (playlist == null) return {'error': '没有找到这个歌单'};
    final by = switch ((args['by'] ?? '').toString().trim().toLowerCase()) {
      'name' || 'title' => AiPlaylistSortBy.name,
      'artist' || 'singer' => AiPlaylistSortBy.artist,
      'duration' || 'time' => AiPlaylistSortBy.duration,
      _ => null,
    };
    if (by == null) return {'error': 'by 只能是 name / artist / duration'};
    final ascending = args['ascending'] != false;
    final changed = await playlists.sort(playlist.id, by, ascending: ascending);
    return {
      'ok': true,
      'playlist': playlist.name,
      'changed': changed,
      'by': by.name,
    };
  }

  Future<Object?> _runSetFavorite(Map<String, dynamic> args) async {
    final favorite = args['favorite'] != false;
    final songs = <MusicItem>[];
    final skipped = <String>[];
    if (args['current_song'] == true) {
      final current = playback.currentSong;
      if (current == null) return {'error': '当前没有播放中的歌曲'};
      songs.add(current);
    } else {
      final (picked, missing) = await _resolveMany(args['songs']);
      songs.addAll(picked);
      skipped.addAll(missing);
    }
    if (songs.isEmpty) {
      return {'error': '没有可操作的歌曲', 'skipped': skipped};
    }
    final changed = <String>[];
    for (final song in songs) {
      final wasFavorite = await playlists.isFavorite(song);
      if (wasFavorite == favorite) continue;
      await playlists.setFavorite(song, favorite);
      changed.add(song.name);
    }
    return {
      'ok': true,
      'favorite': favorite,
      'changed': changed,
      'unchanged': songs.length - changed.length,
      'skipped': skipped,
    };
  }

  // ------------------------------------------------------------------ 下载

  Future<Object?> _runDownloadSongs(Map<String, dynamic> args) async {
    var picked = <MusicItem>[];
    var skipped = <String>[];
    if (args['songs'] is List) {
      final (resolved, missing) = await _resolveMany(args['songs']);
      picked = resolved;
      skipped = missing;
    } else {
      final query = _playlistQuery(args);
      if (query.isEmpty) return {'error': '需要 songs 或 playlist'};
      final playlist = await playlists.findPlaylist(query);
      if (playlist == null) return {'error': '没有找到这个歌单'};
      final songs = await playlists.songsOf(playlist.id);
      picked = songs.take(_maxSongsPerCall).toList(growable: false);
      if (songs.length > picked.length) {
        skipped.add('还有 ${songs.length - picked.length} 首未加入，请再调用一次');
      }
    }
    if (picked.isEmpty) {
      return {'error': '没有可下载的歌曲', 'skipped': skipped};
    }
    await downloads.add(picked);
    return {'queued': picked.length, 'skipped': skipped};
  }

  Future<Object?> _runDeleteDownload(Map<String, dynamic> args) async {
    final taskId = (args['task_id'] ?? '').toString().trim();
    final title = (args['title'] ?? '').toString().trim();
    if (taskId.isEmpty && title.isEmpty) return {'error': '需要 task_id 或 title'};
    String? foundId;
    String? foundTitle;
    for (final task in downloads.tasks) {
      final matched = taskId.isNotEmpty
          ? task.id == taskId
          : _normalize(task.name).contains(_normalize(title));
      if (!matched) continue;
      foundId = task.id;
      foundTitle = task.name;
      break;
    }
    if (foundId == null) return {'error': '没有找到这个下载任务'};
    await downloads.remove(foundId);
    return {'deleted': true, 'id': foundId, 'title': foundTitle};
  }

  Future<Object?> _runClearDownloadCache(Map<String, dynamic> _) async {
    await downloads.clearCache();
    return {'ok': true};
  }

  // ------------------------------------------------------------------ 音源

  Future<Object?> _runToggleSource(Map<String, dynamic> args) async {
    final query = (args['source'] ?? '').toString().trim();
    if (query.isEmpty) return {'error': '需要 source'};
    final source = _findSource(query);
    if (source == null) return {'error': '没有找到这个音源脚本'};
    final enabled = args['enabled'] != false;
    if (source.isEnabled != enabled) {
      await sources.toggle(source.id);
    }
    return {'id': source.id, 'name': source.name, 'enabled': enabled};
  }

  Future<Object?> _runRunSourceCheck(Map<String, dynamic> args) async {
    final query = (args['source'] ?? '').toString().trim();
    if (query.isEmpty) {
      await sources.runCheck(null);
    } else {
      final source = _findSource(query);
      if (source == null) return {'error': '没有找到这个音源脚本'};
      await sources.runCheck(source.id);
    }
    return _runSourceStatus(const {});
  }

  // ------------------------------------------------------------- 猜你喜欢

  Future<Object?> _runGetRecommendations(Map<String, dynamic> args) async {
    final limit = _intOf(args['limit'], fallback: 15).clamp(1, 30);
    final songs = recommendations.current;
    return {
      'ready': recommendations.hasData,
      'total': songs.length,
      'tuning': recommendations.tuning.toJson(),
      if (recommendations.tuning.isNotEmpty)
        'tuningSummary': recommendations.tuning.describe(),
      'songs': [
        for (final item in songs.take(limit)) _recommendedJson(item),
      ],
      if (!recommendations.hasData)
        'note': '推荐还没算好（收藏达到 100 首才会生成），可以先让用户多收藏一些歌',
    };
  }

  Future<Object?> _runEditRecommendations(Map<String, dynamic> args) async {
    var tuning = recommendations.tuning;
    final cleared = _tuningSections(args['clear']);
    if (cleared.isNotEmpty) tuning = tuning.cleared(cleared);

    final pinned = _songRefsOf(args['pin']);
    if (pinned.isNotEmpty) tuning = tuning.withPinned(pinned);
    final excluded = _songRefsOf(args['exclude']);
    if (excluded.isNotEmpty) tuning = tuning.withExcludedSongs(excluded);
    final artists = [
      if (args['exclude_artists'] case final List raw)
        for (final item in raw) item.toString().trim(),
    ].where((item) => item.isNotEmpty).toList(growable: false);
    if (artists.isNotEmpty) tuning = tuning.withExcludedArtists(artists);
    if (args.containsKey('focus')) {
      tuning = tuning.withFocus(args['focus']?.toString() ?? '');
    }

    if (cleared.isEmpty &&
        pinned.isEmpty &&
        excluded.isEmpty &&
        artists.isEmpty &&
        !args.containsKey('focus')) {
      return {
        'error': '没有要改的内容',
        'hint': 'pin / exclude / exclude_artists / focus / clear 至少给一个',
        'tuning': tuning.toJson(),
      };
    }

    final result = await recommendations.apply(tuning);
    return {
      'ok': true,
      'tuning': tuning.toJson(),
      'summary': tuning.describe(),
      'total': result.length,
      'top': [for (final item in result.take(10)) _recommendedJson(item)],
      if (result.isEmpty)
        'note': '推荐还是空的：收藏不足 100 首时算法不会生成推荐，置顶的歌也搜不到',
    };
  }

  static Set<TuningSection> _tuningSections(Object? raw) {
    if (raw is! List) return const {};
    final sections = <TuningSection>{};
    for (final item in raw.take(6)) {
      switch (item.toString().trim().toLowerCase()) {
        case 'pinned' || 'pin' || 'tops':
          sections.add(TuningSection.pinned);
        case 'excluded' || 'exclude' || 'songs' || 'blocked':
          sections.add(TuningSection.excluded);
        case 'artists' || 'artist':
          sections.add(TuningSection.artists);
        case 'focus' || 'taste':
          sections.add(TuningSection.focus);
        case 'all' || '*':
          sections.add(TuningSection.all);
      }
    }
    return sections;
  }

  static List<SongRef> _songRefsOf(Object? raw) {
    if (raw is! List) return const [];
    return [
      for (final item in raw.take(_maxSongsPerCall))
        if (SongRef.fromJson(item) case final ref?) ref,
    ];
  }

  static Map<String, dynamic> _recommendedJson(RecommendedSong item) => {
    ..._songJson(item.song),
    'score': double.parse(item.score.toStringAsFixed(3)),
    if (item.reasons.isNotEmpty) 'reasons': item.reasons,
  };

  // ------------------------------------------------------------------ 设置

  Future<Object?> _runSetAppSetting(Map<String, dynamic> args) async {
    final key = (args['key'] ?? '').toString().trim();
    final value = args['value'];
    const qualities = {'low', 'high', 'lossless', 'lossless24', 'hires'};
    switch (key) {
      case 'audio_quality':
        final token = value.toString().trim();
        if (!qualities.contains(token)) {
          return {'error': 'audio_quality 只能是 ${qualities.join(' / ')}'};
        }
        await settings.setAudioQuality(token);
        return {'key': key, 'value': settings.audioQuality};
      case 'download_quality':
        final token = value.toString().trim();
        if (!qualities.contains(token)) {
          return {'error': 'download_quality 只能是 ${qualities.join(' / ')}'};
        }
        await settings.setDownloadQuality(token);
        return {'key': key, 'value': settings.downloadQuality};
      case 'wifi_only_download':
        // schema 声明成 string，所以模型多半传 "true"/"false"；也兼容真的布尔。
        final flag = value is bool
            ? value
            : switch (value?.toString().trim().toLowerCase()) {
                'true' || '1' || 'on' || 'yes' => true,
                'false' || '0' || 'off' || 'no' => false,
                _ => null,
              };
        if (flag == null) {
          return {'error': 'wifi_only_download 需要 true 或 false'};
        }
        await settings.setWifiOnlyDownload(flag);
        return {'key': key, 'value': settings.wifiOnlyDownload};
      case 'theme':
        final mode = value.toString().trim();
        if (!const {'system', 'light', 'dark'}.contains(mode)) {
          return {'error': 'theme 只能是 system / light / dark'};
        }
        await settings.setThemeMode(mode);
        return {'key': key, 'value': settings.themeMode};
      default:
        return {
          'error': '未知设置项：$key',
          'keys': [
            'audio_quality',
            'download_quality',
            'wifi_only_download',
            'theme',
          ],
        };
    }
  }

  // ------------------------------------------------------------ 声音与偏好

  Future<Object?> _runGetEqualizer(Map<String, dynamic> _) async =>
      _equalizerJson();

  Future<Object?> _runSetEqualizer(Map<String, dynamic> args) async {
    if (!equalizer.supported) return {'error': '这个平台上没有可用的均衡器'};

    final wantsReset = args['reset'] == true;
    final enabled = args['enabled'];
    final preset = (args['preset'] ?? '').toString().trim();
    final bands = args['bands'];
    if (wantsReset) {
      await equalizer.resetFlat();
    }
    if (preset.isNotEmpty) {
      final known = equalizer.presets.map((item) => item.id).toSet();
      if (!known.contains(preset)) {
        return {'error': '没有这个预设：$preset', 'presets': known.toList()};
      }
      await equalizer.selectPreset(preset);
    }
    final skipped = <String>[];
    if (bands is List) {
      for (final raw in bands.take(16)) {
        if (raw is! Map) continue;
        final hz = _doubleOf(raw['hz'] ?? raw['frequency']);
        final gain = _doubleOf(raw['gain_db'] ?? raw['gain'] ?? raw['db']);
        if (hz == null || gain == null) {
          skipped.add(raw.toString());
          continue;
        }
        final applied = await equalizer.setBandGain(hz, gain);
        if (!applied) skipped.add('${hz.round()}Hz');
      }
    }
    if (enabled is bool) await equalizer.setEnabled(enabled);
    return {
      ..._equalizerJson(),
      if (skipped.isNotEmpty) 'skipped': skipped,
    };
  }

  Map<String, dynamic> _equalizerJson() {
    final bands = equalizer.bands;
    return {
      'supported': equalizer.supported,
      'enabled': equalizer.enabled,
      'preset': equalizer.presetId,
      'presets': [for (final item in equalizer.presets) item.id],
      'range': {
        'min_db': equalizer.minDecibels,
        'max_db': equalizer.maxDecibels,
      },
      'bands': [
        for (final band in bands)
          {
            'hz': band.frequencyHz.round(),
            'gain_db': double.parse(band.gainDb.toStringAsFixed(1)),
          },
      ],
    };
  }

  // ---------------------------------------------------------------- 洞察

  Future<Object?> _runListeningStats(Map<String, dynamic> args) async {
    final range = _statsRange(args['range']);
    final limit = _intOf(args['limit'], fallback: 10).clamp(1, 20);
    final snapshot = stats.snapshot(range, limit: limit);
    return {
      'range': snapshot.range,
      'playCount': snapshot.playCount,
      'minutes': (snapshot.totalSeconds / 60).round(),
      'activeDays': snapshot.activeDays,
      'topSongs': [for (final item in snapshot.songs) _rankedJson(item)],
      'topArtists': [for (final item in snapshot.artists) _rankedJson(item)],
      'topAlbums': [for (final item in snapshot.albums) _rankedJson(item)],
    };
  }

  Future<Object?> _runLyrics(Map<String, dynamic> args) async {
    final wantsCurrent =
        args['current_song'] == true ||
        (args['title'] ?? '').toString().trim().isEmpty;
    final maxLines = _intOf(args['max_lines'], fallback: 60).clamp(1, 200);

    MusicItem? song;
    if (wantsCurrent) {
      song = playback.currentSong;
      if (song == null) {
        return {'error': '现在没有播放中的歌曲；也可以给 title 和 artist 指定一首'};
      }
    } else {
      song = await _resolve(
        (args['title'] ?? '').toString().trim(),
        (args['artist'] ?? '').toString().trim(),
      );
      if (song == null) return {'error': '没找到这首歌'};
    }

    final lines = await lyrics.lyricsOf(song);
    if (lines == null || lines.isEmpty) {
      return {'error': '这首歌没有取到歌词', ..._songJson(song)};
    }
    return {
      ..._songJson(song),
      'lines': [
        for (final line in lines.take(maxLines))
          {'at': line.seconds, 'text': line.text},
      ],
      'total': lines.length,
    };
  }

  // ---------------------------------------------------------------- 榜单

  Future<Object?> _runListCharts(Map<String, dynamic> args) async {
    final platform = (args['platform'] ?? '').toString().trim();
    final list = await charts.charts(platform: platform.isEmpty ? null : platform);
    return {
      'charts': [
        for (final item in list)
          {'id': item.id, 'name': item.name, 'platform': item.platform},
      ],
    };
  }

  Future<Object?> _runPlayChart(Map<String, dynamic> args) async {
    final query = (args['chart'] ?? '').toString().trim();
    if (query.isEmpty) return {'error': '需要 chart'};
    final index = _intOf(args['index'], fallback: 0).clamp(0, 9999);

    final list = await charts.charts();
    final lowered = query.toLowerCase();
    AiChartEntry? match;
    for (final item in list) {
      if (item.id == query) {
        match = item;
        break;
      }
    }
    match ??= () {
      for (final item in list) {
        if (item.name.toLowerCase() == lowered) return item;
      }
      for (final item in list) {
        if (item.name.toLowerCase().contains(lowered)) return item;
      }
      return null;
    }();
    if (match == null) return {'error': '没有这个榜单：$query'};

    final songs = await charts.songsOf(match.id);
    if (songs.isEmpty) return {'error': '这个榜单没有取到歌曲', 'chart': match.name};
    final start = index >= songs.length ? 0 : index;
    await playback.playSongs(songs, index: start);
    return {
      'chart': match.name,
      'total': songs.length,
      'startedAt': start,
      'firstSong': _songJson(songs[start]),
    };
  }

  // ------------------------------------------------------------ 定时任务

  Future<Object?> _runListSchedules(Map<String, dynamic> _) async => {
    'schedules': [
      for (final task in schedules.tasks)
        {
          'id': task.id,
          'title': task.title,
          'prompt': task.prompt,
          'time': _hhmm(task.minuteOfDay),
          'cadence': task.cadence.name,
          if (task.cadence == AiScheduleCadence.weekly)
            'weekday': task.weekday,
          'enabled': task.enabled,
          if (task.lastRunAt case final at?) 'lastRunAt': at.toIso8601String(),
          if (task.lastOk case final ok?) 'lastOk': ok,
          if ((task.lastResult ?? '').isNotEmpty) 'lastResult': task.lastResult,
          if ((task.lastFailure ?? '').isNotEmpty)
            'lastFailure': task.lastFailure,
        },
    ],
  };

  Future<Object?> _runManageSchedule(Map<String, dynamic> args) async {
    final action = (args['action'] ?? '').toString().trim();
    final id = (args['id'] ?? '').toString().trim();

    switch (action) {
      case 'create':
        final title = (args['title'] ?? '').toString().trim();
        final prompt = (args['prompt'] ?? '').toString().trim();
        if (title.isEmpty || prompt.isEmpty) {
          return {'error': 'create 需要 title 和 prompt'};
        }
        final minute = _parseMinuteOfDay(args['time']);
        if (minute == null) {
          return {'error': 'time 要写成 HH:mm，例如 08:00'};
        }
        final cadence = _scheduleCadence(args['cadence']);
        if (cadence == null) {
          return {'error': 'cadence 只能是 daily / weekdays / weekly'};
        }
        if (cadence == AiScheduleCadence.weekly) {
          final weekday = _intOf(args['weekday'], fallback: 0);
          if (weekday < 1 || weekday > 7) {
            return {'error': 'weekly 需要 weekday，1=周一 … 7=周日'};
          }
        }
        if (schedules.tasks.length >= 20) {
          return {'error': '定时任务最多 20 个，先删掉一些'};
        }
        final created = await schedules.create(
          title: title,
          prompt: prompt,
          minuteOfDay: minute,
          cadence: cadence.name,
          weekday: cadence == AiScheduleCadence.weekly
              ? _intOf(args['weekday'], fallback: 1)
              : null,
        );
        if (created == null) return {'error': '没有建成，稍后再试'};
        return {
          'created': created.id,
          'title': created.title,
          'time': _hhmm(created.minuteOfDay),
          'cadence': created.cadence.name,
        };
      case 'run':
      case 'pause':
      case 'resume':
      case 'remove':
        if (id.isEmpty) return {'error': '$action 需要 id'};
        if (!schedules.tasks.any((task) => task.id == id)) {
          return {'error': '没有这个任务：$id'};
        }
        if (action == 'remove') {
          final removed = await schedules.remove(id);
          return removed ? {'removed': id} : {'error': '删除失败'};
        }
        if (action == 'pause' || action == 'resume') {
          final enabled = action == 'resume';
          final ok = await schedules.setEnabled(id, enabled);
          return ok ? {'id': id, 'enabled': enabled} : {'error': '改不了这个任务'};
        }
        final result = await schedules.runNow(id);
        return {
          'id': id,
          'ok': result.ok,
          'result': result.summary,
        };
      default:
        return {
          'error': '未知 action：$action',
          'actions': ['create', 'run', 'pause', 'resume', 'remove'],
        };
    }
  }

  Future<Object?> _runRescanLocal(Map<String, dynamic> _) async {
    final added = await local.rescan();
    return {'added': added};
  }

  Future<Object?> _runWriteLocalTags(Map<String, dynamic> args) async {
    final songId = (args['song_id'] ?? '').toString().trim();
    if (songId.isEmpty) return {'error': 'song_id 不能为空'};
    String? field(String key) {
      final value = args[key];
      return value?.toString().trim();
    }

    final title = field('title');
    final artist = field('artist');
    final album = field('album');
    if (title == null && artist == null && album == null) {
      return {'error': '至少给一个要改的字段：title / artist / album'};
    }
    final result = await local.writeTags(
      songId,
      title: title,
      artist: artist,
      album: album,
    );
    if (!result.success) return {'error': result.error ?? '写入失败'};
    return {
      'ok': true,
      'file': result.fileName,
      'title': result.title,
      'artist': result.artist,
      'album': result.album,
    };
  }

  static String _hhmm(int minuteOfDay) {
    final minutes = minuteOfDay % (24 * 60);
    final hour = (minutes ~/ 60).toString().padLeft(2, '0');
    final minute = (minutes % 60).toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  static int? _parseMinuteOfDay(Object? raw) {
    final text = (raw ?? '').toString().trim();
    if (text.isEmpty) return null;
    final match = RegExp(r'^(\d{1,2})\s*[:：]\s*(\d{1,2})$').firstMatch(text);
    if (match == null) return null;
    final hour = int.tryParse(match.group(1)!);
    final minute = int.tryParse(match.group(2)!);
    if (hour == null || minute == null) return null;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
    return hour * 60 + minute;
  }

  static AiScheduleCadence? _scheduleCadence(Object? raw) {
    final text = (raw ?? '').toString().trim().toLowerCase();
    return switch (text) {
      '' || 'daily' => AiScheduleCadence.daily,
      'weekdays' || 'weekday' => AiScheduleCadence.weekdays,
      'weekly' || 'week' => AiScheduleCadence.weekly,
      _ => null,
    };
  }

  static String _statsRange(Object? raw) {
    final text = (raw ?? '').toString().trim().toLowerCase();
    return switch (text) {
      'month' || '本月' => 'month',
      'year' || '今年' => 'year',
      'all' || '全部' => 'all',
      _ => 'week',
    };
  }

  static Map<String, dynamic> _rankedJson(AiRankedEntry item) => {
    'title': item.title,
    if (item.subtitle.isNotEmpty) 'subtitle': item.subtitle,
    'playCount': item.playCount,
    'minutes': (item.totalSeconds / 60).round(),
  };

  // ------------------------------------------------------------------ 内部

  CustomSource? _findSource(String query) {
    final value = query.trim().toLowerCase();
    for (final source in sources.sources) {
      if (source.id == query || source.name.toLowerCase() == value) {
        return source;
      }
    }
    for (final source in sources.sources) {
      if (source.name.toLowerCase().contains(value)) return source;
    }
    return null;
  }

  static const Set<String> _systemPlaylistIds = {
    'favorites',
    'recent',
    'local',
  };

  static String _playlistQuery(Map<String, dynamic> args) =>
      (args['playlist'] ?? '').toString().trim();

  /// 逐首解析模型给的歌曲，返回（找得到的，没找到的）。
  Future<(List<MusicItem>, List<String>)> _resolveMany(Object? rawSongs) async {
    if (rawSongs is! List || rawSongs.isEmpty) {
      return (const <MusicItem>[], const <String>[]);
    }
    final picked = <MusicItem>[];
    final skipped = <String>[];
    for (final raw in rawSongs.take(_maxSongsPerCall)) {
      final (title, artist) = _songRequestOf(raw);
      if (title.isEmpty) continue;
      final directId = raw is Map ? (raw['id'] ?? '').toString().trim() : '';
      final match = directId.isNotEmpty
          ? await _resolveById(directId, title)
          : await _resolve(title, artist);
      if (match == null) {
        skipped.add(artist.isEmpty ? title : '$title · $artist');
      } else if (!picked.any((item) => item.identityKey == match.identityKey)) {
        picked.add(match);
      }
    }
    return (picked, skipped);
  }

  /// 给了 id 也仍走一次搜索，避免拿到一个曲库里已经不存在的旧 id。
  Future<MusicItem?> _resolveById(String id, String title) async {
    final list = await search(title, 10);
    for (final item in list) {
      if (item.id == id || item.identityKey == id) return item;
    }
    return _resolve(title, '');
  }

  /// 挑最像的一版：同名优先，其次包含关系；歌手对得上再加一档。
  Future<MusicItem?> _resolve(String title, String artist) async {
    final list = await search(artist.isEmpty ? title : '$title $artist', 10);
    if (list.isEmpty) return null;
    final wantTitle = _normalize(title);
    final wantArtist = _normalize(artist);
    MusicItem? best;
    var bestScore = 0.0;
    for (final item in list) {
      final itemTitle = _normalize(item.name);
      if (itemTitle.isEmpty) continue;
      final artistHit =
          wantArtist.isEmpty ||
          _normalize(item.singer).contains(wantArtist) ||
          wantArtist.contains(_normalize(item.singer));
      double score;
      if (itemTitle == wantTitle) {
        score = wantArtist.isEmpty ? 0.9 : (artistHit ? 1.0 : 0.75);
      } else if (itemTitle.contains(wantTitle) ||
          wantTitle.contains(itemTitle)) {
        score = artistHit ? 0.6 : 0.4;
      } else {
        score = 0;
      }
      if (score > bestScore) {
        bestScore = score;
        best = item;
      }
    }
    return bestScore >= 0.6 ? best : null;
  }

  static MusicItem? _matchInPlaylist(
    List<MusicItem> songs,
    String title,
    String artist,
  ) {
    final wantTitle = _normalize(title);
    final wantArtist = _normalize(artist);
    for (final song in songs) {
      final songTitle = _normalize(song.name);
      final titleHit =
          songTitle == wantTitle ||
          songTitle.contains(wantTitle) ||
          wantTitle.contains(songTitle);
      if (!titleHit) continue;
      if (wantArtist.isEmpty) return song;
      final singer = _normalize(song.singer);
      if (singer.contains(wantArtist) || wantArtist.contains(singer)) {
        return song;
      }
    }
    return null;
  }

  static final _noise = RegExp(r'''[\s\-_·•,，.。!！?？:：;；()（）\[\]【】「」《》"'’“”]''');

  static String _normalize(String value) =>
      value.toLowerCase().replaceAll(_noise, '');

  static (String, String) _songRequestOf(Object? raw) {
    if (raw is String) return (raw.trim(), '');
    if (raw is! Map) return ('', '');
    final title = (raw['title'] ?? raw['name'] ?? '').toString().trim();
    final artist = (raw['artist'] ?? raw['singer'] ?? '').toString().trim();
    return (title, artist);
  }

  static int _intOf(Object? value, {required int fallback}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  static double? _doubleOf(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  static String _repeatLabel(String mode) => switch (mode) {
    'all' => '列表循环',
    'one' => '单曲循环',
    _ => '顺序播放',
  };

  static Map<String, dynamic> _songJson(MusicItem item) => {
    'id': item.id,
    'title': item.name,
    'artist': item.singer,
    if (item.album.isNotEmpty) 'album': item.album,
    'platform': item.platform,
  };
}

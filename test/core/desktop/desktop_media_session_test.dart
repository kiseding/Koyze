// Copyright 2024 Koyze Contributors
// Licensed under the Apache License, Version 2.0

import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/desktop/desktop_media_channel.dart';
import 'package:koyze/core/desktop/desktop_media_session.dart';

class _FakeSource implements DesktopMediaSource {
  final StreamController<MediaItem?> items = StreamController<MediaItem?>.broadcast();
  final StreamController<PlaybackState> states =
      StreamController<PlaybackState>.broadcast();
  final StreamController<void> jumps = StreamController<void>.broadcast();

  final List<String> actions = <String>[];
  MediaItem? item;
  PlaybackState? state;
  @override
  Duration position = Duration.zero;

  @override
  Duration? duration;

  @override
  Stream<MediaItem?> get mediaItemStream => items.stream;

  @override
  Stream<PlaybackState> get playbackStateStream => states.stream;

  @override
  Stream<void> get positionJumpStream => jumps.stream;

  @override
  MediaItem? get currentItem => item;

  @override
  PlaybackState? get currentState => state;

  @override
  Future<void> play() async => actions.add('play');

  @override
  Future<void> pause() async => actions.add('pause');

  @override
  Future<void> seek(Duration position) async {
    actions.add('seek:${position.inMilliseconds}');
    this.position = position;
  }

  @override
  Future<void> skipToNext() async => actions.add('next');

  @override
  Future<void> skipToPrevious() async => actions.add('previous');

  void emitItem(MediaItem value) {
    item = value;
    items.add(value);
  }

  void emitState(PlaybackState value) {
    state = value;
    states.add(value);
  }

  Future<void> close() async {
    await items.close();
    await states.close();
    await jumps.close();
  }
}

class _FakeChannel implements DesktopMediaChannel {
  final List<({String method, Object? arguments})> calls =
      <({String method, Object? arguments})>[];
  DesktopMediaCommandHandler? handler;
  bool failInitialize = false;

  @override
  Future<void> invoke(String method, [Object? arguments]) async {
    calls.add((method: method, arguments: arguments));
    if (failInitialize && method == 'initialize') {
      throw PlatformException(code: 'unavailable');
    }
  }

  @override
  void setCommandHandler(DesktopMediaCommandHandler? handler) {
    this.handler = handler;
  }

  List<Object?> argumentsOf(String method) => calls
      .where((call) => call.method == method)
      .map((call) => call.arguments)
      .toList();

  int countOf(String method) =>
      calls.where((call) => call.method == method).length;
}

MediaItem _item({
  String id = 'a',
  String title = '春不晚',
  String artist = '某歌手',
}) {
  return MediaItem(
    id: id,
    title: title,
    artist: artist,
    album: '专辑',
    duration: const Duration(seconds: 215),
  );
}

void main() {
  late _FakeSource source;
  late _FakeChannel channel;
  late DesktopMediaSession session;

  setUp(() {
    source = _FakeSource();
    channel = _FakeChannel();
    session = DesktopMediaSession(source: source, channel: channel);
  });

  tearDown(() async {
    await session.dispose();
    await source.close();
  });

  test('没有在播歌曲时只通知系统清空', () async {
    await session.init();

    expect(channel.calls.first.method, 'initialize');
    expect(channel.countOf('clear'), 1);
    expect(channel.countOf('update'), 0);
  });

  test('推送给系统的元数据带时长、进度与播放状态', () async {
    source.item = _item();
    source.duration = const Duration(seconds: 215);
    source.position = const Duration(seconds: 12);
    source.state = PlaybackState(
      playing: true,
      controls: const [MediaControl.skipToNext, MediaControl.skipToPrevious],
    );

    await session.init();

    final payload = channel.argumentsOf('update').single as Map;
    expect(payload['title'], '春不晚');
    expect(payload['artist'], '某歌手');
    expect(payload['album'], '专辑');
    expect(payload['durationMs'], 215000);
    expect(payload['positionMs'], 12000);
    expect(payload['playing'], isTrue);
    expect(payload['canGoNext'], isTrue);
    expect(payload['canGoPrevious'], isTrue);
    expect(payload['sampledAtMs'], isA<int>());
  });

  test('进度会被夹在时长以内', () async {
    source.item = _item();
    source.duration = const Duration(seconds: 100);
    source.position = const Duration(seconds: 180);

    await session.init();

    final payload = channel.argumentsOf('update').single as Map;
    expect(payload['positionMs'], 100000);
  });

  test('切歌时立即重推，且不再重复推同一首', () async {
    source.item = _item();
    await session.init();
    expect(channel.countOf('update'), 1);

    source.emitItem(_item(id: 'b', title: '第二首'));
    await pumpEventQueue();

    final payloads = channel.argumentsOf('update').cast<Map>();
    expect(payloads.length, 2);
    expect(payloads.last['title'], '第二首');
  });

  test('系统命令落到播放器并在结束后补推状态', () async {
    source.item = _item();
    source.state = PlaybackState(playing: false);
    await session.init();
    final before = channel.countOf('update');

    await channel.handler!((method: 'playPause', arguments: null));
    expect(source.actions, ['play']);
    expect(channel.countOf('update'), before + 1);

    source.emitState(PlaybackState(playing: true));
    await pumpEventQueue();
    await channel.handler!((method: 'playPause', arguments: null));
    expect(source.actions, ['play', 'pause']);
  });

  test('相对拖动按当前位置偏移并夹在区间内', () async {
    source.item = _item();
    source.duration = const Duration(seconds: 100);
    source.position = const Duration(seconds: 10);
    await session.init();

    await channel.handler!((method: 'seek', arguments: 5000));
    expect(source.actions.last, 'seek:15000');

    await channel.handler!((method: 'seek', arguments: -90000));
    expect(source.actions.last, 'seek:0');

    await channel.handler!((method: 'seek', arguments: 999000));
    expect(source.actions.last, 'seek:100000');
  });

  test('绝对跳转与停止命令可用', () async {
    source.item = _item();
    await session.init();

    await channel.handler!((method: 'setPosition', arguments: 42000));
    expect(source.actions.last, 'seek:42000');

    await channel.handler!((method: 'stop', arguments: null));
    expect(source.actions.sublist(source.actions.length - 2), [
      'pause',
      'seek:0',
    ]);
  });

  test('原生未实现时静默降级，不抛给调用方', () async {
    channel.failInitialize = true;
    source.item = _item();

    await session.init();

    expect(channel.countOf('update'), 0);
    expect(channel.handler, isNotNull, reason: '仍然保留命令入口');
  });

  testWidgets('播放中每秒推一次进度，暂停后停止', (tester) async {
    source.item = _item();
    source.duration = const Duration(seconds: 215);
    source.state = PlaybackState(playing: true);
    await session.init();
    final playingPushes = channel.countOf('update');

    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(
      channel.countOf('update'),
      greaterThan(playingPushes),
      reason: '播放中应有周期推送',
    );

    source.emitState(PlaybackState(playing: false));
    await tester.pump();
    final pausedPushes = channel.countOf('update');
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(channel.countOf('update'), pausedPushes, reason: '暂停后不再定时推');
  });
}

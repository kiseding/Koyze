import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/audio/audio_handler.dart';
import 'package:koyze/core/audio/audio_spectrum.dart';
import 'package:koyze/features/player/domain/player_spectrum_settings.dart';
import 'package:koyze/features/player/presentation/widgets/player_spectrum_painter.dart';
import 'package:koyze/features/player/presentation/widgets/player_spectrum_strip.dart';
import 'package:rxdart/rxdart.dart';

/// 频谱条的挂载、订阅、卸载与减弱动效。
///
/// 这里不碰真实引擎：mpv 的 FFT 管线在测试环境里不存在，而这条 widget 的
/// 价值恰恰在于「拿不到引擎时也不能崩、不能占位」，所以用合成源验证更彻底。
class _FakeSpectrumSource implements AudioSpectrumSource {
  _FakeSpectrumSource({this.available = true});

  @override
  final bool available;

  final StreamController<SpectrumFrame> _controller =
      StreamController<SpectrumFrame>.broadcast();

  int disposeCount = 0;

  @override
  Stream<SpectrumFrame> get frames => _controller.stream;

  bool get hasListener => _controller.hasListener;

  void emit(List<double> bands) {
    _controller.add(SpectrumFrame(bands: bands));
  }

  @override
  Future<void> dispose() async {
    disposeCount++;
    await _controller.close();
  }
}

class _FakePlaybackHandler implements LxAudioHandler {
  @override
  final mediaItem = BehaviorSubject<MediaItem?>.seeded(null);
  @override
  int? activePlaybackOccurrenceId = 1;

  @override
  bool hasInstalledPositionSource = true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  Widget wrap(Widget child, {bool reduceMotion = false}) {
    return MediaQuery(
      data: MediaQueryData(disableAnimations: reduceMotion),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Center(child: SizedBox(width: 300, child: child)),
      ),
    );
  }

  /// 找出真正画频谱的那个 painter。`CustomPaint` 在 Material 里到处都有，
  /// 只能按 painter 的运行时类型筛。
  bool hasSpectrum(WidgetTester tester) => tester
      .widgetList<CustomPaint>(find.byType(CustomPaint))
      .any((paint) => paint.painter is SpectrumPainter);

  testWidgets('数据源不可用时高度归零，不占任何布局', (tester) async {
    final source = _FakeSpectrumSource(available: false);
    await tester.pumpWidget(wrap(PlayerSpectrumStrip(sourceOverride: source)));

    // 「其它元素不能动」的底线：Web / just_audio 回退时这块必须完全消失，
    // 而不是留一条空白把进度条往下推。（宽度由父约束给，看高度即可。）
    expect(tester.getSize(find.byType(PlayerSpectrumStrip)).height, 0);
    expect(hasSpectrum(tester), isFalse);
  });

  testWidgets('收到帧后画出真实幅值', (tester) async {
    final source = _FakeSpectrumSource();
    await tester.pumpWidget(wrap(PlayerSpectrumStrip(sourceOverride: source)));

    // 还没有数据时画的是空态底纹（一排等高细柱），不是空白——但此时
    // painter 的 display 必须是空的，不能拿假数据糊弄。
    final idle = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((paint) => paint.painter)
        .whereType<SpectrumPainter>()
        .first;
    expect(idle.display, isEmpty);

    source.emit(List<double>.generate(32, (i) => 0.2 + 0.02 * i));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    final live = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((paint) => paint.painter)
        .whereType<SpectrumPainter>()
        .first;
    expect(live.display, hasLength(32));
    expect(tester.getSize(find.byType(PlayerSpectrumStrip)).height, 44);
  });

  testWidgets('首帧超时后隐藏，收到有效帧后恢复', (tester) async {
    final source = _FakeSpectrumSource();
    await tester.pumpWidget(wrap(PlayerSpectrumStrip(sourceOverride: source)));
    source.emit(const []);
    await tester.pump(const Duration(seconds: 3));

    expect(tester.getSize(find.byType(PlayerSpectrumStrip)).height, 0);
    expect(source.hasListener, isTrue);

    source.emit(const [0.4, 0.6]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(hasSpectrum(tester), isTrue);
    expect(tester.getSize(find.byType(PlayerSpectrumStrip)).height, 44);
  });

  testWidgets('切歌立即清空频谱，装源前丢弃残留帧', (tester) async {
    final source = _FakeSpectrumSource();
    final handler = _FakePlaybackHandler();
    const song = MediaItem(id: 'same-song', title: 'Same song');
    handler.mediaItem.add(song);
    await tester.pumpWidget(
      wrap(
        PlayerSpectrumStrip(sourceOverride: source, handlerOverride: handler),
      ),
    );

    SpectrumPainter spectrum() => tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((paint) => paint.painter)
        .whereType<SpectrumPainter>()
        .single;

    source.emit(const [0.9, 0.8]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(spectrum().peak, [0.9, 0.8]);

    handler.mediaItem.add(song.copyWith(title: 'Updated metadata'));
    await tester.pump();
    expect(spectrum().display, [0.9, 0.8]);

    // 队列里连续出现同一首歌时，曲目 ID 一样，队列条目已经切换。
    handler.activePlaybackOccurrenceId = 2;
    handler.hasInstalledPositionSource = false;
    handler.mediaItem.add(song);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(spectrum().display, isEmpty);
    expect(spectrum().peak, isEmpty);

    source.emit(const [0.9, 0.8]);
    await tester.pump();
    expect(spectrum().display, isEmpty);

    handler.hasInstalledPositionSource = true;
    source.emit(const [0.2, 0.3]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(spectrum().display, [0.2, 0.3]);
    expect(spectrum().peak, [0.2, 0.3]);

    await tester.pumpWidget(wrap(const SizedBox.shrink()));
    expect(handler.mediaItem.hasListener, isFalse);
    await handler.mediaItem.close();
  });

  testWidgets('后续帧是补间上来的，不会硬跳', (tester) async {
    final source = _FakeSpectrumSource();
    await tester.pumpWidget(wrap(PlayerSpectrumStrip(sourceOverride: source)));

    // 首帧直接落到目标值：换歌时不希望所有柱子从 0 长一遍。
    source.emit(List<double>.filled(24, 0.2));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    // 第二帧突然满幅：约一个屏幕帧内应明显上升，但不能直接贴满。
    source.emit(List<double>.filled(24, 1));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    final painter = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((paint) => paint.painter)
        .whereType<SpectrumPainter>()
        .first;
    expect(
      painter.display.first,
      lessThan(0.95),
      reason: '一帧就贴到目标值说明补间没生效，视觉上会变成硬跳',
    );
    expect(painter.display.first, greaterThan(0.2), reason: '一点都没动也不对');
  });

  testWidgets('卸载后取消订阅，不再持有流', (tester) async {
    final source = _FakeSpectrumSource();
    await tester.pumpWidget(wrap(PlayerSpectrumStrip(sourceOverride: source)));
    source.emit(const [0.5, 0.5]);
    await tester.pump();
    expect(source.hasListener, isTrue);

    await tester.pumpWidget(wrap(const SizedBox.shrink()));
    await tester.pump();

    // 播放页在导航栈里常驻，只靠 GC 回收不可靠：订阅必须显式取消，
    // 否则离开播放页后 mpv 的 FFT 还在 30Hz 空跑。
    expect(source.hasListener, isFalse);
  });

  testWidgets('减弱动效时只画一条静线，不逐帧重绘', (tester) async {
    final source = _FakeSpectrumSource();
    await tester.pumpWidget(
      wrap(PlayerSpectrumStrip(sourceOverride: source), reduceMotion: true),
    );

    source.emit(List<double>.generate(24, (i) => 0.8));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 32));

    expect(hasSpectrum(tester), isFalse, reason: '开了「减弱动效」还在每帧重绘，等于把系统设置当空气');
    expect(tester.getSize(find.byType(PlayerSpectrumStrip)).height, 44);
  });

  testWidgets('样式切换只换 painter，不重建订阅', (tester) async {
    final source = _FakeSpectrumSource();
    await tester.pumpWidget(wrap(PlayerSpectrumStrip(sourceOverride: source)));
    source.emit(List<double>.generate(16, (i) => 0.4));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    await tester.pumpWidget(
      wrap(
        PlayerSpectrumStrip(sourceOverride: source, style: SpectrumStyle.steps),
      ),
    );
    await tester.pump();

    final styles = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((paint) => paint.painter)
        .whereType<SpectrumPainter>()
        .map((painter) => painter.style);
    expect(styles, contains(SpectrumStyle.steps));
    expect(source.hasListener, isTrue, reason: '换样式不该把数据流断掉');
  });
}

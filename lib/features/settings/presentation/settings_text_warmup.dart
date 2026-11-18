import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'settings_entry.dart';
import 'settings_section_card.dart';

/// 设置页的文本排版预热。
///
/// ## 为什么需要它
///
/// 真机测量（iPhone 17 / 5.2.8，`jank_probe/ios_cold_scroll.py`）显示：冷启动
/// 后第一次拖动设置页，那一秒只有 4~13fps；而同一秒的 GPU 只有 Renderer
/// 5~12%、Tiler 1~4%（平稳滑动时是 30~50%）。也就是说**瓶颈在 UI 线程**，
/// 不是光栅、不是管线编译、不是字形图集。
///
/// 三条对照把范围收窄到「第一次排版」：
///
/// * 进设置后干等 60 秒再滑，照样掉——和启动期的后台任务无关；
/// * 滑过一遍再滑同一片区域就是 60fps——不是每帧都贵；
/// * 继续往没出现过的下半页滑，只有 19~22fps 的轻度掉帧，越往后越轻。
///
/// 所以贵的是那几十行中文**在整个进程里第一次被排版**这一次。`ListView` 是
/// 懒的：首屏之外的三十来行在打开页面时连 Element 都没建，等手指拖到它们才
/// 第一次走 shaping 与字体回退。
///
/// ## 它做什么，不做什么
///
/// 只做一件事：把每个标题/副标题按**真实行的样式**各 layout 一次，让引擎把
/// 字体回退链和 shaping 结果记进缓存。不建树、不绘制、不碰 GPU，也不保留
/// 任何 painter。
///
/// 成本摊在空闲帧上（[Priority.idle]）：只要还有动画或滚动在跑，Scheduler
/// 会优先派帧，这些任务自然往后排，不和用户抢帧。第一块同步跑掉是为了保证
/// 即使后面一直有帧要派（用户一进页面就开始拖），预热也已经有了进展。
class SettingsTextWarmUp {
  const SettingsTextWarmUp._();

  /// 每个空闲任务处理几条。4 条大约 3~8ms，不会把一帧占满。
  static const int _chunkSize = 4;

  /// 进程内只排一次：缓存是引擎级的，第二个设置页实例没有可预热的东西。
  static bool _scheduled = false;

  @visibleForTesting
  static int debugLayouts = 0;

  /// 是否已经排过预热。页面用它判断还要不要再挂一次帧后回调。
  static bool get scheduled => _scheduled;

  @visibleForTesting
  static void resetForTesting() {
    _scheduled = false;
    debugLayouts = 0;
  }

  /// 页面里需要预热一次的字符串：每行的标题与副标题。
  ///
  /// 分区标题不在这里——它只有十条、又短，而且每个分区一进屏就先画出来了。
  @visibleForTesting
  static List<String> stringsFor(List<SettingsSectionSpec> sections) {
    final strings = <String>[];
    for (final section in sections) {
      for (final entry in section.entries) {
        strings.add(entry.title);
        if (entry.subtitle.isNotEmpty) strings.add(entry.subtitle);
      }
    }
    return strings;
  }

  /// 排一次预热。重复调用无效。
  ///
  /// [maxWidth] 只影响断行位置，不影响字体回退与 shaping 的缓存命中，所以
  /// 用一个近似行宽即可，不必精确到像素。
  static void schedule({
    required List<SettingsSectionSpec> sections,
    required TextDirection textDirection,
    required TextScaler textScaler,
    required double maxWidth,
  }) {
    if (_scheduled) return;
    final strings = stringsFor(sections);
    if (strings.isEmpty || maxWidth <= 0) return;
    _scheduled = true;

    final jobs = <(String, TextStyle)>[];
    final titleStyle = settingsRowTitleStyle(const Color(0xFF000000));
    final subtitleStyle = settingsRowSubtitleStyle(const Color(0xFF000000));
    for (final section in sections) {
      for (final entry in section.entries) {
        jobs.add((entry.title, titleStyle));
        if (entry.subtitle.isNotEmpty) {
          jobs.add((entry.subtitle, subtitleStyle));
        }
      }
    }

    void runChunk() {
      final take = math.min(_chunkSize, jobs.length);
      for (var i = 0; i < take; i++) {
        final (text, style) = jobs.removeAt(0);
        _layoutOnce(text, style, textDirection, textScaler, maxWidth);
      }
      if (jobs.isNotEmpty) _scheduleIdle(runChunk);
    }

    // 第一块当场做掉：用户可能在页面画完的下一帧就开始拖，那时如果一条都
    // 还没预热，这次预热就白排了。
    runChunk();
  }

  static void _layoutOnce(
    String text,
    TextStyle style,
    TextDirection textDirection,
    TextScaler textScaler,
    double maxWidth,
  ) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: textDirection,
      textScaler: textScaler,
      maxLines: 2,
      ellipsis: '…',
    );
    try {
      painter.layout(maxWidth: maxWidth);
      debugLayouts++;
    } finally {
      // painter 本身没有复用价值，留着只占内存；要的是引擎侧那份缓存。
      painter.dispose();
    }
  }

  static void _scheduleIdle(VoidCallback task) {
    try {
      SchedulerBinding.instance.scheduleTask<void>(task, Priority.idle);
    } on Object {
      // 没有 binding（纯 Dart 测试、或已经进入销毁流程）就放弃剩下的：
      // 预热只是优化，任何情况下都不该影响页面。
    }
  }
}

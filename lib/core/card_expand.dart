import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:go_router/go_router.dart';
import 'motion/motion_tokens.dart';
import 'motion/transition_snapshot.dart';

/// 卡片"长成"全屏页的展开转场。
///
/// 点击卡片时先调用 [captureCardExpandRect] 记录卡片的屏幕矩形，
/// 再 push 二级页；路由的 pageBuilder 通过 [consumeCardExpandRect]
/// 一次性消费该矩形，transitionsBuilder 据此做「窗口从卡片矩形 lerp
/// 到全屏，卡片界面元素跟着窗口一起移动；宽度跟着走，高度保持比例」的过渡。
/// 其他入口进入（未记录矩形）时退化为默认的上滑淡入。
Rect? _cardExpandRect;
ui.Image? _cardExpandSnapshot;

/// go_router 每次改栈都会重跑 pageBuilder，[consumeCardExpandRect] 又是
/// 一次性的。同一条路由（同一个 [Page.key]）必须记住第一次吃到的源矩形，
/// 否则从叠在上面的设置页返回后会变成不透明普通页：卡片 morph 没了，
/// 自绘右滑也没了（[_CardExpandRoute] 并没有 iOS 系统返回手势）。
final Map<LocalKey, Rect> _expandRectByPage = <LocalKey, Rect>{};
final Map<LocalKey, ui.Image> _expandSnapshotByPage = <LocalKey, ui.Image>{};

/// 已经建过一次的页面。改栈时整栈的 pageBuilder 都会重跑，祖先页重跑时
/// 不能把这次 push 新记录的原点抢走——否则真正被 push 的那一页永远拿不到
/// 源矩形，只能退化成上滑淡入。层级越深越明显：设置 → 本地音乐 → 文件管理
/// 的第三层就是这样。所以只有 [Page.key] 第一次出现才有资格消费。
final Set<LocalKey> _expandPageSeen = <LocalKey>{};

Rect? _adoptExpandRect(ValueKey<String> pageKey, Rect? explicit) {
  final rect = explicit ?? _cardExpandRect;
  _cardExpandRect = null;
  if (rect == null) return _expandRectByPage[pageKey];
  _expandRectByPage[pageKey] = rect;
  return rect;
}

ui.Image? _adoptExpandSnapshot(ValueKey<String> pageKey, ui.Image? explicit) {
  final snapshot = explicit ?? _cardExpandSnapshot;
  _cardExpandSnapshot = null;
  if (snapshot == null) return _expandSnapshotByPage[pageKey];
  final previous = _expandSnapshotByPage[pageKey];
  if (previous != null && !identical(previous, snapshot)) {
    previous.dispose();
  }
  _expandSnapshotByPage[pageKey] = snapshot;
  return snapshot;
}

void _forgetExpandOrigin(LocalKey pageKey) {
  _expandPageSeen.remove(pageKey);
  _expandRectByPage.remove(pageKey);
  _expandSnapshotByPage.remove(pageKey)?.dispose();
}

/// 丢弃一次待消费的展开原点。
///
/// 点击卡片时 [captureCardExpandOrigin] 会先写全局矩形/快照，等目标页的
/// pageBuilder 消费。若这一页选择不做卡片 morph，必须在这里清掉，
/// 否则这份几何会跟到下一张真正要展开的页面上，从错误的位置长出来。
void _dropPendingExpandOrigin(LocalKey pageKey) {
  _cardExpandRect = null;
  _cardExpandSnapshot?.dispose();
  _cardExpandSnapshot = null;
  cardExpandSourceHidden.value = false;
  cardExpandHiddenKey = null;
  _expandRectByPage.remove(pageKey);
  _expandSnapshotByPage.remove(pageKey)?.dispose();
}

/// 测试之间清掉按路由记住的展开原点，避免 key 撞车串数据。
@visibleForTesting
void debugResetCardExpandOrigins() {
  _expandPageSeen.clear();
  _expandRectByPage.clear();
  for (final image in _expandSnapshotByPage.values) {
    image.dispose();
  }
  _expandSnapshotByPage.clear();
}

/// 当前参与转场的源卡片只在关闭后段隐藏，避免实时页面与源卡片快照重影。
final ValueNotifier<bool> cardExpandSourceHidden = ValueNotifier<bool>(false);
GlobalKey? cardExpandHiddenKey;

/// 记录当前卡片的屏幕矩形（供展开转场使用）。
void captureCardExpandRect(BuildContext context) {
  final box = context.findRenderObject() as RenderBox?;
  if (box != null && box.hasSize && box.attached) {
    _cardExpandRect = box.localToGlobal(Offset.zero) & box.size;
  }
}

/// 同时记录卡片几何和像素快照。快照只在转场前短暂保留，用于让源卡片
/// 本体先随边界长大，再交给目标页面内容。
Future<void> captureCardExpandOrigin(BuildContext context) async {
  // 开启动画不隐藏源卡片；隐藏只由关闭阶段的 morph 进度控制。
  cardExpandSourceHidden.value = false;
  captureCardExpandRect(context);
  cardExpandHiddenKey = context.widget.key is GlobalKey
      ? context.widget.key as GlobalKey
      : null;
  final boundary = context.findRenderObject() as RenderRepaintBoundary?;
  if (boundary == null || !boundary.attached || !boundary.hasSize) return;
  try {
    // 按设备像素密度截图（封顶 2x），否则收拢成卡片后快照被插值放大、
    // 文字发虚。
    final dpr = MediaQuery.maybeOf(context)?.devicePixelRatio ?? 1.0;
    final snapshot = await boundary.toImage(pixelRatio: dpr.clamp(1.0, 2.0));
    _cardExpandSnapshot?.dispose();
    _cardExpandSnapshot = snapshot;
  } catch (_) {
    // GPU 快照偶发失败时仍使用几何转场，不能阻断导航。
  }
}

/// 消费并清空展开矩形；pageBuilder 中调用一次。
Rect? consumeCardExpandRect() {
  final rect = _cardExpandRect;
  _cardExpandRect = null;
  return rect;
}

ui.Image? consumeCardExpandSnapshot() {
  final snapshot = _cardExpandSnapshot;
  _cardExpandSnapshot = null;
  return snapshot;
}

/// 卡片拖拽关闭进度（0..1，1 = 完全收起成卡片）。
/// 仅作为 [EdgeSwipeDismiss] 未绑定会话时的回退（播放器、单测）。
/// 卡片展开页 / 整页右滑页必须用每条路由自己的 [_CardDismissSession]，
/// 否则下层透明页会跟着上层的关闭进度一起收拢，看起来像卡死。
final ValueNotifier<double> cardDismissProgress = ValueNotifier<double>(0);

/// 卡片拖动手势的水平位移（0..屏宽）。拖动中卡片左缘跟随该值，
/// 完全跟手；松手后由 _EdgeSwipeDismissState 的 settle 动画驱动归位。
final ValueNotifier<double> cardDismissOffset = ValueNotifier<double>(0);

/// 边缘拖动手势是否激活（拖动中或归位动画中）。
/// 全屏播放器等透明路由据此采用"卡片式"跟手 rect（随手指位移+收缩）。
bool edgeDragActive = false;

/// 拖拽/回弹动画接管期间，禁止路由动画继续参与过渡计算，
/// 否则 Navigator 反向动画会把已收拢的卡片先弹回全屏再关闭。
bool cardDismissLocked = false;

/// 单条可展开路由的关闭会话。叠在透明卡片页上的设置页必须各用各的，
/// 不能写进上面的全局 notifier。
class _CardDismissSession {
  final ValueNotifier<double> progress = ValueNotifier<double>(0);
  final ValueNotifier<double> offset = ValueNotifier<double>(0);
  bool locked = false;
  bool dragActive = false;

  void dispose() {
    progress.dispose();
    offset.dispose();
  }
}

class _CardDismissScope extends InheritedWidget {
  const _CardDismissScope({required this.session, required super.child});

  final _CardDismissSession session;

  static _CardDismissSession? maybeOf(BuildContext context) {
    // 手势回调 / AnimatedBuilder 都可能读会话，不能用 dependOnInheritedWidget。
    return context.getInheritedWidgetOfExactType<_CardDismissScope>()?.session;
  }

  @override
  bool updateShouldNotify(_CardDismissScope oldWidget) =>
      oldWidget.session != session;
}

/// 二级页统一转场：从卡片矩形展开（有矩形时），否则上滑 + 淡入。
/// 页面级动画只允许出现在 PlayerScreen 内部，由 player_expand_test
/// 文本守卫校验，因此这里不使用标准 Transition 封装组件。
CustomTransitionPage<Object?> expandablePage(
  ValueKey<String> pageKey,
  Widget child, {
  Rect? expandRect,
  ui.Image? expandSnapshot,
  bool fullWidthSwipe = false,
  bool expandFromCard = true,
}) {
  // 只有第一次出现的页面（这次真正被 push 的那一页）才消费原点；
  // 祖先页在改栈时也会重跑 pageBuilder，它们只认自己记住的那一份。
  final firstBuild = _expandPageSeen.add(pageKey);
  if (expandFromCard) {
    expandRect = firstBuild
        ? _adoptExpandRect(pageKey, expandRect)
        : _expandRectByPage[pageKey];
    expandSnapshot = firstBuild
        ? _adoptExpandSnapshot(pageKey, expandSnapshot)
        : _expandSnapshotByPage[pageKey];
  } else {
    // 该页明确不做卡片 morph。仍然要把点击时记下的原点丢掉，
    // 否则这张矩形会残留给下一个真正想从卡片展开的页面。
    _dropPendingExpandOrigin(pageKey);
    expandRect = null;
    expandSnapshot = null;
  }
  final sourceRect = expandRect;
  final sourceSnapshot = expandSnapshot;
  final expanding = sourceRect != null;
  return _CardExpandPage(
    key: pageKey,
    // 普通页（无卡片展开）保持不透明：稳定状态下只画最上面一页，下层
    // 页面不参与绘制。左缘手势开始时 [EdgeSwipeDismiss] 会临时把这条
    // 路由的 overlay 条目改成非不透明，让页面往右滑时露出真正的下层
    // 页面而不是窗口底色，松手归位后再恢复。
    // 卡片展开页必须透明才能透视下层做矩形 morph。
    // 整页右滑页也必须透明，飞入/飞出时才能实时露出下层页面。
    opaque: !expanding && !fullWidthSwipe,
    barrierDismissible: expanding,
    barrierColor: Colors.transparent,
    // 卡片容器转场比普通页面快 100ms，打开/关闭使用同一组节奏。
    //
    // 普通页（横向滑一整屏）不能套这个缩短值：180ms 滑满一屏接近每秒
    // 5.5 屏，退出会显得"唰"地一下闪走。进出都用普通过渡时长。
    transitionDuration: effectsDuration(
      Duration(
        milliseconds: expanding
            ? MotionDuration.container.inMilliseconds - 100
            : MotionDuration.normal.inMilliseconds,
      ),
    ),
    reverseTransitionDuration: effectsDuration(
      Duration(
        milliseconds: expanding
            ? MotionDuration.normal.inMilliseconds - 100
            : MotionDuration.normal.inMilliseconds,
      ),
    ),
    child: child,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final session = _CardDismissScope.maybeOf(context);
      final dismissProgress = session?.progress ?? cardDismissProgress;
      final dismissOffset = session?.offset ?? cardDismissOffset;
      // 普通滑入页的动画起点推迟到页面首帧画完之后：首帧要构建、布局整页，
      // 页面重的时候那几十毫秒会直接算进动画，第一帧就跳过去一大截，观感
      // 就是「点下去卡一下才开始滑」。卡片 morph 有自己的矩形节奏，不动它。
      final curved = CurvedAnimation(
        parent: expanding ? animation : TransitionStart.of(animation),
        curve: Curves.easeOutCubic,
        // 反向**必须线性**。
        //
        // `_CardRevealTransition` 里 `t = 1 - animation.value`，所以反向
        // 曲线直接决定了收拢的节奏：easeInCubic 把 animation.value 在前
        // 三分之一压得很低，于是 `t` 直线冲向 1——实测 180ms 的反向动画
        // 在 136ms 时窗口就已经缩到源卡片大小（400x172 vs 380x150），
        // 剩下的 44ms 无事可做，屏幕上立刻安静下来，最后才被真实卡片
        // 补上。用户看到的就是"动效不完整 + 收尾闪一下"。
        //
        // 展开方向用 easeOutCubic 是对的：起点要跟手、终点要留惯性。
        // 收拢方向要的恰恰相反：开头稳、结尾匀，全程都要有可见的变化。
        // 线性把 100% 的行程摊在整段时间上，配合下面按尺寸判定交棒，
        // 每一帧都在收缩，不会出现空转段。
        reverseCurve: Curves.linear,
      );
      late final Widget transition;
      if (expanding) {
        // 有源卡片矩形时必须走矩形 morph。fullWidthSwipe 只影响返回手势
        // 范围，不能改成整页中心缩放——快捷卡半宽时那种缩放就是均匀放大。
        transition = _CardRevealTransition(
          animation: curved,
          sourceGlobalRect: sourceRect,
          sourceSnapshot: sourceSnapshot,
          child: child,
        );
      } else if (fullWidthSwipe) {
        transition = AnimatedBuilder(
          animation: Listenable.merge([curved, dismissOffset, dismissProgress]),
          child: _pageSnapshot(animation, child),
          builder: (context, child) {
            final width = MediaQuery.sizeOf(context).width;
            final current = _CardDismissScope.maybeOf(context);
            final gestureDriven =
                (current?.dragActive ?? edgeDragActive) ||
                (current?.locked ?? cardDismissLocked) ||
                (current?.offset ?? dismissOffset).value > 0;
            final dx = gestureDriven
                ? (current?.offset ?? dismissOffset).value
                : width * (1 - curved.value);
            final t = gestureDriven
                ? (current?.progress ?? dismissProgress).value.clamp(0.0, 1.0)
                : (1 - curved.value).clamp(0.0, 1.0);
            final scale = 1 - 0.10 * t;
            final radius = 34.0 * t;
            return Transform.translate(
              offset: Offset(dx, 12 * t),
              child: Transform.scale(
                scale: scale,
                alignment: Alignment.center,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(radius),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.24 * (1 - t)),
                        blurRadius: 28,
                        spreadRadius: 2 * t,
                        offset: const Offset(-8, 2),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(radius),
                    child: child,
                  ),
                ),
              ),
            );
          },
        );
      } else {
        // 普通二级页：横向滑动进出，也就是系统返回的观感。
        //
        // 这里以前是「淡出 + 下移 24」。淡出叠在全屏播放器那种整屏深色
        // 背景上会像画面溶解，看不出「返回」的方向；横向滑出则始终能
        // 看见下层从左边接上来。
        //
        // 手势进行中不能用路由动画的位移：这一段位移已由外层
        // [EdgeSwipeDismiss] 按手指位置负责，这里再叠一次会让页面跑得
        // 比手指快。
        transition = AnimatedBuilder(
          animation: Listenable.merge([curved, dismissProgress, dismissOffset]),
          child: _pageSnapshot(animation, child),
          builder: (context, child) {
            final current = _CardDismissScope.maybeOf(context);
            final gestureDriven =
                (current?.dragActive ?? edgeDragActive) ||
                (current?.locked ?? cardDismissLocked) ||
                (current?.offset ?? dismissOffset).value > 0;
            if (gestureDriven) return child!;
            final t = curved.value.clamp(0.0, 1.0);
            return FractionalTranslation(
              translation: Offset(1 - t, 0),
              child: child,
            );
          },
        );
      }
      return EdgeSwipeDismiss(
        child: transition,
        fullWidthSwipe: fullWidthSwipe,
        // 收拢成型后锁定本路由的反向动画，pop 后不会弹回全屏再收一遍。
        onDismissCommit: () {
          final current = _CardDismissScope.maybeOf(context);
          if (current != null) {
            current.locked = true;
          } else {
            cardDismissLocked = true;
          }
        },
      );
    },
  );
}

/// 转场期间用位图代替实时页面。
///
/// 位移每帧都在变，实时页面就要跟着整页重画：列表文字、封面、顶栏磨砂
/// 全在里面。换成位图后每帧只剩一次贴图，页面多复杂都一样快。
Widget _pageSnapshot(Animation<double> animation, Widget child) =>
    TransitionSnapshot(
      animations: <Animation<double>>[animation],
      child: child,
    );

class _CardExpandPage extends CustomTransitionPage<Object?> {
  _CardExpandPage({
    required super.key,
    required super.child,
    required super.transitionsBuilder,
    required super.opaque,
    required super.barrierDismissible,
    super.barrierColor,
    super.transitionDuration,
    super.reverseTransitionDuration,
  });

  @override
  Route<Object?> createRoute(BuildContext context) =>
      _CardExpandRoute(page: this);
}

/// 卡片页路由：视觉收拢完成（cardDismissLocked）后再 pop 时，反向动画
/// 清零——路由与屏障立即移除，源卡片无需等一段不可见的过渡时间才能点击。
class _CardExpandRoute extends PageRoute<Object?> {
  _CardExpandRoute({required _CardExpandPage page}) : super(settings: page);

  _CardExpandPage get _page => settings as _CardExpandPage;

  final _CardDismissSession session = _CardDismissSession();

  @override
  bool get opaque => _page.opaque;

  @override
  bool get barrierDismissible => _page.barrierDismissible;

  @override
  Color? get barrierColor => _page.barrierColor;

  @override
  String? get barrierLabel => _page.barrierLabel;

  @override
  bool get maintainState => _page.maintainState;

  /// 关掉路由级快照。
  ///
  /// Flutter 默认会把「已稳定」的页面缓存成一张图层贴图，过渡期间直接
  /// 复用。卡片页恰恰是**自绘 morph**：窗口矩形、内容缩放、快照交接
  /// 每帧都在变，路由快照与实时绘制交替出现时，收尾那几帧会产生
  /// "旧画面闪一下"的观感。全屏播放器路由早就关掉了它（见
  /// app_router.dart 里 _PlayerTransitionRoute 的注释），卡片页这里
  /// 一直漏着，属于同一个坑的第二个入口。
  @override
  bool get allowSnapshotting => false;

  @override
  Duration get transitionDuration => _page.transitionDuration;

  @override
  Duration get reverseTransitionDuration => _page.reverseTransitionDuration;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => Semantics(
    scopesRoute: true,
    explicitChildNodes: true,
    child: _page.child,
  );

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => _CardDismissScope(
    session: session,
    child: Builder(
      builder: (context) => _page.transitionsBuilder(
        context,
        animation,
        secondaryAnimation,
        child,
      ),
    ),
  );

  @override
  bool didPop(Object? result) {
    if (session.locked) {
      controller?.reverseDuration = Duration.zero;
    }
    return super.didPop(result);
  }

  @override
  TickerFuture didPush() {
    // 新页面推入的这一帧要构建、布局整页；动画若从这一帧开始计时，
    // 下一帧直接跳过一大截，看起来就是「点下去先卡一下」。让它先在起点
    // 画完首帧，动画下一帧再从 0 平滑起步。
    TransitionStart.hold();
    return super.didPush();
  }

  @override
  void dispose() {
    final key = _page.key;
    super.dispose();
    session.dispose();
    if (key != null) _forgetExpandOrigin(key);
  }
}

/// 从屏幕左缘右滑关闭当前页面。只在边缘窄条接管手势，避免影响页面
/// 内的横向列表、播放器 PageView 和主 Tab 滑动。
///
/// 所有平台都走这一套自绘手势，不再区分“iOS 交给系统”。
///
/// 这里曾经按“不透明路由 = iOS 系统手势可用”跳过自绘手势，前提不成立：
/// 系统左缘返回是由 `CupertinoPageTransitionsBuilder`（`MaterialPageRoute`
/// 在 iOS 上默认用它）注入的 `_CupertinoBackGestureDetector`，而本文件的
/// `_CardExpandRoute` 是自定义 `PageRoute` 并且重写了 `buildTransitions`，
/// 根本没有任何组件给它装系统手势。于是“不透明 + iOS”的页面两头落空：
/// 系统手势不存在，自绘手势又被自己关掉——表现为设置里点进去的均衡器、
/// 同步、统计等页面完全没法右滑返回。
/// - 透明路由（卡片展开页/播放器）：只发布 [progress]（跟手驱动
///   内层 morph），不叠加外层 transform——否则内容缩放与外层矩形
///   裁剪两条曲线打架，出现"与卡片同缩程度不一致的浮动层"。
class EdgeSwipeDismiss extends StatefulWidget {
  const EdgeSwipeDismiss({
    super.key,
    required this.child,
    this.progress,
    this.onDismissCommit,
    this.invertProgress = false,
    this.fullWidthSwipe = false,
    this.bypassOnLandscape = false,
    this.landscapeLayout = false,
  });

  final Widget child;

  /// 拖动进度发布目标（1 = 完全收拢）。卡片页默认全局卡片进度，
  /// 播放器传入全屏播放器路由进度。
  final ValueNotifier<double>? progress;

  /// 收拢完成后、关闭路由前的回调（宿主在此锁定反向动画接管）。
  final VoidCallback? onDismissCommit;

  /// 目标进度语义是否反转：播放器路由进度是"1=全屏、0=收拢"，
  /// 与拖动进度（0=起点、1=拖满）相反，必须取反才能让封面
  /// 从全屏随手指逐渐变小，而不是按下瞬间跳到迷你形态。
  final bool invertProgress;

  /// 整页右滑返回（用于无横向滚动内容的页面，如榜单设置）。
  /// 默认只接管左缘窄条，避免与页面内横向列表/PageView 冲突。
  final bool fullWidthSwipe;

  /// 横屏播放器不需要透明 morph / 边缘包装，避免 Android 合成器把
  /// 路由背景留在内容之上。
  final bool bypassOnLandscape;
  final bool landscapeLayout;

  @override
  State<EdgeSwipeDismiss> createState() => _EdgeSwipeDismissState();
}

class _EdgeSwipeDismissState extends State<EdgeSwipeDismiss>
    with SingleTickerProviderStateMixin {
  double _drag = 0;
  // 形态进度（0..1，1 = 完全收拢成卡片）：与位移_独立，
  // 松手收拢时页面一边滑回原位一边持续收拢成卡片，绝不先放大再退出。
  double _morph = 0;
  _CardDismissSession? _session;
  ModalRoute<Object?>? _route;
  late ValueNotifier<double> _progress;
  late final AnimationController _settleController;
  Animation<double>? _dragAnimation;
  Animation<double>? _morphAnimation;

  @override
  void initState() {
    super.initState();
    _progress = widget.progress ?? cardDismissProgress;
    _settleController = AnimationController(vsync: this)
      ..addListener(() {
        final drag = _dragAnimation;
        if (drag != null && mounted) {
          setState(() => _drag = drag.value);
        }
        final morph = _morphAnimation;
        if (morph != null) {
          _morph = morph.value;
        }
        _syncProgress();
      });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _session = _CardDismissScope.maybeOf(context);
    _route = ModalRoute.of(context);
    if (widget.progress == null) {
      _progress = _session?.progress ?? cardDismissProgress;
    }
  }

  /// 拖动期间让下层页面参与绘制。
  ///
  /// 不透明路由稳定后 `overlayEntries.first.opaque == true`，Overlay 会跳过
  /// 它下面所有条目——页面往右滑时腾出来的那块区域只能看到窗口底色（黑）。
  /// 开始拖动时临时置为 false，松手归位后恢复；只在手势进行中付这份
  /// 绘制开销，平时仍然只画最上面一页。
  ///
  /// [painted] 为 false 时不强行恢复：正在关闭的路由会被 Flutter 自己的
  /// 状态回调置成 false，抢回来反而会让它重新盖住下层。
  void _setUnderlyingPainted(bool painted) {
    final route = _route;
    if (route == null || !route.opaque) return;
    final entries = route.overlayEntries;
    if (entries.isEmpty) return;
    final entry = entries.first;
    if (painted) {
      if (entry.opaque) entry.opaque = false;
      return;
    }
    final animation = route.animation;
    if (animation != null && animation.status != AnimationStatus.completed) {
      return;
    }
    if (!entry.opaque) entry.opaque = true;
  }

  @override
  void dispose() {
    if (_progress.value != 0) {
      _progress.value = 0;
    }
    final session = _session;
    if (session != null) {
      session.offset.value = 0;
      session.dragActive = false;
      if (widget.fullWidthSwipe) session.locked = false;
    } else {
      cardDismissOffset.value = 0;
      edgeDragActive = false;
      // fullWidthSwipe 不经过 _CardRevealTransition.dispose；必须在这里清锁，
      // 否则一次手势退出后后续按钮/手势退出都会被当成已收拢而跳过动画。
      if (widget.fullWidthSwipe) cardDismissLocked = false;
    }
    _settleController.dispose();
    super.dispose();
  }

  // 把当前形态进度发布给过渡层（跟手驱动矩形 morph）。
  void _syncProgress() {
    _progress.value = widget.invertProgress ? 1 - _morph : _morph;
    final dragging = _drag > 0 || _morph > 0;
    final session = _session;
    if (session != null) {
      session.offset.value = _drag;
      session.dragActive = dragging;
    } else {
      cardDismissOffset.value = _drag;
      edgeDragActive = dragging;
    }
  }

  void _setLocked(bool value) {
    final session = _session;
    if (session != null) {
      session.locked = value;
    } else {
      cardDismissLocked = value;
    }
  }

  void _setDragActive(bool value) {
    final session = _session;
    if (session != null) {
      session.dragActive = value;
    } else {
      edgeDragActive = value;
    }
  }

  void _settleTo({
    required double targetDrag,
    required double targetMorph,
    required Duration duration,
    VoidCallback? onStart,
    required VoidCallback onComplete,
  }) {
    _settleController
      ..stop()
      ..duration = motionDuration(context, duration);
    final curved = CurvedAnimation(
      parent: _settleController,
      // 归位/收拢带 spring 手感，与全屏播放器动效同一曲线族。
      curve: MotionCurve.iosSpring,
    );
    _dragAnimation = Tween<double>(
      begin: _drag,
      end: targetDrag,
    ).animate(curved);
    _morphAnimation = Tween<double>(
      begin: _morph,
      end: targetMorph,
    ).animate(curved);
    onStart?.call();
    void settleListener(AnimationStatus status) {
      if (status != AnimationStatus.completed) return;
      _settleController.removeStatusListener(settleListener);
      // 0 时长动画会在 forward() 内同步完成；先清理全局手势状态，
      // 否则透明播放器会一直被当成“正在收起”，只显示半透明遮罩。
      _syncProgress();
      onComplete();
    }

    _settleController.addStatusListener(settleListener);
    _settleController.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final landscape =
        widget.landscapeLayout ||
        MediaQuery.orientationOf(context) == Orientation.landscape ||
        width > MediaQuery.sizeOf(context).height ||
        View.of(context).physicalSize.width >
            View.of(context).physicalSize.height;
    if (widget.bypassOnLandscape && landscape) {
      return widget.child;
    }
    final route = ModalRoute.of(context);
    final opaqueRoute = route?.opaque ?? true;
    final ios = Theme.of(context).platform == TargetPlatform.iOS;
    // 透明路由（卡片展开/播放器）必须只走内层矩形 morph 一套进度，
    // 避免外层 translate/scale 与内层裁剪互相打架。
    final cardMorph = !opaqueRoute;
    // 普通不透明页只做横向跟手位移，不再缩小加圆角。
    //
    // 以前这里在 iOS 上按收拢进度缩到 0.5、加 48 圆角并叠阴影，那是给
    // 「收进一张卡片」准备的形态。顶层的普通页并没有一个收敛目标，
    // 缩小只是把页面凭空捏小再消失，跟系统返回手势完全不像。
    final page = cardMorph
        ? widget.child
        : Transform.translate(offset: Offset(_drag, 0), child: widget.child);
    return Stack(
      fit: StackFit.expand,
      children: [
        page,
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          // 左缘生效区与 iOS 系统手势区（约 20pt）相比略宽，提高触发
          // 成功率；页面无横向滚动内容时可整页右滑返回。
          right: widget.fullWidthSwipe ? 0 : null,
          width: widget.fullWidthSwipe ? null : (ios ? 40.0 : 32.0),
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragStart: (_) {
              _settleController.stop();
              _setDragActive(true);
              _setUnderlyingPainted(true);
            },
            onHorizontalDragUpdate: (details) {
              if (details.delta.dx <= 0 && _drag <= 0) return;
              final max = MediaQuery.sizeOf(context).width;
              setState(() {
                _drag = (_drag + details.delta.dx).clamp(0.0, max);
                _morph = _drag / max;
              });
              _syncProgress();
            },
            onHorizontalDragEnd: (details) {
              final velocity = details.primaryVelocity ?? 0;
              if (_drag > width * 0.22 || velocity > 700) {
                // 从当前位置继续滑出屏幕右侧，成型后再 pop。宿主此时锁定
                // 反向动画，路由关闭不再回弹——普通页不能先回原位再播一遍
                // 滑出，那会看到页面"弹回去又飞走"。
                _settleTo(
                  targetDrag: width,
                  targetMorph: 1,
                  duration: MotionDuration.normal,
                  onComplete: () {
                    widget.onDismissCommit?.call();
                    Navigator.of(context).maybePop();
                  },
                );
              } else {
                _settleTo(
                  targetDrag: 0,
                  targetMorph: 0,
                  duration: MotionDuration.micro,
                  onComplete: () {
                    _setLocked(false);
                    _setUnderlyingPainted(false);
                  },
                );
              }
            },
            onHorizontalDragCancel: () {
              _settleTo(
                targetDrag: 0,
                targetMorph: 0,
                duration: MotionDuration.micro,
                onComplete: () {
                  _setLocked(false);
                  _setUnderlyingPainted(false);
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _CardRevealTransition extends StatefulWidget {
  const _CardRevealTransition({
    required this.animation,
    required this.sourceGlobalRect,
    this.sourceSnapshot,
    required this.child,
  });

  final Animation<double> animation;
  final Rect sourceGlobalRect;
  final ui.Image? sourceSnapshot;
  final Widget child;

  @override
  State<_CardRevealTransition> createState() => _CardRevealTransitionState();
}

class _CardRevealTransitionState extends State<_CardRevealTransition> {
  _CardDismissSession? _session;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _session = _CardDismissScope.maybeOf(context);
  }

  @override
  void dispose() {
    cardExpandSourceHidden.value = false;
    cardExpandHiddenKey = null;
    final session = _session;
    if (session != null) {
      if (session.locked) {
        session.locked = false;
        session.progress.value = 0;
      }
    } else if (cardDismissLocked) {
      cardDismissLocked = false;
      cardDismissProgress.value = 0;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 卡片矩形直接使用记录时的屏幕坐标：路由页面与 Navigator 同坐标系，
    // 收拢终点即源卡片原位，避免坐标换算引入偏移。
    final sourceTopLeft = widget.sourceGlobalRect.topLeft;
    final sourceRect = sourceTopLeft & widget.sourceGlobalRect.size;
    final targetRect = Offset.zero & MediaQuery.sizeOf(context);
    final backgroundColor = Theme.of(context).scaffoldBackgroundColor;
    final session = _CardDismissScope.maybeOf(context);
    final dismissProgress = session?.progress ?? cardDismissProgress;
    final dismissOffset = session?.offset ?? cardDismissOffset;

    return AnimatedBuilder(
      animation: Listenable.merge([
        widget.animation,
        dismissProgress,
        dismissOffset,
      ]),
      child: RepaintBoundary(child: widget.child),
      builder: (context, child) {
        final current = _CardDismissScope.maybeOf(context);
        final progress = current?.progress ?? dismissProgress;
        final offset = current?.offset ?? dismissOffset;
        final locked = current?.locked ?? cardDismissLocked;
        final dragActive = current?.dragActive ?? edgeDragActive;
        // 跟手时用手指的 dismiss 进度，其余一切情形都听路由动画。
        //
        // 分工必须这么切，不能"取两者更大值"：
        //
        // · 拖动中（dragActive）：矩形左缘跟着手指，progress 即真相。
        // · 松手后（settle 阶段）：`_settleTo(targetMorph: 1)` 会把
        //   progress 一路推到 1，但这段用的是 iosSpring，末段缓出——
        //   若此时仍认 progress，窗口会在 settle 尾声就塌到源卡片大小，
        //   之后 `EdgeSwipeDismiss` 才 pop，路由那 240ms 反向动画全被
        //   吞掉，屏幕冻结一阵再硬切。现场录屏 f836~f842 冻结 7 帧、
        //   f843 突变就是这么来的。
        // · 所以松手瞬间就把主导权交回 `1 - animation.value`：settle 负责
        //   手指的位移归位，路由动画负责形态收拢，两条曲线互不抢权。
        //
        // locked（拖拽已完成、只等路由移除）同样不再参与几何。
        final t = dragActive && !locked
            ? progress.value.clamp(0.0, 1.0)
            : (1 - widget.animation.value).clamp(0.0, 1.0);
        // 窗口从源卡片矩形 lerp 到全屏：四边各自长到屏幕边。
        // 卡片界面元素跟着窗口一起移动，宽度按当前窗宽缩放；
        // 高度用同一比例，避免半宽矮卡被窗高单独压扁。
        var currentRect = Rect.lerp(sourceRect, targetRect, 1 - t)!;
        // 跟手：拖动中卡片左缘 = 手指水平位移，手停卡停；
        // 松手动画（已锁）线性归位到源卡片位置；
        // 无拖动的正常关闭（返回按钮/系统手势）直接归位到源位置，
        // 不能再往左缘飞。
        final fingerX = offset.value;
        // 只有手指还按在屏幕上才叫"拖动"。松手后（settle / locked）
        // 矩形左缘由 settle 负责归位，这里的水平覆盖必须停手，
        // 否则会把已经收窄的窗口又拽回手指位置。
        final dragging = dragActive && !locked;
        final dismissing =
            dragging ||
            locked ||
            progress.value > 0 ||
            widget.animation.status == AnimationStatus.reverse;
        // 窗口已经收到源卡片大小附近 —— 转场层该退场了。
        //
        // 判定按**窗口尺寸**，不按 `t`。
        //
        // 反向动画只有 180ms，而 `t = 1 - animation.value`：任何非线性
        // 反向曲线都会让 `t` 在某一段里走完大半行程，用 `t` 做阈值就等于
        // 用一个和"窗口长到多大"无关的量去决定何时砍层。实测旧实现
        // （t >= 0.99 砍层）在 136ms 时窗口还有 400px 宽（屏幕 800、
        // 源卡片 380），转场层已经消失，剩下 44ms 屏幕上没有转场内容，
        // 最后才被真实卡片补上——这就是"收尾闪烁"的可测量来源。
        //
        // 阈值 1.02 / 1.06 留亚像素余量：松到 1.06 / 1.12 会正好把
        // 402px（源卡片 380）判成"已到位"，收尾提前 40ms 结束。
        final handoffReady =
            currentRect.width <= sourceRect.width * 1.02 &&
            currentRect.height <= sourceRect.height * 1.06;
        // 源卡片只在快照交接窗口隐藏。
        //
        // 起点 0.58 与下面 snapshotOpacity 的淡入起点对齐：早了是重影
        // （快照还没浮现、源卡片也没隐藏），晚了会露出真实卡片。
        // 终点不写死，交给 `handoffReady`——转场层什么时候退场，源卡片
        // 就什么时候恢复，两者是同一件事。
        final hideSource =
            widget.sourceSnapshot != null &&
            dismissing &&
            t >= 0.58 &&
            !handoffReady;
        if (cardExpandSourceHidden.value != hideSource) {
          // 不能在 build 里直接写这个全局 notifier：它的监听者
          // （Pressable 的 ValueListenableBuilder）会在本帧的构建过程中被
          // 标脏，`Element.rebuild` 结束时 `!_dirty` 断言就会失败——横竖屏
          // 切换时整棵树重建，正好踩中这条路径，表现为旋转即红屏。
          // 放到帧末写入，交接只晚一帧，肉眼看不出来。
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            if (cardExpandSourceHidden.value != hideSource) {
              cardExpandSourceHidden.value = hideSource;
            }
          });
        }
        if (dragging) {
          currentRect = Rect.fromLTWH(
            fingerX * (1 - t) + sourceRect.left * t,
            currentRect.top,
            currentRect.width,
            currentRect.height,
          );
        }
        // 收拢/拖拽关闭方向（dragging）：内容保持不透明、不浮现快照，
        // 收拢矩形只是裁剪窗口——route 移除瞬间真实页面同像素接管，
        // 不会出现"快照 vs 实时渲染"的亮度跳变。
        // 展开方向保留原逻辑：内容淡出让快照盖住未长成的本体。
        //
        // 关闭交接窗口整体提前：旧版是 85%~95% 淡入快照、95%~99% 只剩
        // 快照飞回、最后 1% 砍层。`t` 由曲线驱动，末段极快——真实页面在
        // 85% 之后几乎一帧内就消失，而快照在 95%~99% 之间只有 1~2 帧可画，
        // 收尾就成了"先黑一下再冒出卡片"。
        //
        // 现在 58% 开始淡入快照、70% 完成实时页淡出（此时窗口还有 30%
        // 的行程，足够铺满整个交接过程），终点交给上面的 handoffReady。
        final reveal = dismissing
            ? ((0.70 - t) / 0.12).clamp(0.0, 1.0)
            : ((1 - t) / 0.18).clamp(0.0, 1.0);
        final snapshotOpacity = dismissing
            ? ((t - 0.58) / 0.12).clamp(0.0, 1.0)
            : ((t - 0.8) / 0.2).clamp(0.0, 1.0);
        // 背景/表面圆角全程保持与源卡片一致（18），
        // 动效行进中矩形扩张/收缩不改变圆角。
        const radius = 18.0;

        // 收拢完成时提前交棒：转场层退场，真实页面直接接管。
        // 判定见上面的 handoffReady（按窗口尺寸，不按 t）。
        if (dismissing && handoffReady) {
          return const SizedBox.shrink();
        }

        return Stack(
          fit: StackFit.expand,
          children: [
            // 展开过程中的"兜底底色"：卡片窗口还小的时候，窗口之外必须
            // 有一层东西挡住下层页面。
            //
            // 这个透明路由（opaque=false）不会裁剪下层，所以窗口矩形以外
            // 的区域直接露出首页。旧实现只有窗口内部那一层 ColoredBox，
            // 于是整段展开里首页的搜索框、功能卡片、迷你条始终可见——
            // 用户看到的就是"详情页铺开了，但首页还盖在上面"。
            //
            // 底色跟着 reveal 一起淡入（与窗口内背景同一条曲线），
            // 窗口还小的时候它是半透明的，看起来像卡片在把整屏染成底色；
            // 窗口长满时它已经是纯底色，无感。
            if (!dismissing)
              Opacity(
                opacity: ((1 - t) / 0.30).clamp(0.0, 1.0),
                child: ColoredBox(color: backgroundColor),
              ),
            Positioned.fromRect(
              rect: currentRect,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(radius),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Opacity(
                      opacity: reveal,
                      child: ColoredBox(color: backgroundColor),
                    ),
                    // 源卡片快照按窗宽等比放大，相对窗口居中：
                    // 收起时上下左右一起走，而不是顶对齐从下往上收。
                    if (widget.sourceSnapshot != null)
                      Opacity(
                        opacity: snapshotOpacity,
                        child: Transform.scale(
                          alignment: Alignment.center,
                          scale: currentRect.width / sourceRect.width,
                          child: SizedBox(
                            width: sourceRect.width,
                            height: sourceRect.height,
                            child: RawImage(
                              image: widget.sourceSnapshot,
                              fit: BoxFit.contain,
                              filterQuality: FilterQuality.high,
                            ),
                          ),
                        ),
                      ),
                    // 目的页按窗宽等比缩放。
                    //
                    // 对齐必须是 topCenter：收起时窗口从底部往上缩，只有
                    // 顶部（标题栏、返回键）始终留在窗口里。旧实现用 center，
                    // 窗口一矮就把顶栏裁掉——那段画面里详情页已经看不见标题，
                    // 只剩几行歌曲在窗口里漂着，观感是"页面散架了"。
                    // 展开方向 topCenter 也让标题栏贴着窗口上缘长出来，
                    // 而不是从屏幕正中往上下两边撑。
                    Opacity(
                      opacity: reveal,
                      child: OverflowBox(
                        alignment: Alignment.topCenter,
                        minWidth: targetRect.width,
                        maxWidth: targetRect.width,
                        minHeight: targetRect.height,
                        maxHeight: targetRect.height,
                        child: Transform.scale(
                          alignment: Alignment.topCenter,
                          scale: currentRect.width / targetRect.width,
                          child: SizedBox(
                            width: targetRect.width,
                            height: targetRect.height,
                            child: child,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

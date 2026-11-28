// 文件说明：液态玻璃的背景滤镜着色器（见 shaders/liquid_glass.frag）。
// 技术要点：把背景截取直接交给 shader——边缘按斯涅尔定律弯折、RGB 分通道错位
// 出色散，再叠菲涅尔提亮与斜向高光。玻璃本身几乎没有填充色，透感来自光学
// 而不是染色，这是它和"一层低 alpha 底色 + 一道高光"最根本的区别。

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import '../theme/effect_policy.dart';

/// 液态玻璃着色器。
///
/// 只有 Impeller 等支持背景着色器滤镜的后端能用；软件渲染、Web 与部分老设备
/// 上 [available] 为 false，此时调用方应退回普通毛玻璃而不是画一块透明板。
abstract final class LiquidGlassShader {
  static ui.FragmentProgram? _program;

  /// 着色器是否已经编译好、且当前后端支持。
  static bool get available =>
      _program != null && ui.ImageFilter.isShaderFilterSupported;

  /// 在 `runApp` 之前调用一次。失败只记日志：玻璃退回毛玻璃，界面照常可用。
  static Future<void> init() async {
    if (_program != null) return;
    if (kIsWeb || !ui.ImageFilter.isShaderFilterSupported) return;
    try {
      _program = await ui.FragmentProgram.fromAsset(
        'shaders/liquid_glass.frag',
      );
    } catch (error) {
      debugPrint('液态玻璃着色器编译失败：$error');
    }
  }
}

/// 在子组件背后用液态玻璃着色器处理背景。
///
/// 和 [BackdropFilter] 一样只影响「这块玻璃背后的内容」，玻璃自己的子组件
/// 照常画在上面。同一画面里的多块玻璃通过 [BackdropGroup] 共用一次背景截取
/// ——背景截取在移动 GPU 上是这个效果里最贵的一步。
class LiquidGlassBackdrop extends SingleChildRenderObjectWidget {
  const LiquidGlassBackdrop({
    super.key,
    required this.radius,
    required this.frost,
    this.legible = false,
    this.tint,
    this.bottomEdgeOnly = false,
    super.child,
  });

  /// 玻璃圆角（逻辑像素）。着色器里按正圆弧处理，与普通圆角矩形完全一致。
  final double radius;

  /// 着色器之前的模糊量（sigma）。0 表示完全清透，只靠折射成形。
  final double frost;

  /// 玻璃上是否压着文字。
  ///
  /// 完全清透时，下面列表里的文字会清清楚楚透上来，和这块玻璃自己的标题叠在
  /// 一起读不出来。承载文字的面（顶栏、迷你播放条、弹窗）因此额外加一层很淡
  /// 的色调压低背后内容的对比度；纯装饰的面保持零染色。
  final bool legible;

  /// 覆盖色调强度；为 null 时按 [legible] 与明暗取默认值。
  final double? tint;

  /// 只让液态玻璃的光学边缘出现在下缘。
  final bool bottomEdgeOnly;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return RenderLiquidGlass(
      radius,
      frost,
      MediaQuery.devicePixelRatioOf(context),
      BackdropGroup.of(context)?.backdropKey,
      legible,
      tint,
      bottomEdgeOnly,
    )..dark = Theme.of(context).brightness == Brightness.dark;
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderLiquidGlass renderObject,
  ) {
    renderObject
      ..radius = radius
      ..frost = frost
      ..dpr = MediaQuery.devicePixelRatioOf(context)
      ..backdropKey = BackdropGroup.of(context)?.backdropKey
      ..legible = legible
      ..tint = tint
      ..bottomEdgeOnly = bottomEdgeOnly
      ..dark = Theme.of(context).brightness == Brightness.dark;
  }
}

/// [LiquidGlassBackdrop] 的渲染对象。
class RenderLiquidGlass extends RenderProxyBox {
  /// 参数依次是：圆角、模糊量、设备像素比、共享采样键、承载文字、色调覆盖。
  RenderLiquidGlass(
    this._radius,
    this._frost,
    this._dpr,
    this._backdropKey,
    this._legible,
    this._tint,
    this._bottomEdgeOnly,
  );

  /// 裁剪区域每边多出的逻辑像素：折射会把玻璃外侧一两像素的背景弯进来，
  /// 不留这点余量，圆角边缘会被裁掉一条。
  static const double _pad = 1;

  double _radius;
  double _frost;
  double _dpr;
  BackdropKey? _backdropKey;
  bool _legible;
  double? _tint;
  bool _bottomEdgeOnly;

  bool _dark = false;

  /// 上一次绘制时的屏幕位置。着色器参数里带着坐标，靠它判断"位置变了但没重绘"。
  Offset? _painted;
  bool _checkScheduled = false;
  bool _scrollListenerAttached = false;
  bool _positionListenerAttached = false;

  ui.FragmentShader? _shader;
  final _clip = LayerHandle<ClipRectLayer>();
  final _glass = LayerHandle<BackdropFilterLayer>();

  set radius(double value) {
    if (value == _radius) return;
    _radius = value;
    markNeedsPaint();
  }

  set frost(double value) {
    if (value == _frost) return;
    _frost = value;
    markNeedsPaint();
  }

  set dpr(double value) {
    if (value == _dpr) return;
    _dpr = value;
    markNeedsPaint();
  }

  set backdropKey(BackdropKey? value) {
    if (value == _backdropKey) return;
    _backdropKey = value;
    markNeedsPaint();
  }

  set legible(bool value) {
    if (value == _legible) return;
    _legible = value;
    markNeedsPaint();
  }

  set tint(double? value) {
    if (value == _tint) return;
    _tint = value;
    markNeedsPaint();
  }

  set bottomEdgeOnly(bool value) {
    if (value == _bottomEdgeOnly) return;
    _bottomEdgeOnly = value;
    markNeedsPaint();
  }

  set dark(bool value) {
    if (value == _dark) return;
    _dark = value;
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    if (!_scrollListenerAttached) {
      GlassScrollActivity.listenable.addListener(_handleScrollActivityChanged);
      GlassScrollActivity.positionListenable.addListener(
        _handleScrollActivityChanged,
      );
      _scrollListenerAttached = true;
      _positionListenerAttached = true;
    }
  }

  @override
  void detach() {
    if (_scrollListenerAttached) {
      GlassScrollActivity.listenable.removeListener(
        _handleScrollActivityChanged,
      );
      if (_positionListenerAttached) {
        GlassScrollActivity.positionListenable.removeListener(
          _handleScrollActivityChanged,
        );
        _positionListenerAttached = false;
      }
      _scrollListenerAttached = false;
    }
    super.detach();
  }

  void _handleScrollActivityChanged() {
    if (attached) markNeedsPaint();
  }

  @override
  bool get alwaysNeedsCompositing => true;

  @override
  void dispose() {
    _clip.layer = null;
    _glass.layer = null;
    _shader?.dispose();
    super.dispose();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final program = LiquidGlassShader._program;
    // 没编译出着色器、或还没布局出尺寸：照常画子内容，别留一块空白。
    if (program == null || size.isEmpty) {
      super.paint(context, offset);
      return;
    }

    final global = localToGlobal(Offset.zero);
    _painted = global;
    // 祖先的位移/旋转变了但本节点没收到重绘时，着色器里的坐标会停在旧位置，
    // 玻璃边缘的折射就会与背景错开。下一帧补一次重绘把它纠回来。
    _scheduleCheck();

    // 每帧新建 shader：同一个 ImageFilter 会被已经入队的图层持有，复用会让
    // 同帧的其它玻璃读到互相覆盖的 uniform。
    _shader?.dispose();
    final shader = _shader = program.fragmentShader();
    var i = 2; // 0、1 是输入纹理尺寸，由引擎填写。
    void f(double value) => shader.setFloat(i++, value);
    f(size.width * _dpr);
    f(size.height * _dpr);
    f(_radius * _dpr);
    f(_dpr);
    f(20); // 边缘厚度：逻辑像素，原版默认值。
    f(1); // 折射强度 100%。
    f(7); // 色散。
    // 边缘高光。深色背景上同样强度的高光会形成一圈亮边、看起来像两层叠在一起。
    f(_dark ? 0.55 : 0.9);
    // 色调强度：清透材质在浅色下完全不染，深色下仍留一层深灰，否则深色背景上
    // 只剩边缘高光、看起来像几层轮廓叠在一起。
    f(_tint ?? (_dark ? (_legible ? 0.40 : 0.28) : (_legible ? 0.14 : 0)));
    f(2); // 圆角指数：2 即正圆弧，与关闭液态玻璃时的圆角矩形逐像素一致。
    f(global.dx * _dpr);
    f(global.dy * _dpr);
    f(_pad * _dpr);
    f(_bottomEdgeOnly ? 1 : 0);
    if (_dark) {
      f(0.11);
      f(0.11);
      f(0.12);
    } else {
      f(1);
      f(1);
      f(1);
    }

    // 每块玻璃只有一层背景滤镜；同一画面中的所有玻璃通过 BackdropGroup 共用
    // 一次背景截取。着色器在玻璃形状以外输出透明，滤镜结果以 srcOver 叠回，
    // 所以不需要按形状裁剪。
    final layer = _glass.layer ??= BackdropFilterLayer();
    final glass = ui.ImageFilter.shader(shader);
    layer
      ..filter = _frost > 0
          ? ui.ImageFilter.compose(
              outer: glass,
              inner: ui.ImageFilter.blur(
                sigmaX: _frost,
                sigmaY: _frost,
                tileMode: TileMode.clamp,
              ),
            )
          : glass
      ..backdropKey = _backdropKey;
    _clip.layer = context.pushClipRect(
      needsCompositing,
      offset,
      (Offset.zero & size).inflate(_pad),
      (context, offset) => context.pushLayer(layer, super.paint, offset),
      oldLayer: _clip.layer,
    );
  }

  void _scheduleCheck() {
    if (_checkScheduled) return;
    _checkScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _checkScheduled = false;
      if (!attached || _painted == null) return;
      if ((localToGlobal(Offset.zero) - _painted!).distanceSquared > 0.01) {
        markNeedsPaint();
      }
    });
  }
}

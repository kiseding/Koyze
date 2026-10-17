import 'package:flutter/material.dart';

import '../../../core/motion/motion_tokens.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_tokens.dart';
import 'search_provider.dart';

/// 搜索弹窗顶部的输入行。
///
/// Origo-x 的搜索栏是一条浮在磨砂面板上的胶囊：左侧放大镜、右侧随输入
/// 出现的清除与提交按钮，聚焦时边线变亮而不是整条变实心。这里复刻这套
/// 层次，并把「取消」做成分离的玻璃胶囊，避免整条控件被三等分成方块。
class SearchFieldBar extends StatefulWidget {
  const SearchFieldBar({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.hintText,
    required this.onSubmit,
    required this.onClear,
    this.onChanged,
    this.onBack,
    this.backTooltip,
    this.onCancel,
    this.cancelLabel,
    this.clearTooltip,
    this.submitTooltip,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String hintText;
  final ValueChanged<String> onSubmit;
  final VoidCallback onClear;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onBack;
  final String? backTooltip;
  final VoidCallback? onCancel;
  final String? cancelLabel;
  final String? clearTooltip;
  final String? submitTooltip;
  final bool autofocus;

  static const double height = 48;

  @override
  State<SearchFieldBar> createState() => _SearchFieldBarState();
}

class _SearchFieldBarState extends State<SearchFieldBar> {
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(covariant SearchFieldBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_onFocusChanged);
      widget.focusNode.addListener(_onFocusChanged);
    }
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChanged);
    super.dispose();
  }

  void _onFocusChanged() {
    if (widget.focusNode.hasFocus == _focused) return;
    setState(() => _focused = widget.focusNode.hasFocus);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppColors.isDark(context);
    final muted = AppColors.mutedText(context);
    final primary = AppColors.onScaffold(context);
    final accent = AppColors.accentOf(context);
    // 浅色下输入行的白底和面板几乎同色，只靠 hairline 是分不出边界的；
    // 补一条更实的边 + 一层浅投影，聚焦时边线转成强调色。
    final edge = _focused
        ? accent.withValues(alpha: 0.48)
        : (isDark
              ? Colors.white.withValues(alpha: 0.14)
              : const Color(0xFF3C3C43).withValues(alpha: 0.16));

    return Row(
      children: [
        if (widget.onBack != null) ...[
          IconButton(
            tooltip: widget.backTooltip,
            onPressed: widget.onBack,
            icon: Icon(Icons.arrow_back_rounded, size: 21, color: primary),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 40, height: 40),
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: SizedBox(
            height: SearchFieldBar.height,
            // 返回箭头与搜索图标属于同一条 chrome，不再悬在输入框左侧形成
            // 第二条基线；这样输入栏、平台栏和结果区可以共用外层内缩。
            child: AnimatedScale(
              scale: _focused ? 1 : 0.995,
              duration: motionDuration(context, MotionDuration.micro),
              curve: MotionCurve.easeOutQuart,
              child: GlassSurface(
                style: AppGlassStyle.chrome,
                borderRadius: BorderRadius.circular(18),
                emphasized: _focused,
                border: Border.all(color: edge, width: _focused ? 1 : 0.8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.20 : 0.06),
                    blurRadius: 12,
                    offset: const Offset(0, 3),
                  ),
                ],
                child: Row(
                  children: [
                    const SizedBox(width: 14),
                    Icon(
                      Icons.search_rounded,
                      size: 17,
                      color: _focused ? accent : muted,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: widget.controller,
                        focusNode: widget.focusNode,
                        autofocus: widget.autofocus,
                        textInputAction: TextInputAction.search,
                        onChanged: widget.onChanged,
                        onSubmitted: widget.onSubmit,
                        cursorColor: accent,
                        cursorWidth: 1.6,
                        cursorRadius: const Radius.circular(2),
                        style: TextStyle(
                          color: primary,
                          fontSize: 15,
                          height: 1.2,
                          fontWeight: FontWeight.w500,
                          letterSpacing: -0.1,
                        ),
                        decoration: InputDecoration(
                          hintText: widget.hintText,
                          hintStyle: TextStyle(
                            color: muted,
                            fontSize: 15,
                            height: 1.2,
                            fontWeight: FontWeight.w400,
                          ),
                          border: InputBorder.none,
                          isDense: true,
                          filled: false,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 14,
                          ),
                        ),
                      ),
                    ),
                    // 清除 / 提交都用直径小于行高的圆形按钮：靠右对齐时
                    // 视觉重心才落在输入行中线上。
                    // 直接监听 controller：父级是否 setState 都不会漏掉
                    // 「有 / 无文字」，也不必为两个小按钮重建整个页面。
                    ValueListenableBuilder<TextEditingValue>(
                      valueListenable: widget.controller,
                      builder: (context, value, _) => AnimatedSize(
                        duration: motionDuration(context, MotionDuration.micro),
                        curve: MotionCurve.easeOutQuart,
                        alignment: Alignment.centerRight,
                        child: value.text.isEmpty
                            ? const SizedBox.shrink()
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _CircleAction(
                                    tooltip: widget.clearTooltip ?? '',
                                    size: 20,
                                    background: primary.withValues(alpha: 0.10),
                                    icon: Icon(
                                      Icons.close_rounded,
                                      size: 13,
                                      color: primary.withValues(alpha: 0.72),
                                    ),
                                    onTap: widget.onClear,
                                  ),
                                  const SizedBox(width: 6),
                                  _CircleAction(
                                    tooltip: widget.submitTooltip ?? '',
                                    size: 30,
                                    background: accent,
                                    icon: Icon(
                                      Icons.arrow_forward_rounded,
                                      size: 17,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onPrimary,
                                    ),
                                    onTap: () =>
                                        widget.onSubmit(widget.controller.text),
                                  ),
                                ],
                              ),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (widget.onCancel != null) ...[
          const SizedBox(width: 8),
          SearchCancelButton(
            label: widget.cancelLabel ?? '取消',
            onTap: widget.onCancel!,
          ),
        ],
      ],
    );
  }
}

class _CircleAction extends StatelessWidget {
  const _CircleAction({
    required this.tooltip,
    required this.size,
    required this.background,
    required this.icon,
    required this.onTap,
  });

  final String tooltip;
  final double size;
  final Color background;
  final Widget icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final button = Material(
      color: background,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: Center(child: icon),
        ),
      ),
    );
    if (tooltip.isEmpty) return button;
    return Tooltip(message: tooltip, child: button);
  }
}

/// 独立的「取消」玻璃胶囊。
///
/// 竖屏时挂在输入行右侧；横屏可用高度紧张，输入行和平台胶囊要挤在一行，
/// 它会被搬到最右端，所以做成公开组件而不是输入行的私有部分。
class SearchCancelButton extends StatelessWidget {
  const SearchCancelButton({
    super.key,
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: SearchFieldBar.height,
      child: GlassSurface(
        style: AppGlassStyle.chrome,
        borderRadius: BorderRadius.circular(SearchFieldBar.height / 2),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(SearchFieldBar.height / 2),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Center(
                child: Text(
                  label,
                  style: TextStyle(
                    color: AppColors.secondaryText(context),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.1,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 音源平台切换。下拉菜单把可选平台藏进一次点击里，横排胶囊让「还有
/// 哪些源」直接可见，也顺手解决了窄屏上平台名被截断的问题。
class SearchSourceChips extends StatelessWidget {
  const SearchSourceChips({
    super.key,
    required this.sources,
    required this.selectedId,
    required this.onSelected,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
  });

  final List<SearchSourceItem> sources;
  final String selectedId;
  final ValueChanged<String> onSelected;
  final EdgeInsetsGeometry padding;

  static const double height = 32;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      // 右端渐隐：平台比一屏多时，被裁掉的半个胶囊比一条生硬的切口
      // 更能说明「这里还能滑」。
      child: ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (rect) => const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [Colors.white, Colors.white, Colors.transparent],
          stops: [0, 0.93, 1],
        ).createShader(rect),
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: padding,
          physics: const BouncingScrollPhysics(),
          itemCount: sources.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            final source = sources[index];
            return _SourceChip(
              label: source.name,
              selected: source.id == selectedId,
              onTap: () => onSelected(source.id),
            );
          },
        ),
      ),
    );
  }
}

class _SourceChip extends StatelessWidget {
  const _SourceChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.accentOf(context);
    final primary = AppColors.onScaffold(context);
    final border = AppColors.cardBorder(context);
    // AnimatedDefaultTextStyle 的样式是整体替换而非合并；自己拼一个裸
    // TextStyle 会把主题字体（以及中文回退）一起丢掉。
    final base = DefaultTextStyle.of(context).style;
    // 平台上直接叠磨砂会和面板自身的模糊打架（尤其浅色下会发灰），
    // 用同族色的半透明填充 + 细边线就能在玻璃上站住。
    final background = selected
        ? accent.withValues(alpha: AppColors.isDark(context) ? 0.18 : 0.10)
        : primary.withValues(alpha: AppColors.isDark(context) ? 0.035 : 0.025);
    final side = selected
        ? accent.withValues(alpha: 0.46)
        : border.withValues(alpha: 0.42);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: motionDuration(context, MotionDuration.normal),
        curve: MotionCurve.easeOutQuart,
        height: SearchSourceChips.height,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: side, width: selected ? 0.8 : 0.45),
        ),
        child: AnimatedDefaultTextStyle(
          duration: motionDuration(context, MotionDuration.normal),
          curve: MotionCurve.easeOutQuart,
          style: base.copyWith(
            color: selected ? accent : AppColors.secondaryText(context),
            fontSize: 12.5,
            height: 1.0,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            letterSpacing: -0.1,
          ),
          child: Text(label),
        ),
      ),
    );
  }
}

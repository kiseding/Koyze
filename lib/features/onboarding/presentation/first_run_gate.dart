import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../l10n/app_strings.dart';
import '../../settings/presentation/settings_provider.dart';

/// 首启条款闸门。
///
/// 挂在 `MaterialApp.router` 的 builder 上，盖住整个导航树：没同意条款之前
/// 后面的页面不该被访问到，先渲染再遮住也会闪一下。
///
/// 这里只做一件事——让用户读条款并明确同意。曾经的三步引导（条款 → 配音源
/// → 完成）已经去掉：配音源属于「用起来之后自然会做的事」，塞进首启只会让
/// 第一次打开变成填表；而条款是必须留下的一道门。
class FirstRunGate extends ConsumerStatefulWidget {
  const FirstRunGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<FirstRunGate> createState() => _FirstRunGateState();
}

class _FirstRunGateState extends ConsumerState<FirstRunGate> {
  bool _agreed = false;

  bool get _accepted => ref.watch(onboardingAcceptedProvider);

  void _accept() {
    if (!_agreed) return;
    ref.read(onboardingAcceptedProvider.notifier).setAccepted(true);
  }

  @override
  Widget build(BuildContext context) {
    if (_accepted) return widget.child;

    final s = S.of(context);
    final accent = AppColors.accentOf(context);
    final onAccent = AppColors.onAccentOf(context);
    final muted = AppColors.mutedText(context);
    final secondary = AppColors.secondaryText(context);

    return Stack(
      children: [
        // 底下这层是真实界面，同意之后不需要重建路由栈。
        Positioned.fill(child: widget.child),
        Positioned.fill(
          // 用 Material 而不是 ColoredBox：下面的整行可点区域（InkWell）
          // 和 Checkbox 都需要 Material 祖先才能画水波纹，缺了会直接抛
          // 「No Material widget found」。
          child: Material(
            color: AppColors.scaffold(context),
            child: SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 26, 24, 22),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight - 48,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        // 内容在上、操作在下：高屏上按钮贴底，短屏上整体可滚。
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _BrandMark(accent: accent),
                              const SizedBox(height: 26),
                              Text(
                                s.onboardingTermsEyebrow.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 11,
                                  height: 1.2,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.6,
                                  color: accent,
                                  decoration: TextDecoration.none,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                s.onboardingTermsTitle,
                                style: TextStyle(
                                  fontSize: 27,
                                  height: 1.2,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.4,
                                  color: AppColors.onScaffold(context),
                                  decoration: TextDecoration.none,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                s.onboardingTermsIntro,
                                style: TextStyle(
                                  fontSize: 13.5,
                                  height: 1.6,
                                  color: secondary,
                                  decoration: TextDecoration.none,
                                ),
                              ),
                              const SizedBox(height: 22),
                              _TermsCard(
                                points: s.onboardingTermsPoints,
                                accent: accent,
                                secondary: secondary,
                              ),
                            ],
                          ),
                          Padding(
                            padding: const EdgeInsets.only(top: 18),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _ConsentRow(
                                  value: _agreed,
                                  label: s.onboardingTermsConsent,
                                  accent: accent,
                                  secondary: secondary,
                                  onChanged: (value) =>
                                      setState(() => _agreed = value),
                                ),
                                const SizedBox(height: 14),
                                FilledButton(
                                  onPressed: _agreed ? _accept : null,
                                  style: FilledButton.styleFrom(
                                    backgroundColor: accent,
                                    foregroundColor: onAccent,
                                    disabledBackgroundColor: accent.withValues(
                                      alpha: 0.14,
                                    ),
                                    disabledForegroundColor: muted,
                                    elevation: 0,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 15,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                  child: Text(
                                    s.onboardingContinue,
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Center(
                                  child: Text(
                                    s.onboardingTermsFootnote,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      height: 1.4,
                                      color: muted,
                                      decoration: TextDecoration.none,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 左上角的品牌标记：一个带主题色渐变的圆角方块。
class _BrandMark extends StatelessWidget {
  const _BrandMark({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(13),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                accent,
                Color.lerp(accent, Colors.black, 0.22) ?? accent,
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: 0.28),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: const Icon(
            Icons.graphic_eq_rounded,
            size: 22,
            color: Colors.white,
          ),
        ),
        const SizedBox(width: 11),
        Text(
          'Koyze',
          style: TextStyle(
            fontSize: 17,
            height: 1.1,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
            color: AppColors.onScaffold(context),
            decoration: TextDecoration.none,
          ),
        ),
      ],
    );
  }
}

/// 条款正文。用编号卡片承载，长段落也不会糊成一片。
class _TermsCard extends StatelessWidget {
  const _TermsCard({
    required this.points,
    required this.accent,
    required this.secondary,
  });

  final List<String> points;
  final Color accent;
  final Color secondary;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
      decoration: BoxDecoration(
        color: AppColors.fill2(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.cardBorder(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < points.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 21,
                    height: 21,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.14),
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '${i + 1}',
                      style: TextStyle(
                        fontSize: 11,
                        height: 1,
                        fontWeight: FontWeight.w700,
                        color: accent,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Text(
                        points[i],
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.65,
                          color: secondary,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// 「我已阅读并同意」——整行可点，不必精确点中复选框。
class _ConsentRow extends StatelessWidget {
  const _ConsentRow({
    required this.value,
    required this.label,
    required this.accent,
    required this.secondary,
    required this.onChanged,
  });

  final bool value;
  final String label;
  final Color accent;
  final Color secondary;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 26,
              height: 26,
              child: Checkbox(
                value: value,
                onChanged: (next) => onChanged(next ?? false),
                activeColor: accent,
                checkColor: AppColors.onAccentOf(context),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
                side: BorderSide(
                  color: AppColors.cardBorder(context),
                  width: 1.4,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(7),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.45,
                  color: secondary,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

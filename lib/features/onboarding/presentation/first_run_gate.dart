import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/pressable.dart';
import '../../../l10n/app_strings.dart';
import '../../custom_source/presentation/custom_source_provider.dart';
import '../../custom_source/presentation/custom_source_screen.dart';
import '../../settings/presentation/settings_provider.dart';

/// 首启引导。
///
/// 挂在 `MaterialApp.router` 的 builder 上，盖住整个导航树：还没同意条款时
/// 后面的页面不该被访问到，先渲染再遮住也会闪一下。
///
/// 步骤**不存进度**，每次由真实状态推导：
///   1. 未同意 → 条款；
///   2. 已同意但没有任何音源 → 配音源（可跳过）；
///   3. 其余 → 直接放行。
/// 这样中途被杀、或者配好音源后又全关掉，再打开都会落回正确的一步。
class FirstRunGate extends ConsumerStatefulWidget {
  const FirstRunGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<FirstRunGate> createState() => _FirstRunGateState();
}

class _FirstRunGateState extends ConsumerState<FirstRunGate> {
  final PageController _controller = PageController();
  int _step = 0;
  bool _skippedSources = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _accepted => ref.watch(onboardingAcceptedProvider);

  void _goTo(int step) {
    setState(() => _step = step);
    _controller.animateToPage(
      step,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_accepted) return widget.child;

    final hasSource = ref.watch(hasEnabledCustomSourceProvider);
    // 已经配过音源的用户不该再被拦一次：直接从条款进到完成。
    final effectiveStep = _step == 1 && hasSource ? 2 : _step;

    return Stack(
      children: [
        // 底下这层是真实界面，引导关掉后不需要重建路由栈。
        Positioned.fill(child: widget.child),
        Positioned.fill(
          child: ColoredBox(
            color: AppColors.scaffold(context),
            child: SafeArea(
              child: Column(
                children: [
                  Expanded(
                    child: PageView(
                      controller: _controller,
                      physics: const NeverScrollableScrollPhysics(),
                      children: [
                        _TermsPage(onAccept: () {
                          ref
                              .read(onboardingAcceptedProvider.notifier)
                              .setAccepted(true);
                          _goTo(hasSource ? 2 : 1);
                        }),
                        _SourcePage(
                          onConfigure: () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => const CustomSourceScreen(),
                              ),
                            );
                            if (!context.mounted) return;
                            if (ref.read(hasEnabledCustomSourceProvider)) {
                              _goTo(2);
                            }
                          },
                          onSkip: () {
                            setState(() => _skippedSources = true);
                            _goTo(2);
                          },
                        ),
                        _DonePage(
                          skippedSources: _skippedSources,
                          onFinish: () => Navigator.of(context).maybePop(),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var i = 0; i < 3; i++)
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 220),
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            width: i == effectiveStep ? 18 : 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: i == effectiveStep
                                  ? AppColors.accentOf(context)
                                  : AppColors.cardBorder(context),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (effectiveStep == 2) const SizedBox.shrink(),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _TermsPage extends StatelessWidget {
  const _TermsPage({required this.onAccept});

  final VoidCallback onAccept;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 32, 28, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.music_note_rounded,
            size: 34,
            color: AppColors.accentOf(context),
          ),
          const SizedBox(height: 18),
          Text(
            s.onboardingWelcome,
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              color: AppColors.onScaffold(context),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            s.onboardingTermsIntro,
            style: TextStyle(
              fontSize: 13.5,
              height: 1.6,
              color: AppColors.secondaryText(context),
            ),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final line in s.onboardingTermsPoints)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 6, right: 8),
                            child: Container(
                              width: 4,
                              height: 4,
                              decoration: BoxDecoration(
                                color: AppColors.mutedText(context),
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              line,
                              style: TextStyle(
                                fontSize: 12.5,
                                height: 1.6,
                                color: AppColors.secondaryText(context),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onAccept,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accentOf(context),
                foregroundColor: AppColors.onAccentOf(context),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: Text(s.onboardingAgree),
            ),
          ),
        ],
      ),
    );
  }
}

class _SourcePage extends StatelessWidget {
  const _SourcePage({required this.onConfigure, required this.onSkip});

  final VoidCallback onConfigure;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 32, 28, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.extension_outlined,
            size: 32,
            color: AppColors.accentOf(context),
          ),
          const SizedBox(height: 18),
          Text(
            s.onboardingSourceTitle,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: AppColors.onScaffold(context),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            s.onboardingSourceBody,
            style: TextStyle(
              fontSize: 13.5,
              height: 1.65,
              color: AppColors.secondaryText(context),
            ),
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onConfigure,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accentOf(context),
                foregroundColor: AppColors.onAccentOf(context),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: Text(s.onboardingSourceConfigure),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: onSkip,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.mutedText(context),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: Text(s.onboardingSkip),
            ),
          ),
        ],
      ),
    );
  }
}

class _DonePage extends StatelessWidget {
  const _DonePage({required this.skippedSources, required this.onFinish});

  final bool skippedSources;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 32, 28, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.check_circle_outline_rounded,
            size: 32,
            color: AppColors.accentOf(context),
          ),
          const SizedBox(height: 18),
          Text(
            s.onboardingDoneTitle,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: AppColors.onScaffold(context),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            skippedSources ? s.onboardingDoneNoSource : s.onboardingDoneBody,
            style: TextStyle(
              fontSize: 13.5,
              height: 1.65,
              color: AppColors.secondaryText(context),
            ),
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: Pressable(
              onTap: onFinish,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.accentOf(context),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  s.onboardingStart,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.onAccentOf(context),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

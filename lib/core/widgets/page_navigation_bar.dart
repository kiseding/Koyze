import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'fx_icon_button.dart';

class PageNavigationBar extends StatelessWidget {
  const PageNavigationBar({
    super.key,
    required this.pageIndex,
    required this.pageCount,
    required this.onPageChanged,
    this.enabled = true,
  });

  final int pageIndex;
  final int pageCount;
  final ValueChanged<int> onPageChanged;
  final bool enabled;

  /// 胶囊实际距离屏幕底部 32px：相当于典型 iOS 安全区 34px + 原间距
  /// 8px 后整体下移 10px；Android / Windows 也使用同一实际距离。
  static const double bottomClearance = 32;

  /// 胶囊高度 58 + 跨平台统一底距 32。
  static const double floatingExtent = 90;

  /// 最后一行歌曲与胶囊之间的可见间距。
  static const double contentClearance = 24;

  /// 列表需要预留的底部空间，保证最后一行可以滚到分页栏上方。
  static const double listBottomPadding = floatingExtent + contentClearance;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final bottomInset = media.padding.bottom > media.viewPadding.bottom
        ? media.padding.bottom
        : media.viewPadding.bottom;
    if (pageCount <= 1) return SizedBox(height: bottomInset);
    return SizedBox(
      height: floatingExtent,
      child: Padding(
        padding: const EdgeInsets.only(bottom: bottomClearance),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            height: 58,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.miniBar(context),
              borderRadius: BorderRadius.circular(29),
              border: Border.all(color: AppColors.cardBorder(context)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(
                    alpha: AppColors.isDark(context) ? 0.28 : 0.12,
                  ),
                  blurRadius: 16,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildArrowButton(context, isPrevious: true),
                const SizedBox(width: 2),
                _buildPageTextButton(context),
                const SizedBox(width: 2),
                _buildArrowButton(context, isPrevious: false),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPageTextButton(BuildContext context) {
    return TextButton(
      onPressed: enabled ? () => _showPagePickerDialog(context) : null,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: const Size(48, 48),
        maximumSize: const Size(double.infinity, 48),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(
        '第 ${pageIndex + 1} / $pageCount 页',
        style: TextStyle(
          fontSize: 15,
          color: AppColors.secondaryText(context),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildArrowButton(BuildContext context, {required bool isPrevious}) {
    final arrowEnabled =
        enabled && (isPrevious ? pageIndex > 0 : pageIndex + 1 < pageCount);
    final foreground = arrowEnabled
        ? AppColors.secondaryText(context)
        : AppColors.mutedText(context).withValues(alpha: 0.5);
    return SizedBox.square(
      dimension: 48,
      child: FxIconButton(
        tooltip: isPrevious ? '上一页' : '下一页',
        onPressed: arrowEnabled
            ? () => onPageChanged(pageIndex + (isPrevious ? -1 : 1))
            : null,
        icon: Icon(
          isPrevious ? Icons.chevron_left : Icons.chevron_right,
          size: 20,
          color: foreground,
        ),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 48, height: 48),
      ),
    );
  }

  Future<void> _showPagePickerDialog(BuildContext context) async {
    final selected = await showDialog<int>(
      context: context,
      builder: (context) {
        final scheme = Theme.of(context).colorScheme;
        return AlertDialog(
          title: const Text('选择页码'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320, minWidth: 300),
            child: GridView.builder(
              shrinkWrap: true,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 5,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 1.5,
              ),
              itemCount: pageCount,
              itemBuilder: (context, index) {
                final page = index + 1;
                final isCurrent = index == pageIndex;
                return Material(
                  color: isCurrent
                      ? scheme.primaryContainer
                      : scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => Navigator.pop(context, page),
                    child: Center(
                      child: Text(
                        '$page',
                        style: TextStyle(
                          color: isCurrent
                              ? scheme.onPrimaryContainer
                              : scheme.onSurface,
                          fontWeight: isCurrent ? FontWeight.w600 : null,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
          ],
        );
      },
    );
    if (selected == null) return;
    onPageChanged((selected - 1).clamp(0, pageCount - 1).toInt());
  }
}

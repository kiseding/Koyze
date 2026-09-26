import 'package:flutter/material.dart';
import '../performance/low_memory.dart';
import '../theme/app_colors.dart';

/// Loading spinner that keeps animating on low-memory devices.
class AppLoadingIndicator extends StatelessWidget {
  const AppLoadingIndicator({
    super.key,
    this.value,
    this.strokeWidth,
    this.color,
    this.valueColor,
    this.backgroundColor,
  });

  final double? value;
  final double? strokeWidth;
  final Color? color;
  final Animation<Color?>? valueColor;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final indicator = CircularProgressIndicator(
      value: value,
      strokeWidth: strokeWidth ?? 4,
      color: color,
      valueColor: valueColor,
      backgroundColor: backgroundColor,
    );
    if (!LowMemory.active) return indicator;
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: false),
      child: indicator,
    );
  }
}

class LoadingWidget extends StatelessWidget {
  final String? hint;

  const LoadingWidget({super.key, this.hint});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: AppLoadingIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.amber),
            ),
          ),
          if (hint != null) ...[
            const SizedBox(height: 12),
            Text(
              hint!,
              style: TextStyle(
                color: AppColors.mutedText(context),
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// URL/email keyboard types on desktop swallow Shift for `;`/`:`, so typing
/// `https://` becomes `https;//`. Keep a normal text keyboard there.
///
/// 分支保持「枚举值不加 ohos」：`TargetPlatform.ohos` 只在鸿蒙 Flutter fork 里
/// 存在，上游 Flutter（五个平台的 CI 用的）没有这个常量，引用它会让 analyze
/// 直接报 undefined_enum_constant。ohos 落进 default 分支，行为与移动端一致。
TextInputType desktopSafeKeyboardType(TextInputType type) {
  switch (defaultTargetPlatform) {
    case TargetPlatform.windows:
    case TargetPlatform.linux:
    case TargetPlatform.macOS:
      if (type == TextInputType.url || type == TextInputType.emailAddress) {
        return TextInputType.text;
      }
      return type;
    default:
      // Android / iOS / fuchsia / ohos：保持原键盘类型。
      return type;
  }
}

/// Requests focus for a text input and explicitly asks the platform IME to show.
///
/// `autofocus: true` alone can be ignored when a dialog/sheet is still entering.
/// This helper retries once after the first frame so mobile keyboards appear
/// reliably for freshly opened input flows. For animated dialogs, pass
/// [initialDelay] so the IME request lands after the route transition settles.
void requestTextInput(
  BuildContext context,
  FocusNode focusNode, {
  bool Function()? canRequest,
  Duration initialDelay = Duration.zero,
  Duration retryDelay = const Duration(milliseconds: 120),
}) {
  void show() {
    if (!context.mounted || !focusNode.canRequestFocus) return;
    if (canRequest != null && !canRequest()) return;
    FocusScope.of(context).requestFocus(focusNode);
    unawaited(SystemChannels.textInput.invokeMethod<void>('TextInput.show'));
  }

  void schedule(Duration delay) {
    if (delay == Duration.zero) {
      show();
    } else {
      unawaited(Future<void>.delayed(delay, show));
    }
  }

  WidgetsBinding.instance.addPostFrameCallback((_) {
    schedule(initialDelay);
    schedule(initialDelay + retryDelay);
  });
}

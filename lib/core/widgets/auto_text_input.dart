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
///
/// 刻意**不接收 BuildContext**：这个函数是在 post-frame 回调里干活的。
/// `FocusScope.of(context)` 会顺带给那个元素登记一条 inherited 依赖——回调真
/// 跑起来时弹窗可能正在关闭，这条迟到的登记就落在了一个生命周期已不可信的
/// 元素上。真机 debug 构建上「关掉带键盘的弹窗后立刻再开一个」会撞到
/// `InheritedElement.debugDeactivated` 的 `_dependents.isEmpty` 断言、整屏红，
/// 这是那条路径里唯一会改 widget 树的动作，因此把它去掉。
///
/// `FocusNode.requestFocus()` 只走焦点树，不碰 widget 树；节点还没挂进焦点
/// 树时会记下 `_requestFocusWhenReparented`，挂载后自动补上，正是弹窗场景
/// 需要的行为。
void requestTextInput(
  FocusNode focusNode, {
  bool Function()? canRequest,
  Duration initialDelay = Duration.zero,
  Duration retryDelay = const Duration(milliseconds: 120),
}) {
  void show() {
    if (!focusNode.canRequestFocus) return;
    if (canRequest != null && !canRequest()) return;
    focusNode.requestFocus();
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

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

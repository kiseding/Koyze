import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Requests focus for a text input and explicitly asks the platform IME to show.
///
/// `autofocus: true` alone can be ignored when a dialog/sheet is still entering.
/// This helper retries once after the first frame so mobile keyboards appear
/// reliably for freshly opened input flows.
void requestTextInput(
  BuildContext context,
  FocusNode focusNode, {
  bool Function()? canRequest,
}) {
  void show() {
    if (!context.mounted || !focusNode.canRequestFocus) return;
    if (canRequest != null && !canRequest()) return;
    FocusScope.of(context).requestFocus(focusNode);
    unawaited(SystemChannels.textInput.invokeMethod<void>('TextInput.show'));
  }

  WidgetsBinding.instance.addPostFrameCallback((_) {
    show();
    unawaited(Future<void>.delayed(const Duration(milliseconds: 120), show));
  });
}

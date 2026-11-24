// Copyright 2024 Koyze Contributors
// Licensed under the Apache License, Version 2.0

/// 跨平台剪贴板读写。
///
/// ## 为什么不用 `Clipboard` 直接调
///
/// Flutter 自带的 `Clipboard` 走 `SystemChannels.platform` 的
/// `Clipboard.setData` / `Clipboard.getData`。鸿蒙引擎对这两个方法没有实现，
/// 而该通道是 `OptionalMethodChannel`——方法不存在时**不抛异常**，只静默
/// 返回 null。表现是：点「复制」毫无反应、点「剪切板」永远提示「剪切板中
/// 没有链接」，日志里一个字都没有。
///
/// 这里在鸿蒙上改走 `koyze/clipboard` 通道（实现见
/// `ohos/entry/src/main/ets/entryability/ClipboardBridge.ets`），其它平台
/// 仍用 Flutter 自带实现——不为一个平台改变已有行为。
///
/// ## 写入与读取不对称
///
/// 鸿蒙的 pasteboard **写入不需要权限**，所以复制能修好。读取从 API 12 起
/// 受管控：普通应用只能通过「粘贴控件」（PasteButton 安全控件）读取，或者
/// 申请 `ohos.permission.READ_PASTEBOARD`——那是 system_basic 级的受限权限，
/// 要在 AGC 申请 Profile 才能生效，自签构建拿不到。
///
/// 因此读取要区分「没有内容」和「系统没给权限」：后者继续显示
/// 「剪贴板是空的」会误导用户以为复制失败了。本应用没有声明那个受限权限
/// （声明了但 Profile 里没有 ACL，鸿蒙会直接拒绝安装），所以未授权时只能
/// 提示用户手动粘贴。
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 鸿蒙剪贴板通道。
const MethodChannel _ohosChannel = MethodChannel('koyze/clipboard');

/// 是否走鸿蒙原生剪贴板。
bool get _useOhosBridge => !kIsWeb && Platform.operatingSystem == 'ohos';

/// 读取剪贴板的结果。
enum ClipboardReadStatus {
  /// 读到了文本。
  text,

  /// 剪贴板里没有文本（空，或只有图片、文件）。
  empty,

  /// 系统拒绝读取（鸿蒙未授予剪贴板权限）。
  denied,
}

/// 一次剪贴板读取的结果。
class ClipboardReadResult {
  const ClipboardReadResult(this.status, [this.text]);

  const ClipboardReadResult.empty() : this(ClipboardReadStatus.empty);
  const ClipboardReadResult.denied() : this(ClipboardReadStatus.denied);
  const ClipboardReadResult.withText(String value)
    : this(ClipboardReadStatus.text, value);

  final ClipboardReadStatus status;

  /// 仅当 [status] 为 [ClipboardReadStatus.text] 时有值。
  final String? text;
}

/// 写入剪贴板。
///
/// 鸿蒙通道失败时回退到 Flutter 自带实现，宁可退化也不让复制直接失效。
Future<void> setClipboardText(String text) async {
  if (_useOhosBridge) {
    try {
      await _ohosChannel.invokeMethod<void>('setData', {'text': text});
      return;
    } on PlatformException catch (error) {
      debugPrint('[Clipboard] 鸿蒙通道写入失败，回退系统实现: $error');
    } on MissingPluginException catch (error) {
      debugPrint('[Clipboard] 鸿蒙通道未注册，回退系统实现: $error');
    }
  }
  await Clipboard.setData(ClipboardData(text: text));
}

/// 读取剪贴板纯文本。
Future<ClipboardReadResult> readClipboard() async {
  if (_useOhosBridge) {
    try {
      final text = await _ohosChannel.invokeMethod<String>('getData');
      if (text == null || text.isEmpty) {
        return const ClipboardReadResult.empty();
      }
      return ClipboardReadResult.withText(text);
    } on PlatformException catch (error) {
      if (error.code == 'clipboard_denied') {
        return const ClipboardReadResult.denied();
      }
      debugPrint('[Clipboard] 鸿蒙通道读取失败: ${error.code} ${error.message}');
      return const ClipboardReadResult.empty();
    } on MissingPluginException catch (error) {
      debugPrint('[Clipboard] 鸿蒙通道未注册，回退系统实现: $error');
    }
  }
  final data = await Clipboard.getData(Clipboard.kTextPlain);
  final text = data?.text;
  if (text == null || text.isEmpty) return const ClipboardReadResult.empty();
  return ClipboardReadResult.withText(text);
}

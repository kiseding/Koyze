/*
 * Copyright 2024 Koyze Contributors
 * Licensed under the Apache License, Version 2.0
 */

import MethodCall from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodCall';
import { MethodCallHandler, MethodResult } from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';
import { pasteboard } from '@kit.BasicServicesKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0000;
const TAG: string = 'KoyzeClipboard';

/// Dart 侧的 `MethodChannel('koyze/clipboard')`。
///
/// ## 为什么鸿蒙要单独实现
///
/// Flutter 自带的 `Clipboard.setData` / `getData` 走
/// `SystemChannels.platform`，而鸿蒙引擎没有实现这两个方法。该通道是
/// `OptionalMethodChannel`：方法不存在时不抛异常，只回 null。于是点击「复制」
/// 毫无反应、点「剪切板」永远提示内容为空，且日志里一个字都没有——看起来
/// 像是应用逻辑写错了。
///
/// 这里用系统 pasteboard 补上，协议与 Dart 侧 `app_clipboard.dart` 对应：
/// `setData{text}` / `getData -> String`。写入不需要权限；读取从 API 12 起
/// 受管控，未授权时回 `clipboard_denied`，由界面提示用户手动粘贴。
export default class ClipboardBridge implements MethodCallHandler {
  private readonly context: common.UIAbilityContext;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    // onMethodCall 必须同步返回，真正的异步操作在 dispatch 里跑；
    // dispatch 已把全部失败转成 result.error，这里只兜底「回调都没发出去」
    // 的极端情况，避免 Dart 侧永远挂在 await 上。
    this.dispatch(call, result).catch((error: Object) => {
      const failure = error as BusinessError;
      const code: number = failure.code === undefined ? -1 : failure.code;
      hilog.error(DOMAIN, TAG, 'dispatch crashed, code=%{public}d msg=%{public}s',
        code, (error as Error).message ?? 'unknown');
      result.error('clipboard_failed', '剪贴板操作失败', null);
    });
  }

  private async dispatch(call: MethodCall, result: MethodResult): Promise<void> {
    const method: string = call.method;
    if (method === 'setData') {
      await this.setData(call, result);
      return;
    }
    if (method === 'getData') {
      await this.getData(result);
      return;
    }
    result.notImplemented();
  }

  /// 写入。鸿蒙的 pasteboard 不需要权限，这里失败就是真的写不进去。
  private async setData(call: MethodCall, result: MethodResult): Promise<void> {
    try {
      const text: string = this.strArg(call, 'text');
      const data: pasteboard.PasteboardData =
        pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
      await pasteboard.getSystemPasteboard(this.context).setData(data);
      // Dart 侧 invokeMethod<void> 不读返回值，回空串即可。
      result.success('');
    } catch (error) {
      const failure = error as BusinessError;
      const code: number = failure.code === undefined ? -1 : failure.code;
      hilog.error(DOMAIN, TAG, 'setData failed, code=%{public}d msg=%{public}s',
        code, (error as Error).message ?? 'unknown');
      result.error('clipboard_failed', (error as Error).message ?? '剪贴板不可用', null);
    }
  }

  /// 读取。
  ///
  /// 鸿蒙从 API 12 起限制普通应用读取剪贴板：要么用 PasteButton 安全控件，
  /// 要么申请受限权限 `ohos.permission.READ_PASTEBOARD`（system_basic，
  /// 需 AGC 审批 Profile）。本应用两者都没有，所以这里大概率会拿到
  /// 201（权限校验失败）——必须把这种失败和「剪贴板是空的」区分开，
  /// 否则界面会一直说「剪贴板中没有内容」，而用户明明刚复制过。
  private async getData(result: MethodResult): Promise<void> {
    try {
      const data: pasteboard.PasteboardData =
        await pasteboard.getSystemPasteboard(this.context).getData();
      // 非文本条目（图片、文件）取不到纯文本，返回空串由 Dart 侧当作
      // 「没有可用内容」，与 Flutter 其它平台的行为一致。
      const text: string = data.getPrimaryText();
      result.success(text === undefined || text === null ? '' : text);
    } catch (error) {
      const failure = error as BusinessError;
      const code: number = failure.code === undefined ? -1 : failure.code;
      const message: string = (error as Error).message ?? '';
      const denied: boolean = code === 201 ||
        message.toLowerCase().indexOf('permission') >= 0;
      hilog.warn(DOMAIN, TAG, 'getData failed, code=%{public}d denied=%{public}s msg=%{public}s',
        code, denied ? 'true' : 'false', message);
      if (denied) {
        result.error('clipboard_denied', message === '' ? '剪贴板读取未授权' : message, null);
        return;
      }
      // 空剪贴板、没有文本记录等业务错误：按「没有内容」返回，不报错。
      result.success('');
    }
  }

  private strArg(call: MethodCall, name: string): string {
    const value: Object = call.argument(name);
    if (value === undefined || value === null) return '';
    return value as string;
  }
}

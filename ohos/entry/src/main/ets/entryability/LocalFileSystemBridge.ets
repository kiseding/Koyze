/*
 * Copyright 2024 Koyze Contributors
 * Licensed under the Apache License, Version 2.0
 */

import MethodCall from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodCall';
import { MethodCallHandler, MethodResult } from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';
import { fileIo as fs, picker } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0000;
const TAG: string = 'KoyzeFileSystem';

/// Dart 侧的 `MethodChannel('koyze/local_file_system')`。
///
/// 与 Android / iOS 走同一套线上协议（方法名、参数名、返回形态都一致），
/// 这样 `LocalFileSystem` 的三个平台实现只需要一个 Dart 类去解析。
///
/// HarmonyOS 和 Android 有个关键差别：这里**不需要** SAF 那套 `content://`
/// 文档树。鸿蒙的 `@ohos.file.fs` 直接接受普通路径，也接受 DocumentViewPicker
/// 返回的 `file://docs/...` URI，两者用法一样。所以实现是纯路径式的，
/// 比 Android 简单一档。
///
/// 目录选择也在这里做：`file_picker` 的 ohos 移植把 `dir` 当成选文件处理，
/// 返回的是缓存目录里的副本路径，没法当目录用。所以鸿蒙自己实现
/// `pickDirectory`，Dart 侧只在这个平台调它。
export default class LocalFileSystemBridge implements MethodCallHandler {
  private readonly context: common.UIAbilityContext;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    // onMethodCall 必须是同步返回的，真正的 IO 在 dispatch 里异步跑。
    // dispatch 内部已经把所有失败都转成了 result.error，这里只兜底
    // 「连回调都没发出去」的极端情况，避免 Dart 侧永远挂着。
    this.dispatch(call, result).catch((error: Object) => {
      const failure = error as BusinessError;
      const code: number = failure.code === undefined ? -1 : failure.code;
      hilog.error(DOMAIN, TAG, 'dispatch crashed, code=%{public}d msg=%{public}s',
        code, (error as Error).message ?? 'unknown');
      result.error('file_operation_failed', '文件操作失败', null);
    });
  }

  private async dispatch(call: MethodCall, result: MethodResult): Promise<void> {
    const method: string = call.method;
    try {
      switch (method) {
        case 'listDirectory': {
          const path: string = this.strArg(call, 'path');
          result.success(await this.listDirectory(path));
          break;
        }
        case 'copyInto': {
          const source: string = this.strArg(call, 'source');
          const target: string = this.strArg(call, 'target');
          result.success(await this.copyInto(source, target));
          break;
        }
        case 'moveInto': {
          const source: string = this.strArg(call, 'source');
          const target: string = this.strArg(call, 'target');
          result.success(await this.moveInto(source, target));
          break;
        }
        case 'rename': {
          // Dart 侧约定：source=旧完整路径，target=新文件名。
          const source: string = this.strArg(call, 'source');
          const newName: string = this.strArg(call, 'target');
          result.success(await this.rename(source, newName));
          break;
        }
        case 'deleteFile': {
          const path: string = this.strArg(call, 'path');
          result.success(await this.deleteFile(path));
          break;
        }
        case 'createDirectory': {
          const parent: string = this.strArg(call, 'source');
          const name: string = this.strArg(call, 'target');
          result.success(await this.createDirectory(parent, name));
          break;
        }
        case 'exists': {
          const path: string = this.strArg(call, 'path');
          result.success(this.exists(path));
          break;
        }
        case 'pickDirectory': {
          // 返回 '' 表示用户取消，Dart 侧翻成 null。
          result.success(await this.pickDirectory());
          break;
        }
        default:
          result.notImplemented();
          break;
      }
    } catch (error) {
      // 业务异常和系统异常要分开判：文件冲突/名字非法是我们自己抛的，
      // 没有数字 code，直接当 BusinessError 取 code 会拿到 undefined，
      // 一路落进默认分支，Dart 侧就认不出「重名」了。
      const code: string = this.errorCode(error);
      const message: string = (error as Error).message ?? '文件操作失败';
      hilog.error(DOMAIN, TAG, 'method=%{public}s failed, code=%{public}s msg=%{public}s',
        method, code, message);
      result.error(code, message, null);
    }
  }

  /// 列目录。
  ///
  /// `fs.listFile` 只给名字，大小和修改时间要逐个 stat——目录项通常几十个，
  /// 这点开销换来 UI 能显示文件大小，值得。stat 失败的条目跳过（常见于
  /// 刚被别的进程删掉的文件），不能因为一项就整页打不开。
  private async listDirectory(path: string): Promise<Array<Map<string, Object>>> {
    const entries: Array<Map<string, Object>> = [];
    let names: Array<string> = [];
    try {
      names = await fs.listFile(path);
    } catch (error) {
      // 目录不存在或无权访问：返回空列表而不是抛错，与 dart:io 实现一致。
      return entries;
    }
    for (const name of names) {
      const child: string = joinPath(path, name);
      try {
        const stat: fs.Stat = await fs.stat(child);
        const entry: Map<string, Object> = new Map<string, Object>();
        entry.set('name', name);
        entry.set('path', child);
        entry.set('isDirectory', stat.isDirectory());
        entry.set('size', stat.isDirectory() ? 0 : stat.size);
        // Stat.mtime 的单位是**秒**，Dart 侧按毫秒解析，这里必须换算。
        entry.set('modifiedAt', stat.mtime * 1000);
        entries.push(entry);
      } catch (error) {
        continue;
      }
    }
    return entries;
  }

  private async copyInto(sourcePath: string, targetDirectory: string): Promise<string> {
    const name: string = baseName(sourcePath);
    if (name.length === 0) throw makeInvalidName(sourcePath);
    const target: string = joinPath(targetDirectory, name);
    // 目标已存在就报冲突，绝不静默覆盖——用户搬文件时最怕的就是
    // 同名文件被悄悄换掉。
    if (this.exists(target)) {
      throw makeConflict(target);
    }
    await fs.copyFile(sourcePath, target);
    return target;
  }

  private async moveInto(sourcePath: string, targetDirectory: string): Promise<string> {
    const name: string = baseName(sourcePath);
    if (name.length === 0) throw makeInvalidName(sourcePath);
    const target: string = joinPath(targetDirectory, name);
    if (this.exists(target)) {
      throw makeConflict(target);
    }
    try {
      // 同一分区内 moveFile 是原子的。
      await fs.moveFile(sourcePath, target);
    } catch (error) {
      // 跨分区（沙盒 → 公共目录）moveFile 会失败，退回复制 + 删除。
      // 删除失败时把副本也清掉：宁可整体失败，也不要让用户看到两份
      // 而不知道哪份是真的。
      await fs.copyFile(sourcePath, target);
      try {
        await fs.unlink(sourcePath);
      } catch (unlinkError) {
        try {
          await fs.unlink(target);
        } catch (cleanupError) {
          hilog.warn(DOMAIN, TAG, 'rollback failed, code=%{public}d', cleanupError.code);
        }
        throw unlinkError;
      }
    }
    return target;
  }

  private async rename(sourcePath: string, newName: string): Promise<string> {
    if (!isValidFileName(newName)) {
      throw makeInvalidName(newName);
    }
    const target: string = joinPath(parentOf(sourcePath), newName);
    if (target === sourcePath) return sourcePath;
    if (this.exists(target)) {
      throw makeConflict(target);
    }
    await fs.rename(sourcePath, target);
    return target;
  }

  private async deleteFile(path: string): Promise<boolean> {
    // 不存在视为成功：删除是幂等的，重试不该报错。
    if (!this.exists(path)) return true;
    await fs.unlink(path);
    return true;
  }

  private async createDirectory(parentPath: string, name: string): Promise<string> {
    if (!isValidFileName(name)) {
      throw makeInvalidName(name);
    }
    const target: string = joinPath(parentPath, name);
    if (this.exists(target)) {
      throw makeConflict(target);
    }
    await fs.mkdir(target);
    return target;
  }

  private exists(path: string): boolean {
    try {
      return fs.accessSync(path);
    } catch (error) {
      return false;
    }
  }

  /// 选一个目录，返回可被 `fs` 直接使用的路径。
  ///
  /// 为什么不用 `file_picker`：它的 ohos 移植把 `dir` 当「选文件」处理，
  /// 选完会把目录内容当文件读出来、再返回缓存目录里的副本路径，根本不是
  /// 目录。所以这里直接用 `DocumentViewPicker` + 文件夹模式。
  ///
  /// 返回的是 picker 给的 `file://docs/...` URI 原样，**不**转成普通路径：
  /// 访问授权是绑在这个 URI 上的，换成路径就走不到授权了。`@ohos.file.fs`
  /// 的接口两种形式都收，所以后续操作不用特殊处理。
  private async pickDirectory(): Promise<string> {
    // selectMode: 1 = 文件夹（0 是文件）。用字面量而不是 DocumentSelectMode
    // 枚举，因为不同 SDK 版本里这个枚举名不一致，字面量在各版本都成立
    // ——仓库里 file_picker 的 ohos 实现也是这么写的。
    const options: picker.DocumentSelectOptions = {
      selectMode: 1,
      maxSelectNumber: 1,
    };
    const documentPicker = new picker.DocumentViewPicker(this.context);
    const selected: Array<string> = await documentPicker.select(options);
    if (selected === undefined || selected === null || selected.length === 0) {
      return '';
    }
    return selected[0];
  }

  private strArg(call: MethodCall, key: string): string {
    const value: Object = call.argument(key);
    if (value === undefined || value === null) return '';
    return value as string;
  }

  /// 把异常翻成 Dart 侧能分辨的字符串。
  ///
  /// Dart 会把 `conflict` / `access_denied` 转成对应的类型化异常，
  /// 其余原样包成 PlatformException，所以这里只需要区分这几类。
  ///
  /// 判据是「异常上有没有我们塞的 `koyzeCode` 字段」，不用 `instanceof`：
  /// ArkTS 编译到 JS 后自定义错误类的原型链不保证完整，`instanceof` 在
  /// release 包里可能失效，而字段检查没有这个风险。
  private errorCode(error: Object): string {
    const tagged = error as TaggedError;
    if (tagged.koyzeCode !== undefined) return tagged.koyzeCode;
    const failure = error as BusinessError;
    const code: number = failure.code;
    // 13900012 = Permission denied，13900020 = Operation not permitted，
    // 13900002 = No such file or directory。
    if (code === 13900012 || code === 13900020) return 'access_denied';
    if (code === 13900002) return 'not_found';
    return 'file_operation_failed';
  }
}

/// 带通道错误码的异常。
///
/// 继承 `Error` 是为了保留堆栈和 `message`，同时多带一个 `koyzeCode`
/// 供 [LocalFileSystemBridge.errorCode] 识别。
class TaggedError extends Error {
  readonly koyzeCode: string;

  constructor(code: string, message: string) {
    super(message);
    this.koyzeCode = code;
  }
}

/// 目标位置已有同名文件。用户改名重试即可。
class FileConflictError extends TaggedError {
  readonly conflictPath: string;

  constructor(path: string) {
    super('conflict', `目标位置已存在同名文件: ${path}`);
    this.conflictPath = path;
  }
}

/// 文件名不合法（含路径分隔符、为空、是 `.` 或 `..`）。
class InvalidNameError extends TaggedError {
  readonly invalidName: string;

  constructor(name: string) {
    super('invalid_name', `文件名不合法: ${name}`);
    this.invalidName = name;
  }
}

function makeConflict(path: string): FileConflictError {
  return new FileConflictError(path);
}

function makeInvalidName(name: string): InvalidNameError {
  return new InvalidNameError(name);
}

/// 拼路径。鸿蒙原生用 `/`，`file://docs/...` URI 也是 `/`，统一即可。
function joinPath(directory: string, name: string): string {
  if (directory.length === 0) return name;
  const trimmed: string = directory.endsWith('/')
    ? directory.substring(0, directory.length - 1)
    : directory;
  return `${trimmed}/${name}`;
}

function baseName(path: string): string {
  const cut: number = path.lastIndexOf('/');
  return cut < 0 ? path : path.substring(cut + 1);
}

function parentOf(path: string): string {
  const cut: number = path.lastIndexOf('/');
  if (cut < 0) return path;
  // 根目录本身（'/a' → '/'）和 URI 的协议段都要保住，别退化成空串。
  if (cut === 0) return '/';
  return path.substring(0, cut);
}

/// 拒 `..`、路径分隔符和空名字，避免重命名把文件挪到别的目录。
function isValidFileName(name: string): boolean {
  const trimmed: string = name.trim();
  if (trimmed.length === 0) return false;
  if (trimmed.indexOf('/') >= 0 || trimmed.indexOf('\\') >= 0) return false;
  if (trimmed === '.' || trimmed === '..') return false;
  return true;
}

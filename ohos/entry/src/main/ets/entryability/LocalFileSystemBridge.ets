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
/// 文档树。鸿蒙的 `@ohos.file.fs` 直接接受普通沙盒路径；DocumentViewPicker
/// 返回的 `file://docs/...` 则是另一种东西——**URI**，只有 `open` / `stat`
/// 这类接口认，`moveFile` / `copyFile` / `access` / `listFile` 都只收沙盒
/// 路径。两者不能混用（混用的后果是 13900002，看着像「文件不存在」）。
///
/// 写公共目录统一走 [writeIntoChosenDirectory]。这里还有两条**比路径类型
/// 更容易踩**的坑：
/// 1. URI 只接受 ASCII，文件名必须先经 [childUri] 做百分号编码，否则系统
///    抛的是「uriString_ is not ascii string」，但透到上层只剩 13900002；
/// 2. picker 返回的**目录** URI 只授权它自己，官方文档明确写了「URI 路径
///    不推荐拼接，拼接后的 URI 默认未授权」——往它后面接文件名一律被拒。
///    所以真正能落盘的公共入口是 `pickerMode = DOWNLOAD` 返回的
///    `Download/<包名>/`，[writeIntoChosenDirectory] 在目录写不进去时会
///    自动退到那里，并把真实落点返回给 Dart 侧显示。
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
    // 展示用的路径保持原始文件名；真正递给系统的那个 URI 必须编码过，
    // 两者分开算——否则 UI 上会看到一串 %E5%8F%91。
    const target: string = joinPath(targetDirectory, name);
    // 目标已存在就报冲突，绝不静默覆盖——用户搬文件时最怕的就是
    // 同名文件被悄悄换掉。URI 目标要用编码后的写法去探测，否则一律
    // 探测不到，等于把覆盖保护关掉了。
    if (this.exists(isUri(targetDirectory) ? childUri(targetDirectory, name) : target)) {
      throw makeConflict(target);
    }
    if (isUri(targetDirectory)) {
      return await this.writeIntoChosenDirectory(sourcePath, targetDirectory, target, false);
    }
    await fs.copyFile(sourcePath, target);
    return target;
  }

  private async moveInto(sourcePath: string, targetDirectory: string): Promise<string> {
    const name: string = baseName(sourcePath);
    if (name.length === 0) throw makeInvalidName(sourcePath);
    const target: string = joinPath(targetDirectory, name);
    if (this.exists(isUri(targetDirectory) ? childUri(targetDirectory, name) : target)) {
      throw makeConflict(target);
    }
    if (isUri(targetDirectory)) {
      // 目标目录来自 DocumentViewPicker，是 `file://docs/...` URI。
      // `fs.moveFile` / `fs.copyFile` 只认沙盒路径（见 SDK 的 @param 说明），
      // 写 URI 走 writeIntoChosenDirectory：文件名编码 + 多条写入策略。
      return await this.writeIntoChosenDirectory(sourcePath, targetDirectory, target, true);
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
          const cleanup = cleanupError as BusinessError;
          hilog.warn(DOMAIN, TAG, 'rollback failed, code=%{public}d', cleanup.code);
        }
        // arkts-limited-throw 只允许 throw Error 及其子类，而 catch 变量的
        // 静态类型是任意类型，直接 rethrow 编译不过。包一层并把原始业务码
        // 带过去——否则「没权限」会退化成未知错误，用户看到的提示就没用了。
        throw wrapError(unlinkError);
      }
    }
    return target;
  }

  /// 把文件写进用户在 picker 里选中的目录；选中目录不可写时退到下载目录。
  ///
  /// 为什么需要兜底：鸿蒙对「picker 返回的目录 URI」只给**该 URI 本身**的
  /// 临时授权，官方错误码文档写得很直白——「URI 路径不推荐进行拼接，
  /// 拼接后的 URI 默认未授权」。所以在目录 URI 后面接一个文件名去
  /// open/copy，会被当成未授权路径，表现为 13900002（ENOENT）或 401
  /// （参数无效），跟「文件名对不对」无关。
  ///
  /// 唯一被官方承诺「可以在其下创建文件」的入口是
  /// `DocumentSaveOptions.pickerMode = DOWNLOAD` 返回的 `Download/<包名>`
  /// 目录 URI（且不需要用户再点一次对话框）。所以策略是：
  /// 先按用户选的位置写，写不进去就静默落到下载目录，并把**真实落点**
  /// 返回给 Dart 侧，让 UI 能明确告诉用户文件去了哪。
  ///
  /// [removeSource] 为 true 时按「移动」语义删掉源文件；只有确认副本
  /// 已落盘（[wrote] 校验通过）才会删，绝不先删后写。
  private async writeIntoChosenDirectory(
    sourcePath: string,
    targetDirectory: string,
    displayTarget: string,
    removeSource: boolean,
  ): Promise<string> {
    let actual: string = displayTarget;
    try {
      await this.writeIntoUriDirectory(sourcePath, targetDirectory);
    } catch (pickedError) {
      hilog.warn(DOMAIN, TAG, 'picked dir not writable, fallback to Download: %{public}s',
        (pickedError as Error).message ?? 'unknown');
      actual = await this.writeIntoDownloadDirectory(sourcePath);
    }
    if (!removeSource) return actual;
    try {
      await fs.unlink(sourcePath);
    } catch (error) {
      // 副本已经写进公共目录，但源文件删不掉：不能当成功，否则用户
      // 会同时看到两份而不知道哪份是真的。把原始错误带回去。
      throw wrapError(error);
    }
    return actual;
  }

  /// 写进 `Download/<包名>/`：官方唯一承诺「可在其下创建文件」的公共目录。
  ///
  /// `save({pickerMode: DOWNLOAD})` 不弹选择框，直接返回该目录 URI（首次
  /// 调用会由系统创建目录）。之后 `open(子路径, CREATE)` 才是被授权的操作；
  /// 这跟「picker 选中的目录」完全不同——后者拼子路径一律未授权。
  private async writeIntoDownloadDirectory(sourcePath: string): Promise<string> {
    const options: picker.DocumentSaveOptions = new picker.DocumentSaveOptions();
    // DOWNLOAD 模式跳过选择框，直接落到 Download/<包名>/，且返回的 URI
    // 允许在其下创建文件。用枚举而不是字面量，让编译器帮忙校验。
    options.pickerMode = picker.DocumentPickerMode.DOWNLOAD;
    const documentPicker = new picker.DocumentViewPicker(this.context);
    const selected: Array<string> = await documentPicker.save(options);
    if (selected === undefined || selected === null || selected.length === 0) {
      throw new TaggedError('access_denied', '系统未返回可用的下载目录');
    }
    const baseUri: string = selected[0];
    const expected: number = this.fileSize(sourcePath);
    const attempts: Array<string> = [];

    // 1) 当成目录 URI：在其下新建文件（同名自动加序号，不覆盖已有文件）。
    try {
      const candidate: string = this.freeCandidate(baseUri, baseName(sourcePath));
      const dest: fs.File = await fs.open(
        candidate,
        fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC,
      );
      try {
        await fs.copyFile(sourcePath, dest.fd);
      } finally {
        fs.closeSync(dest);
      }
      if (this.wrote(candidate, expected)) return candidate;
      attempts.push(`download+dir=写入不完整(${this.fileSize(candidate)}/${expected})`);
    } catch (error) {
      attempts.push(describeFailure('download+dir', error));
    }

    // 2) 个别版本会直接返回一个预创建好的文件 URI，那就写它本身。
    try {
      const dest: fs.File = await fs.open(baseUri, fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      try {
        await fs.copyFile(sourcePath, dest.fd);
      } finally {
        fs.closeSync(dest);
      }
      if (this.wrote(baseUri, expected)) return baseUri;
      attempts.push(`download+file=写入不完整(${this.fileSize(baseUri)}/${expected})`);
    } catch (error) {
      attempts.push(describeFailure('download+file', error));
    }

    throw new TaggedError(
      'file_operation_failed',
      `保存到下载目录失败: ${attempts.join(' | ')}`,
    );
  }

  /// 在目录 URI 下找一个不冲突的文件名：`歌.m4a` → `歌 (1).m4a`。
  ///
  /// 下载目录是跨应用共享的，同名文件可能来自上一次导出。这里只保证
  /// 不覆盖别人，不去猜用户想不想覆盖——覆盖是不可逆的，宁可变多个副本。
  private freeCandidate(directoryUri: string, name: string): string {
    const dot: number = name.lastIndexOf('.');
    const stem: string = dot > 0 ? name.substring(0, dot) : name;
    const ext: string = dot > 0 ? name.substring(dot) : '';
    for (let i: number = 0; i < 50; i++) {
      const candidateName: string = i === 0 ? name : `${stem} (${i})${ext}`;
      const candidate: string = childUri(directoryUri, candidateName);
      if (!this.exists(candidate)) return candidate;
    }
    return childUri(directoryUri, `${stem}-${Date.now()}${ext}`);
  }

  /// 往 picker 授权的**目录 URI** 里写一个文件。
  ///
  /// 关键前提：文件名必须先做百分号编码。鸿蒙的 URI 解析器只接受 ASCII，
  /// 把「发如雪.m4a」这种原始中文名拼进 `file://…` 会直接在
  /// `URI: uriString_ is not ascii string` 处失败，连权限校验都到不了——
  /// 外面看到的 13900002 并不是「文件不存在」，也不是「没权限」。
  ///
  /// 三条路依次试，顺序按「是否符合文档承诺」排：
  /// 1. `fs.open(…, CREATE)` 拿 fd 再 `copyFile` 到 fd——SDK 明确写了
  ///    open 支持 URI 且支持 CREATE，这是最标准的一条；
  /// 2. `fs.copy(src, 目标文件URI)`——API 11 起两个参数都收 URI，覆盖式写入；
  /// 3. `fs.copy(src, 目录URI)`——让系统自己拼名字，绕开一切路径拼接问题。
  ///
  /// 每条都要**验证写完之后目标真的落盘**：`fs.copy` 在某些版本上对不存在
  /// 的子路径是「静默成功」，不校验就会把「什么都没写」当成成功，然后
  /// 删掉源文件——那是数据丢失，比报错严重得多。校验优先比对字节数，
  /// stat 不可用时才退回「能不能打开」。
  ///
  /// 全部失败时把每条的原始错误码一起带出去：只说「失败了」没法判断是
  /// 编码问题、权限问题还是 URI 解析问题。
  private async writeIntoUriDirectory(
    sourcePath: string,
    targetDirectory: string,
  ): Promise<void> {
    const name: string = baseName(sourcePath);
    const targetUri: string = childUri(targetDirectory, name);
    const attempts: Array<string> = [];
    const expected: number = this.fileSize(sourcePath);

    // 1) open(CREATE) 拿 fd → 按 fd 拷。
    try {
      const dest: fs.File = await fs.open(
        targetUri,
        fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC,
      );
      try {
        await fs.copyFile(sourcePath, dest.fd);
      } finally {
        fs.closeSync(dest);
      }
      if (this.wrote(targetUri, expected)) return;
      attempts.push(`open+fd=写入不完整(${this.fileSize(targetUri)}/${expected})`);
    } catch (error) {
      attempts.push(describeFailure('open+fd', error));
    }

    // 2) 直接拷到目标文件 URI。
    try {
      await fs.copy(sourcePath, targetUri);
      if (this.wrote(targetUri, expected)) return;
      attempts.push(`copy->file=写入不完整(${this.fileSize(targetUri)}/${expected})`);
    } catch (error) {
      attempts.push(describeFailure('copy->file', error));
    }

    // 3) 拷进目录 URI，由系统决定落盘名字。
    try {
      await fs.copy(sourcePath, targetDirectory);
      if (this.wrote(targetUri, expected)) return;
      attempts.push(`copy->dir=写入不完整(${this.fileSize(targetUri)}/${expected})`);
    } catch (error) {
      attempts.push(describeFailure('copy->dir', error));
    }

    throw new TaggedError(
      'file_operation_failed',
      `写入公共目录失败（${targetUri}）: ${attempts.join(' | ')}`,
    );
  }

  private async rename(sourcePath: string, newName: string): Promise<string> {
    if (!isValidFileName(newName)) {
      throw makeInvalidName(newName);
    }
    const parent: string = parentOf(sourcePath);
    const target: string = isUri(parent) ? childUri(parent, newName) : joinPath(parent, newName);
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
    const target: string = isUri(parentPath) ? childUri(parentPath, name) : joinPath(parentPath, name);
    if (this.exists(target)) {
      throw makeConflict(target);
    }
    await fs.mkdir(target);
    return target;
  }

  private exists(path: string): boolean {
    if (isUri(path)) {
      // `fs.access` 不认 URI。只读 open 一次即可：能打开就是存在，
      // 而且 READ_ONLY 不会像 CREATE 那样把文件建出来。
      const forms: Array<string> = uriForms(path);
      for (let i: number = 0; i < forms.length; i++) {
        try {
          const file: fs.File = fs.openSync(forms[i], fs.OpenMode.READ_ONLY);
          fs.closeSync(file);
          return true;
        } catch (error) {
          continue;
        }
      }
      return false;
    }
    try {
      return fs.accessSync(path);
    } catch (error) {
      return false;
    }
  }

  /// 取文件字节数；拿不到（不存在/无权限/该版本不支持对 URI stat）返回 -1。
  ///
  /// 用 `stat` 而不是「打开再 lseek 到末尾」：公共目录里动辄几十 MB，
  /// 探测一次不该产生真实 IO。stat 对 URI 的支持从 API 22 起才有，
  /// 更老的系统上会抛，由 [wrote] 退回存在性判断。
  private fileSize(path: string): number {
    try {
      const stat: fs.Stat = fs.statSync(path);
      if (stat.isDirectory()) return -1;
      return stat.size;
    } catch (error) {
      return -1;
    }
  }

  /// 写完之后的落地校验：字节数一致才算成功。
  ///
  /// 只判「文件存在」是不够的：目标位置可能本来就有一份同名文件（用户
  /// 手动放进去的），存在性检查会把它当成这次写入的成果，然后源文件被
  /// 删掉——用户就同时失去了原文件和这次的新内容。
  private wrote(targetUri: string, expected: number): boolean {
    if (expected < 0) return this.exists(targetUri);
    const actual: number = this.fileSize(targetUri);
    if (actual < 0) return this.exists(targetUri);
    return actual === expected;
  }

  /// 选一个目录，返回可被 `fs` 直接使用的 URI。
  ///
  /// 为什么不用 `file_picker`：它的 ohos 移植把 `dir` 当「选文件」处理，
  /// 选完会把目录内容当文件读出来、再返回缓存目录里的副本路径，根本不是
  /// 目录。所以这里直接用 `DocumentViewPicker` + 文件夹模式。
  ///
  /// 返回的是 picker 给的 `file://docs/...` URI 原样，**不**转成普通路径：
  /// 访问授权是绑在这个 URI 上的，换成路径就走不到授权了。但要注意它
  /// 是 URI 而不是沙盒路径——`moveFile` / `copyFile` / `access` 都不认，
  /// 写文件得走 [writeIntoUriDirectory]（含文件名编码与多条兜底策略）。
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
    if (code === undefined || code === null) return 'file_operation_failed';
    return codeFromNumber(code);
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

/// 系统错误码 → 通道错误码。
///
/// 13900012 = Permission denied，13900020 = Operation not permitted，
/// 13900002 = No such file or directory。
function codeFromNumber(code: number): string {
  if (code === 13900012 || code === 13900020) return 'access_denied';
  if (code === 13900002) return 'not_found';
  return 'file_operation_failed';
}

/// 把 `catch` 到的任意值包成可以 throw 的 `Error`。
///
/// `arkts-limited-throw` 只允许 throw `Error` 及其子类，而 catch 变量的静态
/// 类型是任意类型，直接 rethrow 编译不过。包一层的同时把原始业务码转成
/// [TaggedError]，这样权限错误不会退化成「未知错误」。
function wrapError(value: Object): Error {
  const message: string = (value as Error).message ?? '文件操作失败';
  const code: number = (value as BusinessError).code;
  if (code === undefined || code === null) return new Error(message);
  return new TaggedError(codeFromNumber(code), message);
}

/// 拼路径。鸿蒙原生用 `/`，`file://docs/...` URI 也是 `/`，统一即可。
/// 注意这里**不做编码**：给沙盒路径和展示文案用。要递给系统写盘的
/// 子路径一律用 [childUri]。
function joinPath(directory: string, name: string): string {
  if (directory.length === 0) return name;
  const trimmed: string = directory.endsWith('/')
    ? directory.substring(0, directory.length - 1)
    : directory;
  return `${trimmed}/${name}`;
}

/// 拼一个可写子路径：目标父目录是 URI 时，文件名必须百分号编码。
///
/// 这是整个鸿蒙文件导出最容易踩的一颗雷：`file://docs/.../Documents`
/// 看起来就是个普通字符串，直接 `+ '/' + 文件名` 拼上去毫无编译期问题，
/// 但鸿蒙的 URI 解析器**只接受 ASCII**，遇到原始中文会直接抛
/// 「uriString_ is not ascii string」，外层拿到的却是 13900002
/// （No such file or directory），看着像文件不存在或没权限，误导性极强。
function childUri(directory: string, name: string): string {
  const trimmed: string = directory.endsWith('/')
    ? directory.substring(0, directory.length - 1)
    : directory;
  return `${trimmed}/${encodeFileName(name)}`;
}

/// 原始文件名 → URI 路径段。
///
/// 用 `encodeURIComponent` 而不是 `encodeURI`：前者会把 `%` 和 `/` 也编掉，
/// 正好符合「传进来的名字一定未编码」这个前提（来源是沙盒路径或用户输入）。
/// 用 `encodeURI` 会因为整串里带 `%` 就整体跳过编码，中文原样漏给系统。
function encodeFileName(name: string): string {
  return encodeURIComponent(name);
}

/// 是不是 URI（`file://docs/...`）而不是沙盒路径。
///
/// 这个区分在鸿蒙上是**硬**的：`fs.moveFile` 只收沙盒路径，`fs.access`
/// 也只收沙盒路径；只有 `fs.open` / `fs.stat` 这一类明确写了支持 URI。
/// 把 picker 返回的 URI 当路径用，得到的是 13900002（不是没权限，是
/// 「找不到」——系统按相对路径去解析了）。
function isUri(path: string): boolean {
  return path.indexOf('://') > 0;
}

/// 一个 URI 的候选写法，仅用于「探测存在性」这种容错场景。
///
/// 写盘路径不走这里：[childUri] 已经保证编码正确，二次猜测只会掩盖问题。
/// 探测存在性时数据库里可能存着历史版本的未编码 URI，所以仍然两种都试。
function uriForms(uri: string): Array<string> {
  if (uri.indexOf('%') >= 0) return [uri];
  const encoded: string = encodeURI(uri);
  if (encoded === uri) return [uri];
  return [uri, encoded];
}

/// 取业务错误码；不是 BusinessError 时返回 0。
function failureCode(value: Object): number {
  const code: number = (value as BusinessError).code;
  return code === undefined || code === null ? 0 : code;
}

/// 把一次失败的尝试描述成 `label=code message`，供最终错误信息汇总。
function describeFailure(label: string, value: Object): string {
  const code: number = failureCode(value);
  const message: string = (value as Error).message ?? '';
  return message.length > 0 ? `${label}=${code} ${message}` : `${label}=${code}`;
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

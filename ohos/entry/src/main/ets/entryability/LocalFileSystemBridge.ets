/*
 * Copyright 2024 Koyze Contributors
 * Licensed under the Apache License, Version 2.0
 */

import MethodCall from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodCall';
import { MethodCallHandler, MethodResult } from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';
import { fileIo as fs, picker, fileUri } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { preferences } from '@kit.ArkData';

const DOMAIN: number = 0x0000;
const TAG: string = 'KoyzeFileSystem';

/// 缓存「导出到下载目录」授权 URI 的偏好存储名与键名。
///
/// 单独一个 store：Flutter 侧的设置项走 SharedPreferences（另一个文件），
/// 混在一起容易被 `resetPreferences` 之类的全量清理顺手删掉——那样用户
/// 每次导出都要重新授权一次。
const DOWNLOAD_URI_PREF: string = 'koyze_export';
const DOWNLOAD_URI_KEY: string = 'download_dir_uri';

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
/// 所以写公共目录时统一走 [writeIntoUriDirectory]：用 `fs.copy` 按 URI 写。
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
        case 'exportToPublicDownloads': {
          const source: string = this.strArg(call, 'source');
          result.success(await this.exportToPublicDownloads(source));
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
    if (isUri(targetDirectory)) {
      await this.writeIntoUriDirectory(sourcePath, targetDirectory);
      return target;
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
    if (isUri(targetDirectory)) {
      // 目标目录来自 DocumentViewPicker，是 `file://docs/...` URI。
      // `fs.moveFile` / `fs.copyFile` 只认沙盒路径（见 SDK 的 @param 说明），
      // 早先直接把 URI 递进去，系统把它当相对路径解析 → 13900002，
      // Dart 侧看到的就是 not_found / No such file or directory。
      // 写 URI 的唯一正路是 open 拿 fd（open 支持 URI）再按 fd 拷。
      await this.writeIntoUriDirectory(sourcePath, targetDirectory);
      try {
        await fs.unlink(sourcePath);
      } catch (error) {
        // 副本已经写进公共目录，但源文件删不掉：不能当成功，否则用户
        // 会同时看到两份而不知道哪份是真的。把原始错误带回去。
        throw wrapError(error);
      }
      return target;
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

  /// 往 picker 授权的**目录 URI** 里写一个文件。
  ///
  /// 之前用 `fs.open(目录URI + 文件名, READ_WRITE | CREATE)`，真机上稳定报
  /// 13900002（No such file or directory）：`fs.open` 的注释写着支持 URI，
  /// 但 URI 解析要求**节点已经存在**，`CREATE` 在 URI 上不生效——子路径
  /// 解析不到就直接 ENOENT，跟「有没有权限」无关。所以那条路根本走不通。
  ///
  /// `fs.copy` 从 API 11 起两个参数都接受 URI，且是「覆盖式写入」，
  /// 这才是往 picker 目录里落文件的正确入口。
  ///
  /// 三条路依次试，全部失败时把每条的原始错误码一起带出去：鸿蒙各版本对
  /// URI 的支持差异很大，只说「失败了」没法判断下一步该怎么改。
  private async writeIntoUriDirectory(
    sourcePath: string,
    targetDirectory: string,
  ): Promise<void> {
    const name: string = baseName(sourcePath);
    const targetUri: string = joinPath(targetDirectory, name);
    const failures: Array<string> = [];
    let lastCode: number = 0;

    // 1) 拷到目标文件 URI。
    try {
      await fs.copy(sourcePath, targetUri);
      if (this.exists(targetUri)) return;
      failures.push('copy->file=写入后目标不存在');
    } catch (error) {
      lastCode = failureCode(error);
      failures.push(describeFailure('copy->file', error));
    }

    // 2) 拷进目录 URI，让系统自己拼名字，绕开子路径解析。
    try {
      await fs.copy(sourcePath, targetDirectory);
      if (this.exists(targetUri)) return;
      failures.push('copy->dir=写入后目标不存在');
    } catch (error) {
      lastCode = failureCode(error);
      failures.push(describeFailure('copy->dir', error));
    }

    // 3) open 出 fd 再按 fd 写：个别版本 URI 只对已存在的文件生效。
    try {
      const dest: fs.File = await this.openUri(targetUri);
      try {
        await fs.copyFile(sourcePath, dest.fd);
      } finally {
        fs.closeSync(dest);
      }
      return;
    } catch (error) {
      lastCode = failureCode(error);
      failures.push(describeFailure('open+fd', error));
    }

    throw new TaggedError(
      codeFromNumber(lastCode),
      `写入受限目录失败（${targetUri}）: ${failures.join(' | ')}`,
    );
  }

  /// 打开（不存在就创建）一个可写 URI。
  ///
  /// 文件名里的中文、括号在 URI 里严格来说要百分号编码，个别系统版本
  /// 只认编码后的形式。先按原样试，失败再试编码形式；URI 本身已经带了
  /// `%` 就说明是编过码的，不再二次编码（否则 `%20` 会变成 `%2520`）。
  private async openUri(uri: string): Promise<fs.File> {
    const forms: Array<string> = uriForms(uri);
    let failure: Object = new Error(`无法打开目标: ${uri}`);
    for (let i: number = 0; i < forms.length; i++) {
      try {
        return await fs.open(forms[i], fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE);
      } catch (error) {
        failure = error;
      }
    }
    throw wrapError(failure);
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

  /// 选一个目录，返回可被 `fs` 直接使用的 URI。
  ///
  /// 为什么不用 `file_picker`：它的 ohos 移植把 `dir` 当「选文件」处理，
  /// 选完会把目录内容当文件读出来、再返回缓存目录里的副本路径，根本不是
  /// 目录。所以这里直接用 `DocumentViewPicker` + 文件夹模式。
  ///
  /// 返回的是 picker 给的 `file://docs/...` URI 原样，**不**转成普通路径：
  /// 访问授权是绑在这个 URI 上的，换成路径就走不到授权了。但要注意它
  /// 是 URI 而不是沙盒路径——`moveFile` / `copyFile` / `access` 都不认，
  /// 写文件得走 [writeIntoUriDirectory]（`fs.copy` 支持 URI）。
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

  /// 把沙箱里的文件导出到系统公共下载目录。
  ///
  /// 和 [pickDirectory] 是两件事：那个要求路径能交给 `dart:io` 长期读写
  /// （鸿蒙的 `file://docs/...` 做不到，所以下载根不能换）；这个只要求
  /// 「按 URI 写一次」，`fs.copy` 从 API 11 起支持，完全可做。
  ///
  /// 为什么用 `DocumentPickerMode.DOWNLOAD`：
  /// - 跳过文件选择界面，直接落 `Download/<包名>/`，用户点一次同意就行；
  /// - 返回的 URI **已具备持久化权限**，存下来下次直接用，不必每首歌都弹窗；
  /// - 免权限，不用申请 `READ_WRITE_DOWNLOAD_DIRECTORY`（那个还只支持
  ///   PC / 2in1 / 平板，手机根本没有）。
  ///
  /// 这里刻意**不**返回 URI 给用户看，返回的是展示用路径（去掉
  /// `file://docs/storage/Users/currentUser/` 前缀），设置页里显示成
  /// 「下载/Koyze」这种人类能读的形式。
  private async exportToPublicDownloads(sourcePath: string): Promise<string> {
    if (sourcePath.length === 0 || !this.exists(sourcePath)) {
      throw new TaggedError('not_found', `源文件不存在: ${sourcePath}`);
    }
    const name: string = baseName(sourcePath);
    if (name.length === 0) throw makeInvalidName(sourcePath);

    // 先用缓存的授权。**不对目录 URI 做探活**：`fs.open` 对目录本来就可能
    // 报 EISDIR，而带 CREATE 的 open 更糟——真在某些版本上把「目录」当文件
    // 建出来。用「写一次试试」当探针，失败就重新申请，语义正好。
    const cached: string = await this.readCachedDownloadUri();
    if (cached.length > 0) {
      try {
        await this.copyToUri(sourcePath, joinPath(cached, name));
        return this.prettyPath(cached, name);
      } catch (error) {
        // 授权失效的典型原因：用户在文件管理器里删了 `Download/<包名>`，
        // 或者系统撤销了持久授权。清掉缓存重申请一次。
        hilog.warn(DOMAIN, TAG, 'cached download uri unusable, re-requesting: %{public}s',
          describeFailure('export', error));
        await this.clearCachedDownloadUri();
      }
    }

    const fresh: string = await this.requestDownloadDirectoryUri();
    if (fresh.length === 0) {
      // 用户取消。空串在 Dart 侧翻成 null，与 pickDirectory 一致。
      return '';
    }
    await this.copyToUri(sourcePath, joinPath(fresh, name));
    return this.prettyPath(fresh, name);
  }

  /// 拉起 DOWNLOAD 模式的保存对话框，拿到 `Download/<包名>/` 并记下来。
  ///
  /// 存的是 URI 而不是路径：持久授权绑在 URI 上，转成路径就失效了。
  private async requestDownloadDirectoryUri(): Promise<string> {
    const options: picker.DocumentSaveOptions = new picker.DocumentSaveOptions();
    // DOWNLOAD 模式（枚举值 1）：跳过文件选择界面，直接落 `Download/<包名>/`，
    // 返回的 URI 已带持久化授权。配了它之后 newFileNames / defaultFilePathUri
    // / fileSuffixChoices 一律不生效，所以这里不设那些字段。
    //
    // 写枚举而非字面量 1：`pickerMode` 的类型是 `DocumentPickerMode`，
    // ArkTS 对枚举字段的赋值比 TS 严格，给数字可能编译不过。这个枚举
    // 从 API 12 起就存在，SDK 26 一定有。
    options.pickerMode = picker.DocumentPickerMode.DOWNLOAD;
    const documentPicker = new picker.DocumentViewPicker(this.context);
    const saved: Array<string> = await documentPicker.save(options);
    if (saved === undefined || saved === null || saved.length === 0) {
      return '';
    }
    const uri: string = saved[0];
    if (uri === undefined || uri === null || uri.length === 0) return '';
    await this.writeCachedDownloadUri(uri);
    return uri;
  }

  /// 把沙箱里的一份文件写到 picker 给的目录下，同名覆盖。
  ///
  /// 关键点：**不能直接把 `file://docs/...` URI 递给 fs 当路径用**。
  /// URI 只是「系统给这个目录发了授权」的凭据，不代表 `uri + '/名字'`
  /// 这个子路径已经存在。实测（模拟器 API 26）：
  /// - `fs.open(uri + '/名字', CREATE | READ_WRITE)` → ENOENT（No such file）
  /// - `fs.copy(源, uri + '/名字')` → 401（input parameter is invalid）
  ///
  /// 官方示例的做法是先转成路径再操作：
  ///   `const p = new fileUri.FileUri(uri + '/test.txt').path;`
  ///   `fs.openSync(p, CREATE | READ_WRITE)`
  /// 也就是 FileUri 负责把 docs URI 映射回 `/storage/Users/...` 这样的
  /// 真实路径，授权仍然有效。按这个顺序试，最后才退回按 URI 直写
  /// （个别版本对 URI 的支持更好，留着兜底不亏）。
  private async copyToUri(sourcePath: string, targetUri: string): Promise<void> {
    const failures: Array<string> = [];
    let lastCode: number = 0;
    // 候选路径：FileUri 可能把中文名百分号转义，也可能原样保留，两种都要试。
    // 少试一种就会出现「英文名能导出、中文名导出失败」这种半好用的状态。
    const paths: Array<string> = pathForms(targetUri);

    // 1) 转成路径后 open（不存在就建）+ 按 fd 拷。官方示例走的就是这条。
    for (const targetPath of paths) {
      try {
        const dest: fs.File = await fs.open(
          targetPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE);
        try {
          await fs.copyFile(sourcePath, dest.fd);
        } finally {
          fs.closeSync(dest);
        }
        return;
      } catch (error) {
        lastCode = failureCode(error);
        failures.push(describeFailure('open(path)+fd', error));
      }
    }

    // 2) 转成路径后直接 copy（目标已存在时这条最省事）。
    for (const targetPath of paths) {
      try {
        await fs.copy(sourcePath, targetPath);
        return;
      } catch (error) {
        lastCode = failureCode(error);
        failures.push(describeFailure('copy(path)', error));
      }
    }

    // 3) 兜底：仍按 URI 试一次，兼容对 URI 支持更完整的版本。
    try {
      await fs.copy(sourcePath, targetUri);
      if (this.exists(targetUri)) return;
      failures.push('copy(uri)=写入后目标不存在');
    } catch (error) {
      lastCode = failureCode(error);
      failures.push(describeFailure('copy(uri)', error));
    }

    throw new TaggedError(
      codeFromNumber(lastCode),
      `导出到下载目录失败（${targetUri}）: ${failures.join(' | ')}`,
    );
  }

  /// 把 `file://docs/storage/Users/currentUser/Download/xxx` 变成
  /// `下载/xxx` 这种能显示在设置页里的形式。
  ///
  /// 各版本的前缀不完全一样（有 `Download`、`Downloads`、带 `localUser`
  /// 的），所以只按「Download 之后的部分」切，切不出来就原样返回。
  private prettyPath(directoryUri: string, name: string): string {
    const marker: string = '/Download/';
    const index: number = directoryUri.lastIndexOf(marker);
    const tail: string = index >= 0
      ? directoryUri.substring(index + marker.length)
      : '';
    // 解码失败不能把整个导出流程带崩：path 里出现夹生的 `%` 是完全可能的
    // （包名里带了业务不该出现但确实存在的字符），那就原样显示。
    let folder: string = '下载';
    if (tail.length > 0) {
      try {
        folder = `下载/${decodeURIComponent(tail)}`;
      } catch (error) {
        folder = `下载/${tail}`;
      }
    }
    return `${folder}/${name}`;
  }

  private async readCachedDownloadUri(): Promise<string> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(
        this.context, DOWNLOAD_URI_PREF);
      const value: preferences.ValueType = await store.get(DOWNLOAD_URI_KEY, '');
      // 存的就是 string，但 ValueType 是个联合类型，这里显式收窄；
      // 取不到（首次运行）时 as string 是 undefined，一并当空串。
      const text: string = value as string;
      if (text === undefined || text === null) return '';
      return text;
    } catch (error) {
      // 偏好存储读不出来不该阻断导出：退化成「每次都问一次授权」。
      hilog.warn(DOMAIN, TAG, 'read cached download uri failed: %{public}s',
        describeFailure('preferences', error));
      return '';
    }
  }

  private async writeCachedDownloadUri(uri: string): Promise<void> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(
        this.context, DOWNLOAD_URI_PREF);
      await store.put(DOWNLOAD_URI_KEY, uri);
      await store.flush();
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'write cached download uri failed: %{public}s',
        describeFailure('preferences', error));
    }
  }

  /// 丢掉已失效的授权，下次导出会重新申请。
  private async clearCachedDownloadUri(): Promise<void> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(
        this.context, DOWNLOAD_URI_PREF);
      await store.delete(DOWNLOAD_URI_KEY);
      await store.flush();
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'clear cached download uri failed: %{public}s',
        describeFailure('preferences', error));
    }
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
function joinPath(directory: string, name: string): string {
  if (directory.length === 0) return name;
  const trimmed: string = directory.endsWith('/')
    ? directory.substring(0, directory.length - 1)
    : directory;
  return `${trimmed}/${name}`;
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

/// 一个文件 URI 的候选路径写法（去重）。
///
/// `FileUri` 对中文、括号这类字符的处置在不同版本上不一致：有的原样保留，
/// 有的转成 `%E4%BD%A0`。转义过的路径拿去 open 会建出一个名字里带百分号的
/// 文件，看着能用其实是垃圾。两种写法都给出，让上层按顺序试。
function pathForms(uri: string): Array<string> {
  const primary: string = uriToPath(uri);
  const forms: Array<string> = [primary];
  if (primary.indexOf('%') >= 0) {
    try {
      const decoded: string = decodeURIComponent(primary);
      if (decoded !== primary) forms.push(decoded);
    } catch (error) {
      // 夹生的 `%`（不是合法转义）解不开，就用原样那条。
      hilog.warn(DOMAIN, TAG, 'decode target path failed: %{public}s',
        describeFailure('decode', error));
    }
  }
  return forms;
}

/// 把 `file://docs/...` URI 换成可以交给 fs.open / fs.copy 的路径。
///
/// 为什么必须转：URI 只是「这个目录已授权给本应用」的凭据，`uri + '/名字'`
/// 这个子路径在文件系统里还没被创建过，直接 open 必然 ENOENT；fs.copy 更
/// 直接，回 401（参数非法）。官方示例用 `new fileUri.FileUri(uri).path`
/// 完成这层映射。
///
/// 兜底是手动剥 scheme：`file://docs` 之后的部分就是路径。FileUri 在个别
/// 版本上对带中文的 URI 会抛，这条能保证导出不至于因为一个工具函数失败。
function uriToPath(uri: string): string {
  try {
    const parsed: string = new fileUri.FileUri(uri).path;
    if (parsed !== undefined && parsed !== null && parsed.length > 0) {
      return parsed;
    }
  } catch (error) {
    hilog.warn(DOMAIN, TAG, 'FileUri parse failed, stripping scheme manually: %{public}s',
      describeFailure('fileUri', error));
  }
  const scheme: string = 'file://docs';
  if (uri.startsWith(scheme)) return uri.substring(scheme.length);
  const slash: number = uri.indexOf('/storage/');
  if (slash >= 0) return uri.substring(slash);
  return uri;
}

/// 一个 URI 的候选写法。
///
/// 绝大多数文件名原样就能 open；带中文/空格时个别系统版本要求百分号编码，
/// 所以给一个「原样 + 编码」的候选列表逐个试。已经含 `%` 的 URI 视为
/// 编过码，不再二次编码。
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

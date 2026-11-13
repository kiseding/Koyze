import Flutter
import Foundation

/// iOS / macOS 的本地文件操作。
///
/// 与 Android 不同，Apple 平台上路径是真实路径，`FileManager` 直接可用。
/// 真正的麻烦在**沙盒**：用户通过文档选择器授权的目录，只有在
/// `startAccessingSecurityScopedResource()` 返回 true 的期间才能写。
///
/// 因此这里所有写操作都先确认路径落在某个已激活的 security-scoped 目录
/// 内。不在的话直接拒绝，而不是让 `FileManager` 抛一个语焉不详的错误——
/// 上层需要能区分「没权限」和「文件不存在」。
final class SecurityScopedFileAccess {
  /// 已激活的目录 URL，按路径索引。由 `SecurityScopedDirectoryAccess`
  /// 在用户选择目录、或恢复书签时填充。
  private let activeDirectories: () -> [URL]

  init(activeDirectories: @escaping () -> [URL]) {
    self.activeDirectories = activeDirectories
  }

  func listDirectory(path: String, result: @escaping FlutterResult) {
    guard let directory = writableURL(for: path) else {
      // 不能返回空数组：界面上「没权限」和「文件夹是空的」长得一样，
      // 用户会以为文件丢了。抛 access_denied 让它显示真实原因。
      result(FlutterError(code: "access_denied", message: "目录未授权", details: path))
      return
    }
    do {
      let contents = try FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey],
        options: [.skipsHiddenFiles]
      )
      let entries: [[String: Any]] = contents.map { url in
        let values = try? url.resourceValues(
          forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
        )
        return [
          "name": url.lastPathComponent,
          "path": url.path,
          "isDirectory": values?.isDirectory ?? false,
          "size": values?.fileSize ?? 0,
          "modifiedAt": Int((values?.contentModificationDate?.timeIntervalSince1970 ?? 0) * 1000),
        ]
      }
      result(entries)
    } catch {
      result(FlutterError(
        code: "list_failed",
        message: error.localizedDescription,
        details: path
      ))
    }
  }

  func copyInto(sourcePath: String, targetDirectory: String, result: @escaping FlutterResult) {
    moveOrCopy(sourcePath: sourcePath, targetDirectory: targetDirectory, move: false, result: result)
  }

  func moveInto(sourcePath: String, targetDirectory: String, result: @escaping FlutterResult) {
    moveOrCopy(sourcePath: sourcePath, targetDirectory: targetDirectory, move: true, result: result)
  }

  func rename(sourcePath: String, newName: String, result: @escaping FlutterResult) {
    guard let source = writableURL(for: sourcePath) else {
      result(FlutterError(code: "access_denied", message: "目录未授权", details: sourcePath))
      return
    }
    let target = source.deletingLastPathComponent().appendingPathComponent(newName)
    if FileManager.default.fileExists(atPath: target.path) {
      result(FlutterError(code: "conflict", message: "目标已存在", details: target.path))
      return
    }
    do {
      try FileManager.default.moveItem(at: source, to: target)
      result(target.path)
    } catch {
      result(FlutterError(code: "rename_failed", message: error.localizedDescription, details: sourcePath))
    }
  }

  func deleteFile(path: String, result: @escaping FlutterResult) {
    guard let url = writableURL(for: path) else {
      result(FlutterError(code: "access_denied", message: "目录未授权", details: path))
      return
    }
    do {
      try FileManager.default.removeItem(at: url)
      result(nil)
    } catch {
      result(FlutterError(code: "delete_failed", message: error.localizedDescription, details: path))
    }
  }

  func createDirectory(parentPath: String, name: String, result: @escaping FlutterResult) {
    guard let parent = writableURL(for: parentPath) else {
      result(FlutterError(code: "access_denied", message: "目录未授权", details: parentPath))
      return
    }
    let target = parent.appendingPathComponent(name)
    do {
      try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
      result(target.path)
    } catch {
      result(FlutterError(code: "create_failed", message: error.localizedDescription, details: target.path))
    }
  }

  func exists(path: String, result: @escaping FlutterResult) {
    result(FileManager.default.fileExists(atPath: path))
  }

  private func moveOrCopy(
    sourcePath: String,
    targetDirectory: String,
    move: Bool,
    result: @escaping FlutterResult
  ) {
    guard let source = writableURL(for: sourcePath) else {
      result(FlutterError(code: "access_denied", message: "目录未授权", details: sourcePath))
      return
    }
    guard let targetDirectoryURL = writableURL(for: targetDirectory) else {
      result(FlutterError(code: "access_denied", message: "目录未授权", details: targetDirectory))
      return
    }
    let target = targetDirectoryURL.appendingPathComponent(source.lastPathComponent)
    if FileManager.default.fileExists(atPath: target.path) {
      result(FlutterError(code: "conflict", message: "目标已存在", details: target.path))
      return
    }
    do {
      if move {
        // 不能直接 moveItem：源几乎总在 app 容器（Documents/downloads）里，
        // 目标却是用户在「文件」App 里选的目录——那是另一个 volume，跨卷
        // rename 必然失败（EXDEV）。表现就是「复制能成、移动不行」。
        // 改成复制 + 删源，「移动」在跨卷下本来也只能这么实现。
        try FileManager.default.copyItem(at: source, to: target)
        do {
          try FileManager.default.removeItem(at: source)
        } catch {
          // 副本已经写进去了但源没删掉：不回滚的话用户会看到两份文件，
          // 还以为搬成功了。清掉副本，让这一次操作整体失败。
          try? FileManager.default.removeItem(at: target)
          throw error
        }
      } else {
        try FileManager.default.copyItem(at: source, to: target)
      }
      result(target.path)
    } catch {
      result(FlutterError(
        code: move ? "move_failed" : "copy_failed",
        message: error.localizedDescription,
        details: sourcePath
      ))
    }
  }

  /// 确认 [path] 可写，并返回其 URL。
  ///
  /// 两类路径放行：
  ///
  /// 1. **应用沙盒内**（Documents / Library / tmp）。下载目录就在
  ///    `Documents/downloads`，本来就不需要任何授权；早期只认 security-scoped
  ///    目录，结果主场景——把下载好的歌搬出去——连列都列不出来。
  /// 2. **用户显式授权过的目录**（security-scoped bookmark）。
  ///
  /// 用 `resolvingSymlinksInPath` 比较：iOS 上 `/var` 与 `/private/var`
  /// 指向同一处，不解析会误判成「不在授权目录内」。
  private func writableURL(for path: String) -> URL? {
    let candidate = URL(fileURLWithPath: path).resolvingSymlinksInPath()
    if isInsideSandbox(candidate) {
      return candidate
    }
    for directory in activeDirectories() {
      let root = directory.resolvingSymlinksInPath()
      if candidate.path == root.path || candidate.path.hasPrefix(root.path + "/") {
        return candidate
      }
    }
    return nil
  }

  /// 是否在应用自己的容器内。
  ///
  /// 同时比 `NSHomeDirectory()` 和解析符号链接后的形式，因为 iOS 上
  /// `NSHomeDirectory()` 给的是 `/var/...` 而 `URL.path` 可能是
  /// `/private/var/...`。
  private func isInsideSandbox(_ url: URL) -> Bool {
    let roots = [
      NSHomeDirectory(),
      URL(fileURLWithPath: NSHomeDirectory()).resolvingSymlinksInPath().path,
    ]
    return roots.contains { root in
      url.path == root || url.path.hasPrefix(root + "/")
    }
  }
}

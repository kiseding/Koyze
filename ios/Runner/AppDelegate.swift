import Flutter
import UIKit
import Darwin
import UniformTypeIdentifiers

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate,
  UIDocumentPickerDelegate {
  private var sourceTasks: [String: URLSessionDataTask] = [:]
  private var cancelledSourceTaskIDs = Set<String>()
  private let sourceTaskLock = NSLock()
  private lazy var directoryAccess = SecurityScopedDirectoryAccess()

  /// 正在进行中的导出：`Result` 要等用户在文档选择器里点完才有值。
  private var pendingExportResult: FlutterResult?
  private var pendingExportSource: URL?
  /// 系统「下载」之外，用户上一次选的导出目标（security-scoped URL）。
  private var activeExportDirectory: URL?
  private static let exportDirectoryBookmarkKey = "koyze.exportDirectoryBookmark"
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // audio 后台模式不会露出设置里的「后台 App 刷新」。声明 fetch 之后
    // 还要把间隔降到系统允许的最小值，iOS 才会把 App 放进调度池。
    application.setMinimumBackgroundFetchInterval(
      UIApplication.backgroundFetchIntervalMinimum
    )
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // FlutterAppDelegate hijacks responds(to:) for performFetch and only
  // returns true when a plugin implements it. Without this override iOS
  // never delivers background-fetch wakes, so Settings would show the
  // toggle but the app would never actually refresh.
  override func responds(to aSelector: Selector!) -> Bool {
    if aSelector == #selector(application(_:performFetchWithCompletionHandler:)) {
      return true
    }
    return super.responds(to: aSelector)
  }

  override func application(
    _ application: UIApplication,
    performFetchWithCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
  ) {
    // Fetch is declared so Settings shows Background App Refresh. Widget
    // timelines already refresh from the app group while audio is active;
    // this wake only needs to complete so iOS keeps scheduling the app.
    completionHandler(.noData)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(
      forPlugin: "LXFileProtection"
    ) else { return }
    let channel = FlutterMethodChannel(
      name: "koyze/file_protection",
      binaryMessenger: registrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      guard call.method == "ensureBackgroundReadable",
            let arguments = call.arguments as? [String: Any],
            let rawPath = arguments["path"] as? String else {
        result(FlutterMethodNotImplemented)
        return
      }
      let path = (rawPath as NSString).standardizingPath
      let home = (NSHomeDirectory() as NSString).standardizingPath + "/"
      guard path.hasPrefix(home), FileManager.default.fileExists(atPath: path) else {
        result(FlutterError(
          code: "invalid_path",
          message: "Playback cache path is outside the application container",
          details: nil
        ))
        return
      }
      do {
        try FileManager.default.setAttributes(
          [.protectionKey: FileProtectionType.none],
          ofItemAtPath: path
        )
        result(nil)
      } catch {
        result(FlutterError(
          code: "file_protection",
          message: error.localizedDescription,
          details: nil
        ))
      }
    }

    let directoryChannel = FlutterMethodChannel(
      name: "koyze/security_scoped_directory",
      binaryMessenger: registrar.messenger()
    )
    directoryChannel.setMethodCallHandler { [weak self] call, result in
      guard let self else { return }
      switch call.method {
      case "selectDirectory":
        self.directoryAccess.select(presenter: self.topViewController(), result: result)
      case "restoreDirectories":
        result(self.directoryAccess.restore())
      case "stopAccess":
        self.directoryAccess.stopAll()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    // 文件管理：只在用户已授权的 security-scoped 目录内生效。
    let fileChannel = FlutterMethodChannel(
      name: "koyze/local_file_system",
      binaryMessenger: registrar.messenger()
    )
    fileChannel.setMethodCallHandler { [weak self] call, result in
      guard let self else { return }
      let args = call.arguments as? [String: Any] ?? [:]
      let source = args["source"] as? String
      let target = args["target"] as? String
      let path = args["path"] as? String
      let access = SecurityScopedFileAccess { [weak self] in
        self?.directoryAccess.activeDirectoryURLs ?? []
      }
      switch call.method {
      case "listDirectory":
        guard let path else {
          result(FlutterError(code: "invalid_args", message: "Missing path", details: nil))
          return
        }
        access.listDirectory(path: path, result: result)
      case "copyInto":
        guard let source, let target else {
          result(FlutterError(code: "invalid_args", message: "Missing source or target", details: nil))
          return
        }
        access.copyInto(sourcePath: source, targetDirectory: target, result: result)
      case "moveInto":
        guard let source, let target else {
          result(FlutterError(code: "invalid_args", message: "Missing source or target", details: nil))
          return
        }
        access.moveInto(sourcePath: source, targetDirectory: target, result: result)
      case "rename":
        guard let source, let target else {
          result(FlutterError(code: "invalid_args", message: "Missing source or target", details: nil))
          return
        }
        access.rename(sourcePath: source, newName: target, result: result)
      case "deleteFile":
        guard let path else {
          result(FlutterError(code: "invalid_args", message: "Missing path", details: nil))
          return
        }
        access.deleteFile(path: path, result: result)
      case "createDirectory":
        guard let source, let target else {
          result(FlutterError(code: "invalid_args", message: "Missing source or target", details: nil))
          return
        }
        access.createDirectory(parentPath: source, name: target, result: result)
      case "exists":
        guard let path else {
          result(FlutterError(code: "invalid_args", message: "Missing path", details: nil))
          return
        }
        access.exists(path: path, result: result)
      case "exportToPublicDownloads":
        guard let source else {
          result(FlutterError(code: "invalid_args", message: "Missing source", details: nil))
          return
        }
        self.exportToDownloads(sourcePath: source, result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    let sourceChannel = FlutterMethodChannel(
      name: "koyze/source_transport",
      binaryMessenger: registrar.messenger()
    )
    sourceChannel.setMethodCallHandler { [weak self] call, result in
      guard let self else { return }
      if call.method == "cancel",
         let arguments = call.arguments as? [String: Any],
         let id = arguments["id"] as? String {
        self.sourceTaskLock.lock()
        let task = self.sourceTasks.removeValue(forKey: id)
        if task == nil {
          self.cancelledSourceTaskIDs.insert(id)
          DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self] in
            self?.sourceTaskLock.lock()
            self?.cancelledSourceTaskIDs.remove(id)
            self?.sourceTaskLock.unlock()
          }
        }
        self.sourceTaskLock.unlock()
        task?.cancel()
        result(nil)
        return
      }
      guard call.method == "request",
            let arguments = call.arguments as? [String: Any],
            let id = arguments["id"] as? String,
            let rawURL = arguments["url"] as? String,
            let url = URL(string: rawURL),
            url.scheme == "http" || url.scheme == "https" else {
        result(FlutterMethodNotImplemented)
        return
      }
      sourceTaskLock.lock()
      let wasCancelled = cancelledSourceTaskIDs.remove(id) != nil
      sourceTaskLock.unlock()
      if wasCancelled {
        result(FlutterError(code: "cancelled", message: "Source request was cancelled", details: nil))
        return
      }
      guard SourceTransportDelegate.hasOnlyPublicAddresses(host: url.host ?? "") else {
        result(FlutterError(code: "blocked_address", message: "Source destination is not public", details: nil))
        return
      }
      var request = URLRequest(url: url)
      request.httpMethod = arguments["method"] as? String ?? "GET"
      if let headers = arguments["headers"] as? [String: String] {
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
      }
      if let body = arguments["body"] as? String {
        request.httpBody = Data(base64Encoded: body)
      }
      let timeoutMs = arguments["timeoutMs"] as? Int ?? 15_000
      request.timeoutInterval = Double(timeoutMs) / 1_000.0

      let configuration = URLSessionConfiguration.ephemeral
      configuration.httpCookieAcceptPolicy = .never
      configuration.httpShouldSetCookies = false
      configuration.requestCachePolicy = .useProtocolCachePolicy
      let maximumResponseBytes = arguments["maximumResponseBytes"] as? Int ?? 10 * 1024 * 1024
      let resultGate = FlutterResultGate(result)
      let delegate = SourceTransportDelegate(maximumResponseBytes: maximumResponseBytes) {
        [weak self] data, response, error in
        guard let self else { return }
        self.sourceTaskLock.lock()
        self.sourceTasks.removeValue(forKey: id)
        self.sourceTaskLock.unlock()
        DispatchQueue.main.async {
          if let error {
            resultGate.complete(
              FlutterError(code: "source_transport", message: error.localizedDescription, details: nil)
            )
            return
          }
          guard let response = response as? HTTPURLResponse else {
            resultGate.complete(
              FlutterError(code: "source_transport", message: "Missing HTTP response", details: nil)
            )
            return
          }
          var headers: [String: [String]] = [:]
          for (name, value) in response.allHeaderFields {
            headers[String(describing: name)] = [String(describing: value)]
          }
          resultGate.complete([
            "statusCode": response.statusCode,
            "statusMessage": HTTPURLResponse.localizedString(forStatusCode: response.statusCode),
            "headers": headers,
            "body": (data ?? Data()).base64EncodedString(),
          ])
        }
      }
      let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
      delegate.session = session
      let task = session.dataTask(with: request)
      sourceTaskLock.lock()
      if cancelledSourceTaskIDs.remove(id) != nil {
        sourceTaskLock.unlock()
        task.cancel()
        session.finishTasksAndInvalidate()
        resultGate.complete(
          FlutterError(code: "cancelled", message: "Source request was cancelled", details: nil)
        )
        return
      }
      sourceTasks[id] = task
      sourceTaskLock.unlock()
      task.resume()
    }
  }

  // MARK: - 导出到「文件」App

  /// 把私有目录里的一首歌复制到用户看得见的地方。
  ///
  /// iOS 没有公共「下载」文件夹——沙盒应用能写的位置只有自己的容器。所以
  /// 这里跟鸿蒙走同一套语义：**弹一次目录选择器，把用户选的目录记住**，
  /// 之后每首歌都直接复制进去，不再打扰用户。第一次选完，导出 N 首也只是
  /// 一次授权。
  ///
  /// 为什么不打开 `UIFileSharingEnabled`：那个键会把整个 Documents 目录摊
  /// 在「文件」App 里，而 `playlists.v1.json` 与 `local_artwork/` 就在那，
  /// 用户删掉一个歌单文件就是全部歌单丢失。用选择器当出口没有这个风险。
  private func exportToDownloads(sourcePath: String, result: @escaping FlutterResult) {
    let source = URL(fileURLWithPath: sourcePath)
    guard FileManager.default.fileExists(atPath: source.path) else {
      result(FlutterError(
        code: "not_found",
        message: "要导出的文件不存在",
        details: sourcePath
      ))
      return
    }
    if pendingExportResult != nil {
      result(FlutterError(
        code: "busy",
        message: "上一次导出还没结束",
        details: sourcePath
      ))
      return
    }
    // 用户之前选过目录、书签还能解开：直接写，不弹选择器。
    if let directory = resolvedExportDirectory() {
      copyForExport(source: source, into: directory, result: result)
      return
    }
    pendingExportSource = source
    pendingExportResult = result
    presentExportPicker()
  }

  /// 用户上一次选的导出目标目录（仍在授权期内时）。
  ///
  /// 解析成功就 `startAccessingSecurityScopedResource()` 并常驻——导出是一次
  /// 一首循环调用的，每次进出都 start/stop 既容易漏配平，也没必要。真正失效
  /// 的判据是「书签解不开」或「目录不存在」，那两种情况会把书签清掉，让下次
  /// 导出重新弹选择器。
  private func resolvedExportDirectory() -> URL? {
    if let active = activeExportDirectory,
       FileManager.default.fileExists(atPath: active.path) {
      return active
    }
    activeExportDirectory = nil
    guard let data = UserDefaults.standard.data(
      forKey: Self.exportDirectoryBookmarkKey
    ) else { return nil }
    var stale = false
    guard let url = try? URL(
      resolvingBookmarkData: data,
      options: [],
      relativeTo: nil,
      bookmarkDataIsStale: &stale
    ) else {
      UserDefaults.standard.removeObject(forKey: Self.exportDirectoryBookmarkKey)
      return nil
    }
    guard url.startAccessingSecurityScopedResource() else {
      // 书签还在但授权已撤销（用户在「文件」App 里挪走/删掉了这个目录）。
      UserDefaults.standard.removeObject(forKey: Self.exportDirectoryBookmarkKey)
      return nil
    }
    // 书签过期不等于目录消失（换机恢复、系统升级都会让它 stale），重新
    // 生成一份再继续用；只有真正打不开时才要求重选。
    if stale, let refreshed = try? url.bookmarkData(
      options: [],
      includingResourceValuesForKeys: nil,
      relativeTo: nil
    ) {
      UserDefaults.standard.set(refreshed, forKey: Self.exportDirectoryBookmarkKey)
    }
    activeExportDirectory = url
    return url
  }

  /// 弹出目录选择器（`folder` 模式），让用户挑导出目标。
  private func presentExportPicker() {
    let picker = UIDocumentPickerViewController(
      forOpeningContentTypes: [.folder],
      asCopy: false
    )
    picker.delegate = self
    picker.allowsMultipleSelection = false
    guard let presenter = topViewController() else {
      finishExport(
        FlutterError(code: "no_presenter", message: "界面未就绪", details: nil)
      )
      return
    }
    presenter.present(picker, animated: true)
  }

  /// 把文件复制进已授权的目录。
  ///
  /// 不再自己 `startAccessingSecurityScopedResource`：调用方保证 [directory]
  /// 已经激活（书签解析处常驻、picker 回调里 start 过）。多 start 一次的计数
  /// 一旦漏配平，授权会一直挂着，用户撤销权限后仍能写——那是更糟的状态。
  private func copyForExport(
    source: URL,
    into directory: URL,
    result: @escaping FlutterResult
  ) {
    let target = directory.appendingPathComponent(source.lastPathComponent)
    do {
      // 覆盖式：同一首歌重复导出不该报错，用户要的就是「现在这里是最新的」。
      if FileManager.default.fileExists(atPath: target.path) {
        try FileManager.default.removeItem(at: target)
      }
      try FileManager.default.copyItem(at: source, to: target)
      result(target.path)
    } catch {
      result(FlutterError(
        code: "export_failed",
        message: error.localizedDescription,
        details: source.path
      ))
    }
  }

  private func finishExport(_ value: Any?) {
    let pending = pendingExportResult
    pendingExportResult = nil
    pendingExportSource = nil
    pending?(value)
  }

  func documentPicker(
    _ controller: UIDocumentPickerViewController,
    didPickDocumentsAt urls: [URL]
  ) {
    guard let source = pendingExportSource, let directory = urls.first else {
      finishExport(nil)
      return
    }
    guard directory.startAccessingSecurityScopedResource() else {
      finishExport(FlutterError(
        code: "access_denied",
        message: "无法访问所选文件夹",
        details: directory.path
      ))
      return
    }
    // 授权保持常驻：导出是一首一首循环调用的，复制完就 stop 的话，第二首歌
    // 拿到的 activeExportDirectory 已经没有写权限了。
    activeExportDirectory = directory
    if let bookmark = try? directory.bookmarkData(
      options: [],
      includingResourceValuesForKeys: nil,
      relativeTo: nil
    ) {
      UserDefaults.standard.set(bookmark, forKey: Self.exportDirectoryBookmarkKey)
    }
    let pending = pendingExportResult
    // 先取出 result 再调用 copyForExport：它会通过 finishExport 清空。
    pendingExportResult = nil
    pendingExportSource = nil
    copyForExport(source: source, into: directory, result: { value in
      pending?(value)
    })
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    // 空串表示「用户取消」，与 `pickDirectory` 的约定一致。
    finishExport("")
  }

  private func topViewController() -> UIViewController? {
    let sceneWindow = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .first(where: { $0.activationState == .foregroundActive })?
      .windows
      .first(where: { $0.isKeyWindow })
    var controller = sceneWindow?.rootViewController ?? window?.rootViewController
    while let presented = controller?.presentedViewController {
      controller = presented
    }
    return controller
  }
}

private final class SecurityScopedDirectoryAccess: NSObject, UIDocumentPickerDelegate {
  private let bookmarkKey = "koyze.security_scoped_directory_bookmarks"
  private var activeURLs: [String: URL] = [:]

  /// 供文件操作复用：只有这些目录内的路径才允许写。
  var activeDirectoryURLs: [URL] { Array(activeURLs.values) }
  private var pendingResult: FlutterResult?

  func select(presenter: UIViewController?, result: @escaping FlutterResult) {
    guard let presenter else {
      result(FlutterError(code: "no_presenter", message: "Unable to present directory picker", details: nil))
      return
    }
    pendingResult = result
    // Use the pre-iOS-14 initializer because the app still supports older
    // deployment targets. The public.folder UTI provides the same directory
    // security-scoped URL behavior on supported iOS versions.
    let picker = UIDocumentPickerViewController(
      documentTypes: ["public.folder"],
      in: .open
    )
    picker.delegate = self
    picker.allowsMultipleSelection = false
    presenter.present(picker, animated: true)
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    guard let url = urls.first, url.startAccessingSecurityScopedResource() else {
      pendingResult?(FlutterError(code: "access_denied", message: "Directory access was denied", details: nil))
      pendingResult = nil
      return
    }
    activeURLs[url.path] = url
    do {
      var bookmarks = UserDefaults.standard.dictionary(forKey: bookmarkKey) as? [String: String] ?? [:]
      bookmarks[url.path] = try SecurityScopedDirectoryAccess.bookmark(for: url)
      UserDefaults.standard.set(bookmarks, forKey: bookmarkKey)
      pendingResult?(url.path)
    } catch {
      url.stopAccessingSecurityScopedResource()
      pendingResult?(FlutterError(code: "bookmark_failed", message: error.localizedDescription, details: nil))
    }
    pendingResult = nil
  }

  /// 创建能在下次启动时重新拿到 security scope 的 bookmark。
  ///
  /// **不能**用 `.minimalBookmark`。那个选项的语义是「只记足够定位的东西」，
  /// 它不下发安全作用域信息；用它存下来的 bookmark 在重启后
  /// `startAccessingSecurityScopedResource()` 一律返回 false——用户当场选
  /// 完目录能用，杀掉进程再打开授权就没了。5.2.0 就是这样：设置里选了
  /// iOS「文件」App 的 Music 文件夹，重启后目录读不了，界面停在
  /// 「Koyze could not start / PathAccessException」。
  ///
  /// iOS 上的正确写法是**不给任何选项**：`URL.BookmarkCreationOptions` 里
  /// 只有 `.minimalBookmark` / `.suitableForBookmarkFile` 对 iOS 开放，
  /// `.withSecurityScope` 是 macOS 专有的（iOS 上不可用，写了编译不过）。
  /// 空选项创建的 bookmark 会自动携带安全作用域，这正是文档选择器授权的
  /// 标准持久化方式。
  static func bookmark(for url: URL) throws -> String {
    let data = try url.bookmarkData(
      options: [],
      includingResourceValuesForKeys: nil,
      relativeTo: nil
    )
    return data.base64EncodedString()
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    pendingResult?(nil)
    pendingResult = nil
  }

  func restore() -> [String] {
    let bookmarks = UserDefaults.standard.dictionary(forKey: bookmarkKey) as? [String: String] ?? [:]
    var paths: [String] = []
    var updated = bookmarks
    // 幂等：Dart 侧会在启动早期恢复一次（下载服务要用），曲库初始化时再
    // 恢复一次。已经激活的 URL 不再重复 startAccessing——iOS 的访问计数是
    // 成对的，多 start 一次就多欠一次 stop，stopAll 只会还一次。
    for url in activeURLs.values {
      paths.append(url.path)
    }
    for (fallbackPath, encoded) in bookmarks {
      if activeURLs[fallbackPath] != nil {
        // 已经激活过，但 URL 可能和这次解析出来的不同（stale 刷新过），
        // 以已激活的为准，不重复解析。
        continue
      }
      guard let data = Data(base64Encoded: encoded) else { continue }
      do {
        var stale = false
        let url = try SecurityScopedDirectoryAccess.resolveBookmark(data, isStale: &stale)
        guard url.startAccessingSecurityScopedResource() else {
          // 授权拿不回来（目录被删、provider 卸载、用户改过位置）。这条
          // bookmark 留着没意义，删掉它，下次启动不用再为注定失败的路径
          // 白跑一遍。
          //
          // 注意**只删 bookmark，不删 Dart 侧的目录设置**：后者是用户可见
          // 的选择，由设置页展示「所选目录不可用」并让用户重新选；在这里
          // 悄悄抹掉，用户只会看到自己的设置凭空消失。
          updated.removeValue(forKey: fallbackPath)
          continue
        }
        activeURLs[fallbackPath] = url
        paths.append(url.path)
        if stale, let refreshed = try? SecurityScopedDirectoryAccess.bookmark(for: url) {
          // stale 说明 provider 那边换了标识（例如用户在「文件」App 里
          // 重命名了目录）。不刷新的话下次启动还会拿到旧数据。
          updated[fallbackPath] = refreshed
        }
      } catch {
        updated.removeValue(forKey: fallbackPath)
        continue
      }
    }
    if updated != bookmarks {
      UserDefaults.standard.set(updated, forKey: bookmarkKey)
    }
    return paths
  }

  /// 解析 bookmark。iOS 上没有 `.withSecurityScope` 这个解析选项（那是
  /// macOS 的），传 `.withoutUI` 即可——安全作用域是 bookmark 自身带的，
  /// 由创建时的选项决定，不在解析时指定。
  static func resolveBookmark(_ data: Data, isStale: inout Bool) throws -> URL {
    try URL(
      resolvingBookmarkData: data,
      options: [.withoutUI],
      relativeTo: nil,
      bookmarkDataIsStale: &isStale
    )
  }

  func stopAll() {
    for url in activeURLs.values {
      url.stopAccessingSecurityScopedResource()
    }
    activeURLs.removeAll()
  }
}

private final class FlutterResultGate {
  private let result: FlutterResult
  private let lock = NSLock()
  private var completed = false

  init(_ result: @escaping FlutterResult) {
    self.result = result
  }

  func complete(_ value: Any?) {
    lock.lock()
    guard !completed else {
      lock.unlock()
      return
    }
    completed = true
    lock.unlock()
    result(value)
  }
}

private final class SourceTransportDelegate: NSObject, URLSessionDataDelegate {
  weak var session: URLSession?
  private let maximumResponseBytes: Int
  private let completion: (Data?, URLResponse?, Error?) -> Void
  private var data = Data()
  private var response: URLResponse?
  private var completed = false

  init(
    maximumResponseBytes: Int,
    completion: @escaping (Data?, URLResponse?, Error?) -> Void
  ) {
    self.maximumResponseBytes = maximumResponseBytes
    self.completion = completion
  }

  func urlSession(
    _ session: URLSession,
    dataTask: URLSessionDataTask,
    didReceive response: URLResponse,
    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
  ) {
    if response.expectedContentLength > maximumResponseBytes {
      completionHandler(.cancel)
      finish(error: NSError(
        domain: "LXSourceTransport",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Source response exceeded the byte limit"]
      ))
      return
    }
    self.response = response
    completionHandler(.allow)
  }

  func urlSession(
    _ session: URLSession,
    dataTask: URLSessionDataTask,
    didReceive data: Data
  ) {
    guard self.data.count + data.count <= maximumResponseBytes else {
      dataTask.cancel()
      finish(error: NSError(
        domain: "LXSourceTransport",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Source response exceeded the byte limit"]
      ))
      return
    }
    self.data.append(data)
  }

  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didCompleteWithError error: Error?
  ) {
    finish(error: error)
  }

  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest,
    completionHandler: @escaping (URLRequest?) -> Void
  ) {
    completionHandler(nil)
  }

  private static func isPrivateIPv4(_ first: UInt8, _ second: UInt8) -> Bool {
    return first == 0 || first == 10 || first == 127 || first >= 224 ||
      (first == 100 && second >= 64 && second <= 127) ||
      (first == 169 && second == 254) ||
      (first == 172 && second >= 16 && second <= 31) ||
      (first == 192 && second == 168)
  }

  private func finish(error: Error?) {
    guard !completed else { return }
    completed = true
    completion(error == nil ? data : nil, response, error)
    session?.finishTasksAndInvalidate()
  }

  static func hasOnlyPublicAddresses(host: String) -> Bool {
    guard !host.isEmpty else { return false }
    var hints = addrinfo(
      ai_flags: AI_ADDRCONFIG,
      ai_family: AF_UNSPEC,
      ai_socktype: SOCK_STREAM,
      ai_protocol: IPPROTO_TCP,
      ai_addrlen: 0,
      ai_canonname: nil,
      ai_addr: nil,
      ai_next: nil
    )
    var result: UnsafeMutablePointer<addrinfo>?
    guard getaddrinfo(host, nil, &hints, &result) == 0, let first = result else {
      return false
    }
    defer { freeaddrinfo(result) }
    var current: UnsafeMutablePointer<addrinfo>? = first
    var found = false
    while let info = current {
      guard let address = info.pointee.ai_addr else { return false }
      found = true
      if address.pointee.sa_family == sa_family_t(AF_INET) {
        let value = address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
          UInt32(bigEndian: $0.pointee.sin_addr.s_addr)
        }
        let first = UInt8((value >> 24) & 0xff)
        let second = UInt8((value >> 16) & 0xff)
        if Self.isPrivateIPv4(first, second) {
          return false
        }
      } else if address.pointee.sa_family == sa_family_t(AF_INET6) {
        let bytes = address.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) {
          withUnsafeBytes(of: $0.pointee.sin6_addr) { Array($0) }
        }
        // IPv4-mapped IPv6 (::ffff:a.b.c.d)：解码出 IPv4 后按私网规则检查，
        // 否则 ::ffff:127.0.0.1 等映射地址可绕过上面的 IPv4 拦截。
        if bytes[0...9].allSatisfy({ $0 == 0 }), bytes[10] == 0xff, bytes[11] == 0xff {
          if bytes[12...15].allSatisfy({ $0 == 0 }) ||
             Self.isPrivateIPv4(bytes[12], bytes[13]) {
            return false
          }
        } else if bytes.allSatisfy({ $0 == 0 }) || bytes == Array(repeating: 0, count: 15) + [1] ||
           (bytes[0] & 0xfe) == 0xfc ||
           (bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80) || bytes[0] == 0xff {
          return false
        }
      }
      current = info.pointee.ai_next
    }
    return found
  }
}

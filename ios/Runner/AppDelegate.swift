import Flutter
import UIKit
import Darwin
import UniformTypeIdentifiers

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var sourceTasks: [String: URLSessionDataTask] = [:]
  private var cancelledSourceTaskIDs = Set<String>()
  private let sourceTaskLock = NSLock()
  private lazy var directoryAccess = SecurityScopedDirectoryAccess()
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
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
      bookmarks[url.path] = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil).base64EncodedString()
      UserDefaults.standard.set(bookmarks, forKey: bookmarkKey)
      pendingResult?(url.path)
    } catch {
      url.stopAccessingSecurityScopedResource()
      pendingResult?(FlutterError(code: "bookmark_failed", message: error.localizedDescription, details: nil))
    }
    pendingResult = nil
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    pendingResult?(nil)
    pendingResult = nil
  }

  func restore() -> [String] {
    let bookmarks = UserDefaults.standard.dictionary(forKey: bookmarkKey) as? [String: String] ?? [:]
    var paths: [String] = []
    for (fallbackPath, encoded) in bookmarks {
      guard let data = Data(base64Encoded: encoded) else { continue }
      do {
        var stale = false
        let url = try URL(resolvingBookmarkData: data, bookmarkDataIsStale: &stale)
        guard url.startAccessingSecurityScopedResource() else { continue }
        activeURLs[fallbackPath] = url
        paths.append(url.path)
      } catch {
        continue
      }
    }
    return paths
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

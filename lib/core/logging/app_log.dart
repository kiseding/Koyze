import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

enum AppLogLevel { info, warning, error }

final class AppLogEntry {
  const AppLogEntry({
    required this.timestamp,
    required this.level,
    required this.category,
    required this.message,
    this.stackTrace,
  });

  final DateTime timestamp;
  final AppLogLevel level;
  final String category;
  final String message;
  final String? stackTrace;

  String get text {
    final time = timestamp.toIso8601String();
    final levelName = level.name.toUpperCase();
    final buffer = StringBuffer('[$time][$levelName][$category] $message');
    if (stackTrace case final stack? when stack.isNotEmpty) {
      buffer
        ..write('\n')
        ..write(stack);
    }
    return buffer.toString();
  }
}

/// 内存里的运行日志。
///
/// 只在「记录中」时才收日志：[record] 在未开始记录时直接返回，调用点遍布整个
/// 应用（一百多处），不这么做它们会在用户没看诊断面板的时候一直往内存里堆字符串、
/// 每来一条还要重建一次 [entries] 列表。诊断面板打开时 [start]，关闭时 [stop]。
final class AppLog with WidgetsBindingObserver {
  AppLog({this.maximumEntries = 2000, bool startRecording = false})
    : _collecting = startRecording;

  static final AppLog instance = AppLog();

  final int maximumEntries;
  final List<AppLogEntry> _items = [];
  final ValueNotifier<List<AppLogEntry>> entries =
      ValueNotifier<List<AppLogEntry>>(const []);
  DebugPrintCallback? _previousDebugPrint;
  FlutterExceptionHandler? _previousFlutterError;
  bool Function(Object error, StackTrace stackTrace)? _previousPlatformError;
  bool _hooksInstalled = false;
  bool _collecting;

  /// 是否正在记录。诊断面板打开期间为 true。
  bool get isActive => _collecting;

  /// 开始记录。
  ///
  /// [installHooks] 为 false 时只打开记录开关，不去接管 debugPrint 与全局错误
  /// 处理器——单元测试里没有绑定好的 WidgetsBinding，接管会直接抛异常。
  void start({bool installHooks = true}) {
    if (_collecting) {
      if (installHooks) _installHooks();
      return;
    }
    _collecting = true;
    if (installHooks) _installHooks();
    record('app', 'diagnostic logging started');
  }

  void stop() {
    if (!_collecting) return;
    _collecting = false;
    _removeHooks();
  }

  void _installHooks() {
    if (_hooksInstalled) return;
    _hooksInstalled = true;
    _previousDebugPrint = debugPrint;
    debugPrint = _captureDebugPrint;
    _previousFlutterError = FlutterError.onError;
    FlutterError.onError = _captureFlutterError;
    _previousPlatformError = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = _capturePlatformError;
    WidgetsBinding.instance.addObserver(this);
  }

  void _removeHooks() {
    if (!_hooksInstalled) return;
    _hooksInstalled = false;
    WidgetsBinding.instance.removeObserver(this);
    if (_previousDebugPrint != null) debugPrint = _previousDebugPrint!;
    FlutterError.onError = _previousFlutterError;
    PlatformDispatcher.instance.onError = _previousPlatformError;
    _previousDebugPrint = null;
    _previousFlutterError = null;
    _previousPlatformError = null;
  }

  void record(
    String category,
    Object? message, {
    AppLogLevel level = AppLogLevel.info,
    StackTrace? stackTrace,
  }) {
    if (!_collecting) return;
    var text = _redact(message?.toString() ?? '');
    if (text.length > 8000) {
      text = '${text.substring(0, 8000)}\n… message truncated';
    }
    _items.add(
      AppLogEntry(
        timestamp: DateTime.now(),
        level: level,
        category: category,
        message: text,
        stackTrace: stackTrace == null ? null : _redact(stackTrace.toString()),
      ),
    );
    if (_items.length > maximumEntries) {
      _items.removeRange(0, _items.length - maximumEntries);
    }
    entries.value = List.unmodifiable(_items);
  }

  void clear() {
    if (_items.isEmpty) return;
    _items.clear();
    entries.value = const [];
  }

  String exportText() => _items.map((entry) => entry.text).join('\n\n');

  void _captureDebugPrint(String? message, {int? wrapWidth}) {
    if (message != null && message.isNotEmpty) record('debug', message);
    _previousDebugPrint?.call(message, wrapWidth: wrapWidth);
  }

  void _captureFlutterError(FlutterErrorDetails details) {
    record(
      'flutter',
      details.exceptionAsString(),
      level: AppLogLevel.error,
      stackTrace: details.stack,
    );
    final previous = _previousFlutterError;
    if (previous != null) {
      previous(details);
    } else {
      FlutterError.presentError(details);
    }
  }

  bool _capturePlatformError(Object error, StackTrace stackTrace) {
    record('platform', error, level: AppLogLevel.error, stackTrace: stackTrace);
    return _previousPlatformError?.call(error, stackTrace) ?? false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    record('lifecycle', state.name);
  }

  @override
  void didHaveMemoryPressure() {
    record('lifecycle', 'memory pressure', level: AppLogLevel.warning);
  }

  String _redact(String value) {
    var redacted = value
        .replaceAllMapped(
          RegExp(
            r'(authorization\s*[:=]\s*)(?:bearer\s+)?[^\s,]+',
            caseSensitive: false,
          ),
          (match) => '${match.group(1)}***',
        )
        .replaceAllMapped(
          RegExp(
            r'((?:access[-_]?token|token)\s*[:=]\s*)[^\s,&#]+',
            caseSensitive: false,
          ),
          (match) => '${match.group(1)}***',
        )
        .replaceAllMapped(
          RegExp(
            r'([?&](?:(?:access[-_]?token|token)|authorization|signature|sign|'
            r'(?:x-)?api[-_]?key|cookie|password)=)[^&#\s]+',
            caseSensitive: false,
          ),
          (match) => '${match.group(1)}***',
        )
        .replaceAllMapped(
          RegExp(r'(cookie\s*[:=]\s*)[^\r\n]+', caseSensitive: false),
          (match) => '${match.group(1)}***',
        );
    redacted = redacted.replaceAllMapped(
      RegExp(r'''https?://[^\s<>"']+''', caseSensitive: false),
      (match) => _redactUri(match.group(0)!),
    );
    return redacted.replaceAllMapped(
      RegExp(
        r'(?<![A-Za-z0-9_-])eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+',
      ),
      (_) => '[JWT_REDACTED]',
    );
  }

  String _redactUri(String value) {
    final trailing = RegExp(r'[),.;:]+$').firstMatch(value)?.group(0) ?? '';
    final raw = trailing.isEmpty
        ? value
        : value.substring(0, value.length - trailing.length);
    final uri = Uri.tryParse(raw);
    if (uri == null || uri.host.isEmpty) return value;
    final safe = uri.replace(
      userInfo: '',
      query: uri.hasQuery ? 'redacted' : null,
      fragment: uri.hasFragment ? 'redacted' : null,
    );
    return '$safe$trailing';
  }
}

final class AppLogNavigationObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    AppLog.instance.record('navigation', 'push ${_routeName(route)}');
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    AppLog.instance.record('navigation', 'pop ${_routeName(route)}');
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    AppLog.instance.record(
      'navigation',
      'replace ${_routeName(oldRoute)} → ${_routeName(newRoute)}',
    );
  }

  String _routeName(Route<dynamic>? route) =>
      route?.settings.name ?? route?.runtimeType.toString() ?? 'unknown';
}

final appLogNavigationObserver = AppLogNavigationObserver();

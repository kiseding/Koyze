// Copyright 2024 Koyze Contributors
// Licensed under the Apache License, Version 2.0

/// Music source health monitoring service.
/// 
/// Periodically checks all music platforms for availability,
/// tracks latency, and notifies when sources go down.

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';

enum HealthStatus { healthy, degraded, down, unknown }

class SourceHealth {
  final HealthStatus status;
  final DateTime lastCheck;
  final String? error;
  final int? latencyMs;
  final String? httpStatus;

  SourceHealth({
    required this.status,
    required this.lastCheck,
    this.error,
    this.latencyMs,
    this.httpStatus,
  });

  bool get isHealthy => status == HealthStatus.healthy;
  bool get isDegraded => status == HealthStatus.degraded;
  bool get isDown => status == HealthStatus.down;
}

enum MusicPlatform {
  qq('QQ音乐', 'https://y.qq.com'),
  netease('网易云音乐', 'https://music.163.com'),
  kuwo('酷我音乐', 'https://kuwo.cn'),
  kugou('酷狗音乐', 'https://kugou.com'),
  migu('咪咕音乐', 'https://music.migu.cn');

  final String displayName;
  final String baseUrl;
  
  const MusicPlatform(this.displayName, this.baseUrl);
}

class SourceHealthMonitor {
  static const Duration CHECK_INTERVAL = Duration(hours: 1);
  static const Duration HEALTH_CHECK_TIMEOUT = Duration(seconds: 10);
  static const int MAX_HISTORY_ENTRIES = 100;
  
  final Dio _dio;
  final Map<MusicPlatform, SourceHealth> _healthStatus = {};
  final Map<MusicPlatform, List<SourceHealth>> _healthHistory = {};
  final _healthStreamController = StreamController<Map<MusicPlatform, SourceHealth>>.broadcast();
  
  Timer? _checkTimer;
  bool _isMonitoring = false;

  SourceHealthMonitor({Dio? dio}) : _dio = dio ?? Dio() {
    _configureDio();
  }

  void _configureDio() {
    _dio.options.connectTimeout = HEALTH_CHECK_TIMEOUT;
    _dio.options.receiveTimeout = HEALTH_CHECK_TIMEOUT;
    _dio.options.validateStatus = (status) => true; // Accept all status codes
  }

  /// Start periodic health monitoring.
  void startMonitoring() {
    if (_isMonitoring) return;
    
    _isMonitoring = true;
    
    // Initial check
    checkAllSources();
    
    // Periodic checks
    _checkTimer = Timer.periodic(CHECK_INTERVAL, (_) => checkAllSources());
    
    debugPrint('🏥 Source health monitoring started (interval: ${CHECK_INTERVAL.inMinutes}min)');
  }

  /// Stop health monitoring.
  void stopMonitoring() {
    _checkTimer?.cancel();
    _checkTimer = null;
    _isMonitoring = false;
    
    debugPrint('🏥 Source health monitoring stopped');
  }

  /// Check all music sources.
  Future<void> checkAllSources() async {
    debugPrint('🏥 Running health check for all sources...');
    
    final futures = MusicPlatform.values.map((platform) => checkSource(platform));
    await Future.wait(futures);
    
    _healthStreamController.add(Map.from(_healthStatus));
    
    // Log summary
    final healthy = _healthStatus.values.where((h) => h.isHealthy).length;
    final total = _healthStatus.length;
    debugPrint('🏥 Health check complete: $healthy/$total sources healthy');
  }

  /// Record a health sample without a network call.
  void recordCheck(MusicPlatform platform, SourceHealth health) {
    _updateHealth(platform, health);
  }

  /// Check a specific music source.
  Future<SourceHealth> checkSource(MusicPlatform platform) async {
    final stopwatch = Stopwatch()..start();
    
    try {
      // 1. Basic connectivity test (HEAD request)
      final response = await _dio.head(
        platform.baseUrl,
        options: Options(
          followRedirects: true,
          headers: {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          },
        ),
      );
      
      stopwatch.stop();
      final latency = stopwatch.elapsedMilliseconds;
      
      // 2. Determine health status based on response
      HealthStatus status;
      if (response.statusCode == 200 || response.statusCode == 302) {
        // Check latency threshold
        if (latency < 1000) {
          status = HealthStatus.healthy;
        } else if (latency < 3000) {
          status = HealthStatus.degraded;
        } else {
          status = HealthStatus.degraded;
          debugPrint('⚠️ ${platform.displayName} high latency: ${latency}ms');
        }
      } else if (response.statusCode! >= 400 && response.statusCode! < 500) {
        status = HealthStatus.down;
        debugPrint('🔴 ${platform.displayName} returned ${response.statusCode}');
      } else {
        status = HealthStatus.degraded;
      }
      
      final health = SourceHealth(
        status: status,
        lastCheck: DateTime.now(),
        latencyMs: latency,
        httpStatus: response.statusCode?.toString(),
      );
      
      _updateHealth(platform, health);
      return health;
      
    } on DioException catch (e) {
      stopwatch.stop();
      
      final health = SourceHealth(
        status: HealthStatus.down,
        lastCheck: DateTime.now(),
        error: _formatDioError(e),
        latencyMs: stopwatch.elapsedMilliseconds,
      );
      
      _updateHealth(platform, health);
      
      debugPrint('🔴 ${platform.displayName} health check failed: ${e.type}');
      
      return health;
      
    } catch (e) {
      stopwatch.stop();
      
      final health = SourceHealth(
        status: HealthStatus.down,
        lastCheck: DateTime.now(),
        error: e.toString(),
      );
      
      _updateHealth(platform, health);
      return health;
    }
  }

  void _updateHealth(MusicPlatform platform, SourceHealth health) {
    final previousHealth = _healthStatus[platform];
    _healthStatus[platform] = health;
    
    // Add to history
    _healthHistory.putIfAbsent(platform, () => []).add(health);
    
    // Limit history size
    if (_healthHistory[platform]!.length > MAX_HISTORY_ENTRIES) {
      _healthHistory[platform]!.removeAt(0);
    }
    
    // Detect status change
    if (previousHealth != null && previousHealth.status != health.status) {
      _notifyStatusChange(platform, previousHealth.status, health.status);
    }
  }

  void _notifyStatusChange(
    MusicPlatform platform,
    HealthStatus oldStatus,
    HealthStatus newStatus,
  ) {
    if (newStatus == HealthStatus.down) {
      debugPrint('🚨 ${platform.displayName} went DOWN');
      _sendNotification(
        title: '音源异常',
        body: '${platform.displayName} 暂时不可用，将自动切换备用源',
      );
    } else if (oldStatus == HealthStatus.down && newStatus == HealthStatus.healthy) {
      debugPrint('✅ ${platform.displayName} recovered');
      _sendNotification(
        title: '音源恢复',
        body: '${platform.displayName} 已恢复正常',
      );
    } else if (newStatus == HealthStatus.degraded) {
      debugPrint('⚠️ ${platform.displayName} degraded');
    }
  }

  Future<void> _sendNotification({required String title, required String body}) async {
    // TODO: Integrate with flutter_local_notifications
    // For now, just debug print
    debugPrint('📬 Notification: $title - $body');
  }

  String _formatDioError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
        return 'Connection timeout';
      case DioExceptionType.sendTimeout:
        return 'Send timeout';
      case DioExceptionType.receiveTimeout:
        return 'Receive timeout';
      case DioExceptionType.badResponse:
        return 'Bad response: ${e.response?.statusCode}';
      case DioExceptionType.cancel:
        return 'Request cancelled';
      case DioExceptionType.connectionError:
        return 'Connection error';
      case DioExceptionType.badCertificate:
        return 'Bad certificate';
      case DioExceptionType.unknown:
      default:
        return 'Unknown error: ${e.message}';
    }
  }

  /// Get current health status for all platforms.
  Map<MusicPlatform, SourceHealth> getHealthStatus() {
    return Map.unmodifiable(_healthStatus);
  }

  /// Get health status for a specific platform.
  SourceHealth? getHealth(MusicPlatform platform) {
    return _healthStatus[platform];
  }

  /// Get health history for a platform.
  List<SourceHealth> getHistory(MusicPlatform platform) {
    return List.unmodifiable(_healthHistory[platform] ?? []);
  }

  /// Calculate uptime percentage for a platform.
  double getUptimePercentage(MusicPlatform platform, {Duration? period}) {
    final history = _healthHistory[platform];
    if (history == null || history.isEmpty) return 0.0;
    
    final cutoff = period != null 
        ? DateTime.now().subtract(period)
        : DateTime.fromMillisecondsSinceEpoch(0);
    
    final relevantHistory = history.where((h) => h.lastCheck.isAfter(cutoff)).toList();
    if (relevantHistory.isEmpty) return 0.0;
    
    final healthyCount = relevantHistory.where((h) => h.isHealthy).length;
    return (healthyCount / relevantHistory.length) * 100;
  }

  /// Get average latency for a platform.
  int? getAverageLatency(MusicPlatform platform, {Duration? period}) {
    final history = _healthHistory[platform];
    if (history == null || history.isEmpty) return null;
    
    final cutoff = period != null 
        ? DateTime.now().subtract(period)
        : DateTime.fromMillisecondsSinceEpoch(0);
    
    final relevantHistory = history
        .where((h) => h.lastCheck.isAfter(cutoff) && h.latencyMs != null)
        .toList();
    
    if (relevantHistory.isEmpty) return null;
    
    final totalLatency = relevantHistory.fold<int>(
      0,
      (sum, h) => sum + h.latencyMs!,
    );
    
    return totalLatency ~/ relevantHistory.length;
  }

  /// Stream of health status updates.
  Stream<Map<MusicPlatform, SourceHealth>> get healthStream => 
      _healthStreamController.stream;

  /// Get overall system health.
  HealthStatus getOverallHealth() {
    if (_healthStatus.isEmpty) return HealthStatus.unknown;
    
    final allDown = _healthStatus.values.every((h) => h.isDown);
    if (allDown) return HealthStatus.down;
    
    final anyDown = _healthStatus.values.any((h) => h.isDown);
    final anyDegraded = _healthStatus.values.any((h) => h.isDegraded);
    
    if (anyDown || anyDegraded) return HealthStatus.degraded;
    
    return HealthStatus.healthy;
  }

  /// Export health report as JSON.
  Map<String, dynamic> exportHealthReport() {
    return {
      'timestamp': DateTime.now().toIso8601String(),
      'overallHealth': getOverallHealth().name,
      'platforms': _healthStatus.map((platform, health) {
        return MapEntry(platform.name, {
          'status': health.status.name,
          'lastCheck': health.lastCheck.toIso8601String(),
          'latencyMs': health.latencyMs,
          'httpStatus': health.httpStatus,
          'error': health.error,
          'uptime24h': getUptimePercentage(platform, period: Duration(hours: 24)),
          'avgLatency24h': getAverageLatency(platform, period: Duration(hours: 24)),
        });
      }),
    };
  }

  void dispose() {
    stopMonitoring();
    _healthStreamController.close();
  }
}

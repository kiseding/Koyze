// Copyright 2024 Koyze Contributors
// Licensed under the Apache License, Version 2.0

/// Secure custom source engine with runtime isolation.
/// 
/// Provides execution timeout, memory monitoring, and network rate limiting.

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'custom_source_engine.dart';
import 'source_network_proxy.dart';
import '../presentation/security_monitor_widget.dart';

class SecureSourceEngine {
  final CustomSourceEngine _baseEngine;
  final SourceNetworkProxy _networkProxy;
  final String sourceId;
  
  static const Duration MAX_EXECUTION_TIME = Duration(seconds: 5);
  static const int MAX_MEMORY_MB = 100;
  
  final _securityStatus = ValueNotifier<SourceSecurityStatus>(
    SourceSecurityStatus(sourceId: ''),
  );
  
  Timer? _executionTimer;
  final Stopwatch _totalExecutionTime = Stopwatch();
  final Set<String> _accessedDomains = {};
  final List<SecurityWarning> _warnings = [];

  SecureSourceEngine({
    required CustomSourceEngine baseEngine,
    required this.sourceId,
    SourceNetworkProxy? networkProxy,
  })  : _baseEngine = baseEngine,
        _networkProxy = networkProxy ?? SourceNetworkProxy() {
    _securityStatus.value = SourceSecurityStatus(sourceId: sourceId);
  }

  ValueNotifier<SourceSecurityStatus> get securityStatus => _securityStatus;

  /// Execute a source operation with security constraints.
  Future<T> execute<T>(
    String operation,
    Map<String, dynamic> args, {
    Duration? timeout,
  }) async {
    final executionTimeout = timeout ?? MAX_EXECUTION_TIME;
    
    // Start timeout timer
    final completer = Completer<T>();
    _executionTimer?.cancel();
    _executionTimer = Timer(executionTimeout, () {
      if (!completer.isCompleted) {
        completer.completeError(
          TimeoutException('Script execution timeout after ${executionTimeout.inSeconds}s'),
        );
      }
    });

    _totalExecutionTime.start();

    try {
      // Memory check (platform-dependent)
      int? memoryBefore;
      if (Platform.isAndroid || Platform.isLinux) {
        memoryBefore = await _getProcessMemory();
      }

      // Execute with network proxy
      final result = await _executeWithNetworkProxy<T>(operation, args);

      // Memory check after
      if (memoryBefore != null) {
        final memoryAfter = await _getProcessMemory();
        final memoryDelta = (memoryAfter! - memoryBefore) ~/ (1024 * 1024);
        
        if (memoryDelta > MAX_MEMORY_MB) {
          _addWarning(
            SecurityWarningLevel.warning,
            'High memory usage: ${memoryDelta}MB allocated',
          );
        }
      }

      _executionTimer?.cancel();
      _totalExecutionTime.stop();
      
      _updateSecurityStatus();
      
      if (!completer.isCompleted) {
        completer.complete(result);
      }
      
      return completer.future;
    } catch (e) {
      _executionTimer?.cancel();
      _totalExecutionTime.stop();
      
      if (e is SecurityException) {
        _addWarning(
          SecurityWarningLevel.critical,
          'Security violation: ${e.message}',
        );
      }
      
      _updateSecurityStatus();
      
      if (!completer.isCompleted) {
        completer.completeError(e);
      }
      
      return completer.future;
    }
  }

  Future<T> _executeWithNetworkProxy<T>(
    String operation,
    Map<String, dynamic> args,
  ) async {
    // Intercept network requests and route through proxy
    final modifiedArgs = Map<String, dynamic>.from(args);
    
    // If the operation involves fetching, wrap the URL
    if (operation == 'fetch' || operation == 'request') {
      final url = args['url'] as String?;
      if (url != null) {
        try {
          final response = await _networkProxy.fetch(url, sourceId);
          
          // Track accessed domain
          final uri = Uri.parse(url);
          _accessedDomains.add(uri.host);
          
          // Return response data
          return response.data as T;
        } on SecurityException catch (e) {
          _addWarning(
            SecurityWarningLevel.critical,
            'Network request blocked: ${e.message}',
          );
          rethrow;
        }
      }
    }
    
    // Execute the actual operation
    return await _baseEngine.execute<T>(operation, modifiedArgs);
  }

  Future<int?> _getProcessMemory() async {
    if (Platform.isLinux) {
      try {
        final result = await Process.run('cat', ['/proc/self/status']);
        final lines = (result.stdout as String).split('\n');
        for (final line in lines) {
          if (line.startsWith('VmRSS:')) {
            final parts = line.split(RegExp(r'\s+'));
            if (parts.length >= 2) {
              return int.tryParse(parts[1]);
            }
          }
        }
      } catch (e) {
        debugPrint('Failed to get memory usage: $e');
      }
    } else if (Platform.isAndroid) {
      // Android memory tracking is more complex
      // Would need to use android_intent or platform channels
      return null;
    }
    return null;
  }

  void _addWarning(SecurityWarningLevel level, String message) {
    _warnings.add(SecurityWarning(
      level: level,
      message: message,
    ));
    
    // Keep only recent warnings (last 50)
    if (_warnings.length > 50) {
      _warnings.removeAt(0);
    }
  }

  void _updateSecurityStatus() {
    final networkStats = _networkProxy.getStats(sourceId);
    
    _securityStatus.value = SourceSecurityStatus(
      sourceId: sourceId,
      networkRequestCount: networkStats['totalRequests'] as int,
      accessedDomains: _accessedDomains.toList(),
      totalExecutionTime: _totalExecutionTime.elapsed,
      warnings: List.from(_warnings),
      networkStats: networkStats,
    );
  }

  /// Clear security status (for testing or reset).
  void clearStatus() {
    _warnings.clear();
    _accessedDomains.clear();
    _totalExecutionTime.reset();
    _networkProxy.clearRateLimit(sourceId);
    _updateSecurityStatus();
  }

  /// Export security audit log.
  List<Map<String, dynamic>> exportAuditLog() {
    return _networkProxy.exportAuditLog(sourceId: sourceId);
  }

  void dispose() {
    _executionTimer?.cancel();
    _securityStatus.dispose();
  }
}

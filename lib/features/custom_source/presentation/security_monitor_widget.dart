// Copyright 2024 Koyze Contributors
// Licensed under the Apache License, Version 2.0

/// Security monitoring widget for custom sources.
/// 
/// Displays real-time security metrics:
/// - Network request count
/// - Accessed domains
/// - Execution time
/// - Security warnings

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/source_network_proxy.dart';

enum SecurityWarningLevel { info, warning, critical }

class SecurityWarning {
  final SecurityWarningLevel level;
  final String message;
  final DateTime timestamp;

  SecurityWarning({
    required this.level,
    required this.message,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

class SourceSecurityStatus {
  final String sourceId;
  final int networkRequestCount;
  final List<String> accessedDomains;
  final Duration totalExecutionTime;
  final List<SecurityWarning> warnings;
  final Map<String, dynamic>? networkStats;

  SourceSecurityStatus({
    required this.sourceId,
    this.networkRequestCount = 0,
    this.accessedDomains = const [],
    this.totalExecutionTime = Duration.zero,
    this.warnings = const [],
    this.networkStats,
  });

  SourceSecurityStatus copyWith({
    int? networkRequestCount,
    List<String>? accessedDomains,
    Duration? totalExecutionTime,
    List<SecurityWarning>? warnings,
    Map<String, dynamic>? networkStats,
  }) {
    return SourceSecurityStatus(
      sourceId: sourceId,
      networkRequestCount: networkRequestCount ?? this.networkRequestCount,
      accessedDomains: accessedDomains ?? this.accessedDomains,
      totalExecutionTime: totalExecutionTime ?? this.totalExecutionTime,
      warnings: warnings ?? this.warnings,
      networkStats: networkStats ?? this.networkStats,
    );
  }

  bool get hasWarnings => warnings.isNotEmpty;
  bool get hasCriticalWarnings =>
      warnings.any((w) => w.level == SecurityWarningLevel.critical);
}

class SourceSecurityMonitor extends ConsumerWidget {
  final String sourceId;
  final SourceSecurityStatus status;

  const SourceSecurityMonitor({
    super.key,
    required this.sourceId,
    required this.status,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  status.hasCriticalWarnings
                      ? Icons.error
                      : status.hasWarnings
                          ? Icons.warning
                          : Icons.security,
                  color: _getStatusColor(context),
                ),
                const SizedBox(width: 8),
                Text(
                  '安全状态监控',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildMetricRow(
              context,
              icon: Icons.network_check,
              label: '网络请求',
              value: '${status.networkRequestCount} 次',
              detail: status.networkStats != null
                  ? '成功 ${status.networkStats!['successfulRequests']} / 失败 ${status.networkStats!['failedRequests']}'
                  : null,
            ),
            const SizedBox(height: 8),
            _buildMetricRow(
              context,
              icon: Icons.language,
              label: '访问域名',
              value: '${status.accessedDomains.length} 个',
              detail: status.accessedDomains.isNotEmpty
                  ? status.accessedDomains.take(3).join(', ') +
                      (status.accessedDomains.length > 3
                          ? ' +${status.accessedDomains.length - 3}'
                          : '')
                  : null,
            ),
            const SizedBox(height: 8),
            _buildMetricRow(
              context,
              icon: Icons.timer,
              label: '累计执行时间',
              value: _formatDuration(status.totalExecutionTime),
              detail: status.networkStats != null
                  ? '平均响应 ${status.networkStats!['avgDurationMs']}ms'
                  : null,
            ),
            if (status.networkStats != null) ...[
              const SizedBox(height: 8),
              _buildMetricRow(
                context,
                icon: Icons.speed,
                label: '速率限制剩余',
                value:
                    '${status.networkStats!['rateLimitRemaining']}/30 次/分钟',
                detail: status.networkStats!['rateLimitRemaining'] < 5
                    ? '接近限制'
                    : null,
                warningLevel: status.networkStats!['rateLimitRemaining'] < 5
                    ? SecurityWarningLevel.warning
                    : null,
              ),
            ],
            if (status.warnings.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              Text(
                '⚠️ 安全警告',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: Colors.orange,
                    ),
              ),
              const SizedBox(height: 8),
              ...status.warnings.map((warning) => _buildWarning(context, warning)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMetricRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    String? detail,
    SecurityWarningLevel? warningLevel,
  }) {
    Color? valueColor;
    if (warningLevel == SecurityWarningLevel.critical) {
      valueColor = Colors.red;
    } else if (warningLevel == SecurityWarningLevel.warning) {
      valueColor = Colors.orange;
    }

    return Row(
      children: [
        Icon(icon, size: 20, color: Theme.of(context).textTheme.bodySmall?.color),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (detail != null)
                Text(
                  detail,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.color
                            ?.withOpacity(0.7),
                        fontSize: 11,
                      ),
                ),
            ],
          ),
        ),
        Text(
          value,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: valueColor,
              ),
        ),
      ],
    );
  }

  Widget _buildWarning(BuildContext context, SecurityWarning warning) {
    IconData icon;
    Color color;

    switch (warning.level) {
      case SecurityWarningLevel.critical:
        icon = Icons.error;
        color = Colors.red;
        break;
      case SecurityWarningLevel.warning:
        icon = Icons.warning;
        color = Colors.orange;
        break;
      case SecurityWarningLevel.info:
        icon = Icons.info;
        color = Colors.blue;
        break;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              warning.message,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(BuildContext context) {
    if (status.hasCriticalWarnings) {
      return Colors.red;
    } else if (status.hasWarnings) {
      return Colors.orange;
    }
    return Colors.green;
  }

  String _formatDuration(Duration duration) {
    if (duration.inHours > 0) {
      return '${duration.inHours}小时${duration.inMinutes.remainder(60)}分钟';
    } else if (duration.inMinutes > 0) {
      return '${duration.inMinutes}分钟${duration.inSeconds.remainder(60)}秒';
    } else {
      return '${duration.inSeconds}秒';
    }
  }
}

/// Compact security indicator for list views
class CompactSecurityIndicator extends StatelessWidget {
  final SourceSecurityStatus status;

  const CompactSecurityIndicator({
    super.key,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _getStatusColor().withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _getStatusColor().withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            status.hasCriticalWarnings
                ? Icons.error
                : status.hasWarnings
                    ? Icons.warning
                    : Icons.check_circle,
            size: 14,
            color: _getStatusColor(),
          ),
          const SizedBox(width: 4),
          Text(
            '${status.networkRequestCount} 请求',
            style: TextStyle(
              fontSize: 12,
              color: _getStatusColor(),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor() {
    if (status.hasCriticalWarnings) {
      return Colors.red;
    } else if (status.hasWarnings) {
      return Colors.orange;
    }
    return Colors.green;
  }
}

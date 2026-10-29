// Copyright 2024 Koyze Contributors
// Licensed under the Apache License, Version 2.0

import 'dart:convert';

import 'package:flutter/foundation.dart';

/// 一个 OpenAI 兼容接口的连接配置。
///
/// 只存地址和模型名；密钥走安全存储，绝不跟配置一起落盘或进备份。
@immutable
class AiConfig {
  const AiConfig({
    this.baseUrl = '',
    this.model = '',
    this.toolsEnabled = true,
    this.allowActions = true,
  });

  /// 用户填的地址，允许是 `https://api.deepseek.com`、
  /// `https://api.deepseek.com/v1` 或完整的 `.../chat/completions`。
  final String baseUrl;
  final String model;

  /// 是否允许模型调用应用内的工具（搜曲库、读歌单、查音源）。
  final bool toolsEnabled;

  /// 是否允许工具执行会改变状态的操作：播放、建歌单、收藏、下载、删除等。
  /// 默认打开——助手的意义就是替你把事做完；只想让它查资料时再关掉。
  final bool allowActions;

  static const AiConfig empty = AiConfig();

  bool get isConfigured => baseUrl.trim().isNotEmpty && model.trim().isNotEmpty;

  /// 补全成可直接 POST 的地址。
  String get endpoint {
    var base = normalizeBaseUrl(baseUrl);
    if (base.isEmpty) return '';
    if (base.endsWith('/chat/completions')) return base;
    return '$base/chat/completions';
  }

  AiConfig copyWith({
    String? baseUrl,
    String? model,
    bool? toolsEnabled,
    bool? allowActions,
  }) => AiConfig(
    baseUrl: baseUrl ?? this.baseUrl,
    model: model ?? this.model,
    toolsEnabled: toolsEnabled ?? this.toolsEnabled,
    allowActions: allowActions ?? this.allowActions,
  );

  static String normalizeBaseUrl(String raw) {
    var value = raw.trim();
    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }

  /// 返回 null 表示可用，否则返回错误原因（由界面翻译成文案）。
  AiConfigProblem? validate() {
    final url = normalizeBaseUrl(baseUrl);
    if (url.isEmpty) return AiConfigProblem.missingBaseUrl;
    final parsed = Uri.tryParse(url);
    if (parsed == null ||
        !parsed.hasAuthority ||
        (parsed.scheme != 'https' && parsed.scheme != 'http')) {
      return AiConfigProblem.invalidBaseUrl;
    }
    if (model.trim().isEmpty) return AiConfigProblem.missingModel;
    return null;
  }

  /// 默认值不落盘，老配置文件读回来也不会因为缺字段而改变行为。
  Map<String, dynamic> toJson() => {
    'baseUrl': normalizeBaseUrl(baseUrl),
    'model': model.trim(),
    if (!toolsEnabled) 'toolsEnabled': false,
    if (!allowActions) 'allowActions': false,
  };

  factory AiConfig.fromJson(Map<String, dynamic> json) => AiConfig(
    baseUrl: json['baseUrl']?.toString() ?? '',
    model: json['model']?.toString() ?? '',
    toolsEnabled: json['toolsEnabled'] != false,
    // 旧版本存的是 allowWrites（默认关），读回来一并当成执行权限。
    allowActions: json['allowActions'] ?? json['allowWrites'] ?? true,
  );

  @override
  bool operator ==(Object other) =>
      other is AiConfig &&
      other.baseUrl == baseUrl &&
      other.model == model &&
      other.toolsEnabled == toolsEnabled &&
      other.allowActions == allowActions;

  @override
  int get hashCode => Object.hash(baseUrl, model, toolsEnabled, allowActions);
}

enum AiConfigProblem { missingBaseUrl, invalidBaseUrl, missingModel }

enum AiRole { system, user, assistant, tool }

/// 模型请求调用某个工具。字段名对齐 OpenAI 的 `message.tool_calls[]`。
@immutable
class AiToolCall {
  const AiToolCall({
    required this.id,
    required this.name,
    this.arguments = const <String, dynamic>{},
    this.rawArguments = '',
  });

  final String id;
  final String name;
  final Map<String, dynamic> arguments;

  /// 模型原始给的参数串，回传给接口时原样发回去最稳（有些网关会校验格式）。
  final String rawArguments;

  Map<String, dynamic> toRequestJson() => {
    'id': id,
    'type': 'function',
    'function': {
      'name': name,
      'arguments': rawArguments.isEmpty ? jsonEncode(arguments) : rawArguments,
    },
  };
}

@immutable
class AiMessage {
  const AiMessage(
    this.role,
    this.content, {
    this.toolCalls = const <AiToolCall>[],
    this.toolCallId,
  });

  /// 工具执行结果：回填给模型看的那条消息。
  const AiMessage.tool(this.content, {required this.toolCallId})
    : role = AiRole.tool,
      toolCalls = const <AiToolCall>[];

  final AiRole role;
  final String content;

  /// assistant 消息里带回的调用请求，要和下一轮 tool 消息配对。
  final List<AiToolCall> toolCalls;

  /// tool 消息指向它回答的是哪一次调用。
  final String? toolCallId;

  Map<String, dynamic> toJson() {
    return {
      'role': role.name,
      'content': content,
      if (toolCalls.isNotEmpty)
        'tool_calls': [for (final call in toolCalls) call.toRequestJson()],
      if (toolCallId != null) 'tool_call_id': toolCallId,
    };
  }
}

/// 请求失败的分类，界面按类别给不同提示，不用把后端原文直接抛给用户。
enum AiFailureKind {
  notConfigured,
  unauthorized,
  notFound,
  rateLimited,
  serverError,
  timeout,
  emptyResponse,
  badResponse,
  network,

  /// 请求超过了模型的上下文长度（对话太长或工具结果太大）。可以靠清空对话解决。
  contextTooLong,

  /// 该接口不认 `tools` 字段。关掉执行权限后仍可聊天。
  toolsUnsupported,

  /// 接口明确拒绝了这次请求，[AiException.detail] 里有它的原话。
  rejected,

  /// 网关（502 / 503 / 504）没能等到模型回话。多数是上游瞬时过载，重试即可。
  gatewayTimeout,

  /// 模型连着调用工具到上限还没给出结论。
  toolLoop,
}

class AiException implements Exception {
  const AiException(this.kind, [this.detail = '']);

  final AiFailureKind kind;
  final String detail;

  @override
  String toString() => detail.isEmpty
      ? 'AiException(${kind.name})'
      : 'AiException(${kind.name}): $detail';
}

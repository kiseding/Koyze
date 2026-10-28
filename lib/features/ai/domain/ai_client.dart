// Copyright 2024 Koyze Contributors
// Licensed under the Apache License, Version 2.0

import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../../core/network/app_http_client.dart';
import 'ai_config.dart';

/// 一次对话的原始结果：既有正文，也可能带着工具调用请求。
@immutable
class AiCompletion {
  const AiCompletion({this.content = '', this.toolCalls = const []});

  final String content;
  final List<AiToolCall> toolCalls;

  bool get hasToolCalls => toolCalls.isNotEmpty;
}

/// OpenAI 兼容的 chat/completions 客户端。
///
/// 只依赖「POST /chat/completions + Bearer」这一条最小公约数，所以 DeepSeek、
/// 通义、Kimi、自建 one-api 之类的网关都能直接填进来。
class AiClient {
  AiClient({Dio? dio}) : _dio = dio ?? AppHttpClient.create();

  final Dio _dio;

  Future<String> complete({
    required AiConfig config,
    required String apiKey,
    required List<AiMessage> messages,
    double temperature = 0.7,
    int maxTokens = 2048,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final result = await completeDetailed(
      config: config,
      apiKey: apiKey,
      messages: messages,
      temperature: temperature,
      maxTokens: maxTokens,
      timeout: timeout,
    );
    if (result.content.trim().isEmpty) {
      throw const AiException(AiFailureKind.emptyResponse);
    }
    return result.content;
  }

  /// 和 [complete] 走同一条链路，但把工具调用一起解析出来。
  ///
  /// [tools] 非空时请求里带上 `tools` 与 `tool_choice: auto`；没传就和以前的报文
  /// 完全一致，避免给不支持工具的老网关塞未知字段。
  Future<AiCompletion> completeDetailed({
    required AiConfig config,
    required String apiKey,
    required List<AiMessage> messages,
    List<Map<String, dynamic>> tools = const [],
    double temperature = 0.7,
    int maxTokens = 2048,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    if (!config.isConfigured) {
      throw const AiException(AiFailureKind.notConfigured);
    }
    if (apiKey.trim().isEmpty) {
      throw const AiException(AiFailureKind.unauthorized);
    }

    final Response<dynamic> response;
    try {
      response = await _dio.post<dynamic>(
        config.endpoint,
        data: {
          'model': config.model,
          'messages': messages.map((message) => message.toJson()).toList(),
          'temperature': temperature,
          'max_tokens': maxTokens,
          'stream': false,
          if (tools.isNotEmpty) 'tools': tools,
          if (tools.isNotEmpty) 'tool_choice': 'auto',
        },
        options: Options(
          headers: {
            'Authorization': 'Bearer ${apiKey.trim()}',
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          sendTimeout: timeout,
          receiveTimeout: timeout,
          validateStatus: (_) => true,
        ),
      );
    } on DioException catch (error) {
      throw AiException(
        _kindOfDioException(error),
        error.message ?? error.type.name,
      );
    }

    final status = response.statusCode ?? 0;
    if (status == 401 || status == 403) {
      throw const AiException(AiFailureKind.unauthorized);
    }
    if (status == 404) {
      throw const AiException(AiFailureKind.notFound);
    }
    if (status == 429) {
      throw const AiException(AiFailureKind.rateLimited);
    }
    if (status >= 500) {
      throw AiException(
        AiFailureKind.serverError,
        _errorMessage(response.data),
      );
    }
    if (status >= 400) {
      throw AiException(
        AiFailureKind.badResponse,
        _errorMessage(response.data),
      );
    }

    return AiCompletion(
      content: _contentOf(response.data) ?? '',
      toolCalls: _toolCallsOf(response.data),
    );
  }

  static AiFailureKind _kindOfDioException(DioException error) {
    return switch (error.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout => AiFailureKind.timeout,
      DioExceptionType.badResponse =>
        (error.response?.statusCode ?? 0) >= 500
            ? AiFailureKind.serverError
            : AiFailureKind.badResponse,
      _ => AiFailureKind.network,
    };
  }

  /// `choices[0].message.content`，兼容把 content 拆成多段 text 的实现。
  static String? _contentOf(dynamic data) {
    final message = _messageOf(data);
    if (message == null) return null;
    final content = message['content'];
    if (content is String) return content;
    if (content is List) {
      final buffer = StringBuffer();
      for (final part in content) {
        if (part is Map && part['text'] is String) {
          buffer.write(part['text']);
        } else if (part is String) {
          buffer.write(part);
        }
      }
      return buffer.isEmpty ? null : buffer.toString();
    }
    return null;
  }

  static Map<dynamic, dynamic>? _messageOf(dynamic data) {
    if (data is! Map) return null;
    final choices = data['choices'];
    if (choices is! List || choices.isEmpty) return null;
    final first = choices.first;
    if (first is! Map) return null;
    final message = first['message'] ?? first['delta'];
    return message is Map ? message : null;
  }

  /// 解析 `message.tool_calls[]`。参数是 JSON 字符串，模型偶尔给半截，
  /// 解析不出来就当空参数——让工具自己报「缺少参数」，而不是整轮对话失败。
  static List<AiToolCall> _toolCallsOf(dynamic data) {
    final message = _messageOf(data);
    final raw = message?['tool_calls'];
    if (raw is! List) return const [];
    final calls = <AiToolCall>[];
    for (var index = 0; index < raw.length; index++) {
      final item = raw[index];
      if (item is! Map) continue;
      final function = item['function'];
      if (function is! Map) continue;
      final name = function['name']?.toString().trim() ?? '';
      if (name.isEmpty) continue;

      final rawArguments = function['arguments'];
      Map<String, dynamic> arguments = const {};
      var argumentText = '';
      if (rawArguments is Map) {
        arguments = Map<String, dynamic>.from(rawArguments);
        argumentText = jsonEncode(rawArguments);
      } else if (rawArguments is String) {
        argumentText = rawArguments;
        arguments = _decodeArguments(rawArguments);
      }

      calls.add(
        AiToolCall(
          id: item['id']?.toString() ?? 'call_$index',
          name: name,
          arguments: arguments,
          rawArguments: argumentText,
        ),
      );
    }
    return calls;
  }

  static Map<String, dynamic> _decodeArguments(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return const {};
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } on FormatException {
      // 忽略：按空参数处理。
    }
    return const {};
  }

  static String _errorMessage(dynamic data) {
    if (data is Map) {
      final error = data['error'];
      if (error is Map && error['message'] is String) {
        return error['message'] as String;
      }
      if (data['message'] is String) return data['message'] as String;
    }
    if (data is String) return data;
    return '';
  }
}

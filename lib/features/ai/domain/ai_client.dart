// Copyright 2024 Koyze Contributors
// Licensed under the Apache License, Version 2.0

import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../../core/logging/app_log.dart';
import '../../../core/network/app_http_client.dart';
import 'ai_config.dart';
import 'voice_probe.dart';

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
      response = await _post(
        config.endpoint,
        apiKey,
        {
          'model': config.model,
          'messages': messages.map((message) => message.toJson()).toList(),
          'temperature': temperature,
          'max_tokens': maxTokens,
          'stream': false,
          if (tools.isNotEmpty) 'tools': tools,
          if (tools.isNotEmpty) 'tool_choice': 'auto',
        },
        timeout,
      );
    } on DioException catch (error) {
      final detail = _readable(error.response?.data);
      throw AiException(
        _kindOfDioException(error),
        detail.isEmpty ? (error.message ?? error.type.name) : detail,
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
    if (status >= 400) {
      final detail = _errorMessage(response.data);
      // 4xx 的原因千差万别（上下文超长、接口不认 tools、参数校验失败），
      // 光看状态码分不出来，原文必须留在日志里，否则只能看到一句「无法解析」。
      AppLog.instance.record(
        'ai.http',
        'POST ${config.endpoint} -> $status ${detail.isEmpty ? '(no message)' : detail}',
        level: AppLogLevel.warning,
      );
      if (status >= 500) {
        throw AiException(_kindOfServerError(status), detail);
      }
      throw AiException(_kindOfClientError(detail), detail);
    }

    return AiCompletion(
      content: _contentOf(response.data) ?? '',
      toolCalls: _toolCallsOf(response.data),
    );
  }

  /// 探测这个接口到底有没有把 `input_audio` 交给模型。
  ///
  /// 发一段合成的方波，问模型听没听见声音：真的收到了就说「听见了」，被网关
  /// 丢掉、只剩文字时只能凭文字猜「没收到音频」。这样用户不用再从一句含糊的
  /// 回复里猜是模型不行还是自己没开麦克风。
  ///
  /// 返回 true 表示音频确实到了模型手里；false 表示被丢了。接口明确拒绝
  /// `input_audio` 时抛 [AiFailureKind.audioUnsupported]，其余错误照常抛。
  Future<bool> probeAudio({
    required AiConfig config,
    required String apiKey,
    Duration timeout = const Duration(seconds: 40),
  }) async {
    final completion = await completeDetailed(
      config: config,
      apiKey: apiKey,
      messages: [
        AiMessage(
          AiRole.user,
          '这是测试。这条消息里附了一段音频，内容是三声短促的“嘟”。'
          '如果你真的收到了音频并能听到它，只回答「听见了」三个字；'
          '如果没收到音频、只是看到这段文字，只回答「没有音频」。',
          voice: AiVoiceAttachment(base64Data: buildProbeWavBase64()),
        ),
      ],
      temperature: 0,
      maxTokens: 24,
      timeout: timeout,
    );
    final reply = completion.content;
    // 正向信号优先：模型描述了声音（嘟/响/三声）就说明它真听到了，
    // 哪怕它没按格式只说「听见了」。
    const heard = ['听见', '听到', '听到了', '嘟', '响', 'beep', 'tone'];
    const missing = ['没有音频', '没收到', '没有收到', '无法听到', 'no audio'];
    final lower = reply.toLowerCase();
    if (missing.any(lower.contains) &&
        !heard.any((word) => lower.contains(word))) {
      return false;
    }
    return heard.any((word) => lower.contains(word));
  }

  /// 重试次数与间隔。网关 502/504 多半是上游瞬时过载，重发一次通常就好了；
  /// 4xx 一律不重发，免得把同一个无效请求交两遍。
  static const int _attempts = 2;
  static const Duration _retryDelay = Duration(milliseconds: 800);

  Future<Response<dynamic>> _post(
    String endpoint,
    String apiKey,
    Map<String, dynamic> data,
    Duration timeout,
  ) async {
    final options = Options(
      headers: {
        'Authorization': 'Bearer ${apiKey.trim()}',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      sendTimeout: timeout,
      receiveTimeout: timeout,
      validateStatus: (_) => true,
    );

    for (var attempt = 1; ; attempt++) {
      try {
        final response = await _dio.post<dynamic>(
          endpoint,
          data: data,
          options: options,
        );
        final status = response.statusCode ?? 0;
        if (status >= 500 && status != 501 && attempt < _attempts) {
          await Future<void>.delayed(_retryDelay);
          continue;
        }
        return response;
      } on DioException catch (error) {
        if (attempt >= _attempts || !_worthRetrying(error)) rethrow;
        // 已经等到超时的（receiveTimeout / sendTimeout）不重来一次，
        // 否则用户要干等两倍时间才看到报错。
        await Future<void>.delayed(_retryDelay);
      }
    }
  }

  static bool _worthRetrying(DioException error) => switch (error.type) {
    DioExceptionType.connectionTimeout ||
    DioExceptionType.connectionError => true,
    DioExceptionType.badResponse => (error.response?.statusCode ?? 0) >= 500,
    _ => false,
  };

  /// 4xx 里最常见的两类原因单独拎出来：它们都有明确解法，
  /// 混在「返回内容无法解析」里用户没法自救。
  static AiFailureKind _kindOfClientError(String detail) {
    final text = detail.toLowerCase();
    if (text.isEmpty) return AiFailureKind.badResponse;
    final overContext =
        text.contains('context_length') ||
        text.contains('context length') ||
        text.contains('maximum context') ||
        text.contains('too many tokens') ||
        text.contains('prompt is too long') ||
        text.contains('reduce the length') ||
        text.contains('exceeds the maximum') ||
        (text.contains('token') &&
            (text.contains('exceed') || text.contains('too long')));
    if (overContext) return AiFailureKind.contextTooLong;
    // 语音消息最常踩的两类：模型根本不听音频，或者模型名不认这个模态。
    // 它们都有明确解法（换模型），不能混进「接口拒绝了这次请求」。
    final audioComplaint =
        text.contains('input_audio') ||
        (text.contains('audio') &&
            (text.contains('not support') ||
                text.contains('unsupported') ||
                text.contains('does not support') ||
                text.contains('invalid') ||
                text.contains('unknown variant') ||
                text.contains('modality') ||
                text.contains('not allowed')));
    if (audioComplaint) return AiFailureKind.audioUnsupported;
    final toolComplaint =
        text.contains('tool') &&
        (text.contains('not support') ||
            text.contains('unsupported') ||
            text.contains('does not support') ||
            text.contains('unknown field') ||
            text.contains('unknown parameter'));
    if (toolComplaint) return AiFailureKind.toolsUnsupported;
    return AiFailureKind.rejected;
  }

  static AiFailureKind _kindOfDioException(DioException error) {
    final status = error.response?.statusCode ?? 0;
    return switch (error.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout => AiFailureKind.timeout,
      DioExceptionType.badResponse => status >= 500
          ? _kindOfServerError(status)
          : AiFailureKind.badResponse,
      // 有些网关声明 json 却回了一整页 HTML，Dio 解析失败会落到 unknown。
      // 只要拿到了响应，就还是按状态码判，别报成「网络错误」。
      DioExceptionType.unknown when error.response != null =>
        status >= 500 ? _kindOfServerError(status) : AiFailureKind.badResponse,
      _ => AiFailureKind.network,
    };
  }

  static AiFailureKind _kindOfServerError(int status) =>
      status == 502 || status == 503 || status == 504
      ? AiFailureKind.gatewayTimeout
      : AiFailureKind.serverError;

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
        return _readable(error['message']);
      }
      if (data['message'] is String) return _readable(data['message']);
      return '';
    }
    return _readable(data);
  }

  /// 网关挂掉时常直接吐一整页 HTML（nginx 的 502 / 504 页面就是这样）。
  /// 把 `<html><head>...` 原样贴在气泡里既看不懂也没意义，这里只留标题。
  static String _readable(Object? raw) {
    if (raw is! String) return '';
    var text = raw.trim();
    if (text.isEmpty) return '';
    if (text.startsWith('<')) {
      final title = RegExp(
        r'<title[^>]*>([^<]*)</title>',
        caseSensitive: false,
      ).firstMatch(text)?.group(1);
      if (title != null && title.trim().isNotEmpty) return title.trim();
      text = text.replaceAll(RegExp(r'<[^>]+>'), ' ');
    }
    text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return text.length <= 200 ? text : '${text.substring(0, 200)}…';
  }
}

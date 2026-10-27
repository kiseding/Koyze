// Copyright 2024 Koyze Contributors
// Licensed under the Apache License, Version 2.0

import 'dart:async';

import 'package:dio/dio.dart';

import '../../../core/network/app_http_client.dart';
import 'ai_config.dart';

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
      throw AiException(AiFailureKind.serverError, _errorMessage(response.data));
    }
    if (status >= 400) {
      throw AiException(AiFailureKind.badResponse, _errorMessage(response.data));
    }

    final content = _contentOf(response.data);
    if (content == null || content.trim().isEmpty) {
      throw const AiException(AiFailureKind.emptyResponse);
    }
    return content;
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
    if (data is! Map) return null;
    final choices = data['choices'];
    if (choices is! List || choices.isEmpty) return null;
    final first = choices.first;
    if (first is! Map) return null;
    final message = first['message'] ?? first['delta'];
    if (message is! Map) return null;
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

// Copyright 2024 Koyze Contributors
// Licensed under the Apache License, Version 2.0

import 'package:flutter/foundation.dart';

/// 一个 OpenAI 兼容接口的连接配置。
///
/// 只存地址和模型名；密钥走安全存储，绝不跟配置一起落盘或进备份。
@immutable
class AiConfig {
  const AiConfig({this.baseUrl = '', this.model = ''});

  /// 用户填的地址，允许是 `https://api.deepseek.com`、
  /// `https://api.deepseek.com/v1` 或完整的 `.../chat/completions`。
  final String baseUrl;
  final String model;

  static const AiConfig empty = AiConfig();

  bool get isConfigured => baseUrl.trim().isNotEmpty && model.trim().isNotEmpty;

  /// 补全成可直接 POST 的地址。
  String get endpoint {
    var base = normalizeBaseUrl(baseUrl);
    if (base.isEmpty) return '';
    if (base.endsWith('/chat/completions')) return base;
    return '$base/chat/completions';
  }

  AiConfig copyWith({String? baseUrl, String? model}) =>
      AiConfig(baseUrl: baseUrl ?? this.baseUrl, model: model ?? this.model);

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

  Map<String, dynamic> toJson() => {
    'baseUrl': normalizeBaseUrl(baseUrl),
    'model': model.trim(),
  };

  factory AiConfig.fromJson(Map<String, dynamic> json) => AiConfig(
    baseUrl: json['baseUrl']?.toString() ?? '',
    model: json['model']?.toString() ?? '',
  );

  @override
  bool operator ==(Object other) =>
      other is AiConfig &&
      other.baseUrl == baseUrl &&
      other.model == model;

  @override
  int get hashCode => Object.hash(baseUrl, model);
}

enum AiConfigProblem { missingBaseUrl, invalidBaseUrl, missingModel }

enum AiRole { system, user, assistant }

@immutable
class AiMessage {
  const AiMessage(this.role, this.content);

  final AiRole role;
  final String content;

  Map<String, dynamic> toJson() => {'role': role.name, 'content': content};
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
}

class AiException implements Exception {
  const AiException(this.kind, [this.detail = '']);

  final AiFailureKind kind;
  final String detail;

  @override
  String toString() =>
      detail.isEmpty ? 'AiException(${kind.name})' : 'AiException(${kind.name}): $detail';
}

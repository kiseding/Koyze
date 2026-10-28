// Copyright 2024 Koyze Contributors
// Licensed under the Apache License, Version 2.0

import '../../../l10n/app_strings.dart';
import '../domain/ai_config.dart';

/// 把请求失败的类型翻译成一句能看懂的提示。
String aiFailureText(S s, AiFailureKind kind) => switch (kind) {
  AiFailureKind.notConfigured => s.aiErrorNotConfigured,
  AiFailureKind.unauthorized => s.aiErrorUnauthorized,
  AiFailureKind.notFound => s.aiErrorNotFound,
  AiFailureKind.rateLimited => s.aiErrorRateLimited,
  AiFailureKind.serverError => s.aiErrorServer,
  AiFailureKind.timeout => s.aiErrorTimeout,
  AiFailureKind.emptyResponse => s.aiErrorEmpty,
  AiFailureKind.badResponse => s.aiErrorBadResponse,
  AiFailureKind.network => s.aiErrorNetwork,
  AiFailureKind.contextTooLong => s.aiErrorContextTooLong,
  AiFailureKind.toolsUnsupported => s.aiErrorToolsUnsupported,
  AiFailureKind.rejected => s.aiErrorRejected,
  AiFailureKind.toolLoop => s.aiErrorToolLoop,
};

// Copyright 2024 Koyze Contributors
// Licensed under the Apache License, Version 2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_notification.dart';
import '../../../core/widgets/fx_icon_button.dart';
import '../../../core/widgets/fx_switch.dart';
import '../../../core/widgets/gradient_bar_backgrounds.dart';
import '../../../l10n/app_strings.dart';
import '../domain/ai_config.dart';
import 'ai_failure_text.dart';
import 'ai_provider.dart';

/// AI 服务配置：地址、密钥、模型。
///
/// 只有地址和模型名落盘；密钥写进系统安全存储，按接口地址做命名空间隔离。
class AiSettingsScreen extends ConsumerStatefulWidget {
  const AiSettingsScreen({super.key});

  @override
  ConsumerState<AiSettingsScreen> createState() => _AiSettingsScreenState();
}

class _AiSettingsScreenState extends ConsumerState<AiSettingsScreen> {
  final _baseUrl = TextEditingController();
  final _apiKey = TextEditingController();
  final _model = TextEditingController();
  bool _hasStoredKey = false;
  bool _hydrated = false;
  bool _keyChecked = false;
  bool _busy = false;
  bool _testingVoice = false;
  bool _obscure = true;

  @override
  void dispose() {
    _baseUrl.dispose();
    _apiKey.dispose();
    _model.dispose();
    super.dispose();
  }

  void _hydrate(AiConfig config) {
    // 首次 build 时配置还没从磁盘读回来，状态是空的；不能拿空值当「已填过」，
    // 否则读回来之后输入框再也填不上。
    if (!_hydrated) {
      if (config.baseUrl.isEmpty && config.model.isEmpty) return;
      _hydrated = true;
      _baseUrl.text = config.baseUrl;
      _model.text = config.model;
    }
    _checkStoredKey(config);
  }

  /// 已保存过密钥时把提示语换成「留空即保留」。要等配置读回来才知道问哪个地址。
  void _checkStoredKey(AiConfig config) {
    if (_keyChecked || config.baseUrl.isEmpty) return;
    _keyChecked = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final key = await ref.read(aiConfigProvider.notifier).loadKey();
      if (!mounted) return;
      if (key != null && key.isNotEmpty) setState(() => _hasStoredKey = true);
    });
  }

  /// 带上开关状态：只改地址/模型时不能把工具调用的选择顺手重置掉。
  AiConfig get _config => ref
      .read(aiConfigProvider)
      .copyWith(baseUrl: _baseUrl.text, model: _model.text);

  Future<void> _save() async {
    final s = S.of(context);
    final config = _config;
    if (config.validate() != null) {
      showAppNotification(s.aiConfigInvalid, type: AppNotificationType.error);
      return;
    }
    setState(() => _busy = true);
    try {
      final notifier = ref.read(aiConfigProvider.notifier);
      final key = _apiKey.text.trim();
      if (key.isNotEmpty) {
        await notifier.saveKey(key, baseUrl: config.baseUrl);
      }
      await notifier.save(config);
      if (!mounted) return;
      showAppNotification(s.aiConfigSaved, type: AppNotificationType.success);
      Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 开关即时生效：用户改完不用再点保存，也不会因为忘了保存而看着没反应。
  Future<void> _applyFlags(
    AiConfig current, {
    bool? toolsEnabled,
    bool? allowActions,
  }) async {
    await ref
        .read(aiConfigProvider.notifier)
        .save(
          current.copyWith(
            toolsEnabled: toolsEnabled,
            allowActions: allowActions,
          ),
        );
  }

  Future<void> _test() async {
    final s = S.of(context);
    final config = _config;
    if (config.validate() != null) {
      showAppNotification(s.aiConfigInvalid, type: AppNotificationType.error);
      return;
    }
    setState(() => _busy = true);
    try {
      final notifier = ref.read(aiConfigProvider.notifier);
      final typed = _apiKey.text.trim();
      final key = typed.isNotEmpty
          ? typed
          : await notifier.loadKey(baseUrl: config.baseUrl);
      if (key == null || key.isEmpty) {
        if (!mounted) return;
        showAppNotification(
          s.aiErrorUnauthorized,
          type: AppNotificationType.error,
        );
        return;
      }
      await ref
          .read(aiClientProvider)
          .complete(
            config: config,
            apiKey: key,
            messages: const [AiMessage(AiRole.user, 'ping')],
            maxTokens: 8,
            temperature: 0,
            timeout: const Duration(seconds: 30),
          );
      if (!mounted) return;
      showAppNotification(s.aiTestOk, type: AppNotificationType.success);
    } on AiException catch (error) {
      if (!mounted) return;
      showAppNotification(
        aiFailureText(s, error.kind),
        type: AppNotificationType.error,
      );
    } catch (_) {
      if (!mounted) return;
      showAppNotification(s.aiErrorNetwork, type: AppNotificationType.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 单独测一次「这个接口听不听得见音频」。
  ///
  /// 连接测试只证明地址和密钥对，不能证明模型收得到 `input_audio`——很多网关
  /// 会把不认识的内容段静默丢掉，模型于是只能看到文字、回一句「没收到语音」。
  Future<void> _testVoice() async {
    final s = S.of(context);
    final config = _config;
    if (config.validate() != null) {
      showAppNotification(s.aiConfigInvalid, type: AppNotificationType.error);
      return;
    }
    setState(() => _testingVoice = true);
    try {
      final notifier = ref.read(aiConfigProvider.notifier);
      final typed = _apiKey.text.trim();
      final key = typed.isNotEmpty
          ? typed
          : await notifier.loadKey(baseUrl: config.baseUrl);
      if (key == null || key.isEmpty) {
        if (!mounted) return;
        showAppNotification(
          s.aiErrorUnauthorized,
          type: AppNotificationType.error,
        );
        return;
      }
      final heard = await ref
          .read(aiClientProvider)
          .probeAudio(config: config, apiKey: key);
      if (!mounted) return;
      showAppNotification(
        heard ? s.aiTestVoiceOk : s.aiTestVoiceDropped,
        type: heard ? AppNotificationType.success : AppNotificationType.error,
      );
    } on AiException catch (error) {
      if (!mounted) return;
      showAppNotification(
        aiFailureText(s, error.kind),
        type: AppNotificationType.error,
      );
    } catch (_) {
      if (!mounted) return;
      showAppNotification(s.aiErrorNetwork, type: AppNotificationType.error);
    } finally {
      if (mounted) setState(() => _testingVoice = false);
    }
  }

  Widget _buildToggle(
    BuildContext context, {
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool>? onChanged,
    bool enabled = true,
  }) {
    final onSurface = AppColors.onScaffold(context);
    final active = enabled && onChanged != null;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  color: active ? onSurface : onSurface.withValues(alpha: 0.45),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: AppColors.mutedText(context),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: FxSwitch(
            value: value,
            activeColor: AppColors.accentOf(context),
            inactiveTrackColor: AppColors.isDark(context)
                ? AppColors.surfaceVariant
                : AppColors.lightSurfaceVariant,
            onChanged: active ? onChanged : null,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final config = ref.watch(aiConfigProvider);
    _hydrate(config);

    final onSurface = AppColors.onScaffold(context);
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        flexibleSpace: GradientAppBarBackground(
          background: Theme.of(context).scaffoldBackgroundColor,
        ),
        leading: FxIconButton(
          tooltip: s.back,
          icon: Icon(Icons.arrow_back, color: onSurface),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          s.aiSettingsTitle,
          style: TextStyle(
            color: onSurface,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text(
            s.aiSettingsIntro,
            style: TextStyle(
              fontSize: 13,
              height: 1.5,
              color: onSurface.withValues(alpha: 0.65),
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _baseUrl,
            enabled: !_busy,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: s.aiBaseUrl,
              hintText: s.aiBaseUrlHint,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _model,
            enabled: !_busy,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: s.aiModel,
              hintText: s.aiModelHint,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _apiKey,
            enabled: !_busy,
            obscureText: _obscure,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: s.aiApiKey,
              hintText: _hasStoredKey ? s.aiApiKeyStoredHint : s.aiApiKeyHint,
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscure ? Icons.visibility_off : Icons.visibility,
                  size: 20,
                ),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            onChanged: (value) {
              final has = value.trim().isNotEmpty;
              if (has != _hasStoredKey) {
                // 输入框里有内容时提示语不再强调「已保存」，避免误以为要重填。
                setState(() => _hasStoredKey = _hasStoredKey && !has);
              }
            },
          ),
          const SizedBox(height: 18),
          _buildToggle(
            context,
            title: s.aiToolsTitle,
            subtitle: s.aiToolsSubtitle,
            value: config.toolsEnabled,
            onChanged: _busy
                ? null
                : (value) => _applyFlags(config, toolsEnabled: value),
          ),
          const SizedBox(height: 10),
          _buildToggle(
            context,
            title: s.aiActionsTitle,
            subtitle: s.aiActionsSubtitle,
            value: config.allowActions,
            enabled: config.toolsEnabled,
            onChanged: _busy
                ? null
                : (value) => _applyFlags(config, allowActions: value),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _test,
                  icon: const Icon(Icons.wifi_tethering, size: 18),
                  label: Text(_busy ? s.aiTesting : s.aiTestConnection),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _busy ? null : _save,
                  child: Text(s.save),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // 语音单独测：连接正常不代表这个模型听得见音频。很多网关会静默丢掉
          // input_audio，模型只看到文字，用户却以为是自己的录音没发出去。
          OutlinedButton.icon(
            onPressed: _busy || _testingVoice ? null : _testVoice,
            icon: _testingVoice
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.graphic_eq_rounded, size: 18),
            label: Text(_testingVoice ? s.aiTestingVoice : s.aiTestVoice),
          ),
          const SizedBox(height: 6),
          Text(
            s.aiTestVoiceHint,
            style: TextStyle(fontSize: 12, color: AppColors.mutedText(context)),
          ),
        ],
      ),
    );
  }
}

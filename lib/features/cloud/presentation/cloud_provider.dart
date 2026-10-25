import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/state/buildless_notifier.dart';
import '../domain/cloud_api_client.dart';

final cloudApiProvider = Provider<CloudApiClient>((ref) => CloudApiClient());

final cloudSessionProvider =
    NotifierProvider<CloudSessionNotifier, CloudSessionState>(
      CloudSessionNotifier.new,
    );

class CloudSessionState {
  final bool loaded;
  final bool loggedIn;
  final bool checking;
  final String? baseUrl;
  final String? username;
  final String? role;
  final String? error;

  const CloudSessionState({
    this.loaded = false,
    this.loggedIn = false,
    this.checking = false,
    this.baseUrl,
    this.username,
    this.role,
    this.error,
  });

  CloudSessionState copyWith({
    bool? loaded,
    bool? loggedIn,
    bool? checking,
    String? baseUrl,
    String? username,
    String? role,
    String? error,
  }) {
    return CloudSessionState(
      loaded: loaded ?? this.loaded,
      loggedIn: loggedIn ?? this.loggedIn,
      checking: checking ?? this.checking,
      baseUrl: baseUrl ?? this.baseUrl,
      username: username ?? this.username,
      role: role ?? this.role,
      error: error,
    );
  }
}

class CloudSessionNotifier extends BuildlessNotifier<CloudSessionState> {
  CloudSessionNotifier({CloudApiClient? api, this.autoRefresh = true})
    : _apiOverride = api,
      super(const CloudSessionState()) {
    // Direct instantiation (tests) has no provider to build, so the refresh
    // starts here; provider-hosted instances start it from [build].
    if (api != null) {
      _api = api;
      _refreshStarted = true;
      if (autoRefresh) unawaited(refresh());
    }
  }

  /// Whether a provider-hosted notifier restores the session on first read.
  final bool autoRefresh;
  final CloudApiClient? _apiOverride;
  CloudApiClient _api = CloudApiClient();
  bool _refreshStarted = false;
  int _generation = 0;

  @override
  CloudSessionState build() {
    _api = _apiOverride ?? ref.watch(cloudApiProvider);
    if (!_refreshStarted) {
      _refreshStarted = true;
      if (autoRefresh) unawaited(refresh());
    }
    return super.build();
  }

  bool _current(int generation) => generation == _generation;

  CloudSessionState _sessionState({String? error}) {
    return CloudSessionState(
      loaded: true,
      checking: false,
      loggedIn: _api.isLoggedIn,
      baseUrl: _api.baseUrl,
      username: _api.username,
      role: _api.role,
      error: error,
    );
  }

  Future<void> refresh() async {
    final generation = ++_generation;
    publish(value.copyWith(checking: true, error: null));
    try {
      await _api.load();
    } catch (error) {
      if (!_current(generation)) return;
      publish(
        value.copyWith(
          loaded: true,
          checking: false,
          error: '无法读取安全凭据: $error',
        ),
      );
      return;
    }
    if (!_current(generation)) return;

    final verifiedToken = _api.token;
    final verifiedRevision = _api.sessionRevision;
    CloudVerification verification;
    try {
      verification = _api.isLoggedIn
          ? await _api.verify()
          : CloudVerification.noSession;
    } on CloudSessionSafetyError catch (error) {
      publish(_sessionState(error: error.toString()));
      return;
    }
    if (!_current(generation)) return;

    if (verification == CloudVerification.unauthorized && _api.isLoggedIn) {
      if (!_current(generation)) return;
      try {
        await _api.clearSession(
          expectedToken: verifiedToken,
          expectedRevision: verifiedRevision,
        );
      } catch (_) {
        if (!_current(generation)) return;
        publish(_sessionState(error: '无法清除安全凭据'));
        return;
      }
      if (!_current(generation)) return;
    }

    publish(
      _sessionState(
        error: verification == CloudVerification.unavailable
            ? '服务器暂时不可用，已保留登录状态'
            : _api.configurationError,
      ),
    );
  }

  Future<void> setBaseUrl(String url) async {
    final generation = ++_generation;
    try {
      await _api.setBaseUrl(url);
    } on ArgumentError catch (error) {
      if (_current(generation)) {
        publish(
          value.copyWith(checking: false, error: error.message?.toString()),
        );
      }
      rethrow;
    }
    if (!_current(generation)) return;
    publish(_sessionState());
  }

  Future<bool> login(String username, String password) async {
    final generation = ++_generation;
    try {
      await _api.login(username, password);
    } catch (error) {
      if (_current(generation) || error is CloudSessionSafetyError) {
        publish(value.copyWith(checking: false, error: error.toString()));
      }
      return false;
    }
    if (!_current(generation)) return false;
    publish(_sessionState());
    return true;
  }

  Future<bool> register(String username, String password) async {
    final generation = ++_generation;
    try {
      await _api.register(username, password);
    } catch (error) {
      if (_current(generation) || error is CloudSessionSafetyError) {
        publish(value.copyWith(checking: false, error: error.toString()));
      }
      return false;
    }
    if (!_current(generation)) return false;
    publish(_sessionState());
    return true;
  }

  Future<void> logout() async {
    final generation = ++_generation;
    try {
      await _api.clearSession();
    } catch (_) {
      if (_current(generation)) {
        publish(_sessionState(error: '无法清除安全凭据'));
      }
      return;
    }
    if (!_current(generation)) return;
    publish(_sessionState());
  }
}

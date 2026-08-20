import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../domain/sync_account.dart';

final class SyncIdentityStore {
  SyncIdentityStore({Future<SharedPreferences> Function()? preferences})
    : _preferences = preferences ?? SharedPreferences.getInstance;

  static const _localUserKey = 'sync_local_user_id';
  static const _deviceKey = 'sync_device_id';
  static const _accountKey = 'sync_account_id';
  static const _stateKey = 'sync_account_state';
  static const _lastSyncKey = 'sync_last_sync_at';
  static const _favoriteBaselinePrefix = 'sync_favorite_baseline_v1_';

  final Future<SharedPreferences> Function() _preferences;
  final Uuid _uuid = const Uuid();

  Future<SyncAccount> load() async {
    final prefs = await _preferences();
    final localUserId =
        prefs.getString(_localUserKey) ??
        await _createAndStore(prefs, _localUserKey, 'local');
    final deviceId =
        prefs.getString(_deviceKey) ??
        await _createAndStore(prefs, _deviceKey, 'device');
    final state = SyncAccountState.values.firstWhere(
      (value) => value.name == prefs.getString(_stateKey),
      orElse: () => SyncAccountState.anonymous,
    );
    final lastSync = prefs.getInt(_lastSyncKey);
    return SyncAccount(
      localUserId: localUserId,
      deviceId: deviceId,
      accountId: prefs.getString(_accountKey),
      state: state,
      lastSyncAt: lastSync == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(lastSync, isUtc: true),
    );
  }

  Future<SyncAccount> setState(
    SyncAccount account,
    SyncAccountState state, {
    String? accountId,
  }) async {
    final prefs = await _preferences();
    await prefs.setString(_stateKey, state.name);
    if (accountId != null) await prefs.setString(_accountKey, accountId);
    return account.copyWith(state: state, accountId: accountId);
  }

  Future<SyncAccount> markSynced(SyncAccount account) async {
    final now = DateTime.now().toUtc();
    final prefs = await _preferences();
    await prefs.setString(_stateKey, SyncAccountState.synced.name);
    await prefs.setInt(_lastSyncKey, now.millisecondsSinceEpoch);
    return account.copyWith(state: SyncAccountState.synced, lastSyncAt: now);
  }

  Future<SyncAccount> returnToAnonymous(SyncAccount account) async {
    final prefs = await _preferences();
    await prefs.remove(_accountKey);
    await prefs.setString(_stateKey, SyncAccountState.anonymous.name);
    return SyncAccount(
      localUserId: account.localUserId,
      deviceId: account.deviceId,
      state: SyncAccountState.anonymous,
      lastSyncAt: account.lastSyncAt,
    );
  }

  Future<bool> hasFavoriteBaseline(String accountId) async {
    return (await _preferences()).getBool(
          '$_favoriteBaselinePrefix$accountId',
        ) ==
        true;
  }

  Future<void> markFavoriteBaseline(String accountId) async {
    final ok = await (await _preferences()).setBool(
      '$_favoriteBaselinePrefix$accountId',
      true,
    );
    if (!ok) throw StateError('Unable to persist favorite baseline');
  }

  Future<String> _createAndStore(
    SharedPreferences prefs,
    String key,
    String prefix,
  ) async {
    final value = '${prefix}_${_uuid.v4()}';
    await prefs.setString(key, value);
    return value;
  }
}

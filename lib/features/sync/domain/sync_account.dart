enum SyncAccountState {
  anonymous,
  authenticated,
  merging,
  syncing,
  synced,
  syncError,
}

final class SyncAccount {
  const SyncAccount({
    required this.localUserId,
    required this.deviceId,
    required this.state,
    this.accountId,
    this.lastSyncAt,
  });

  final String localUserId;
  final String deviceId;
  final String? accountId;
  final SyncAccountState state;
  final DateTime? lastSyncAt;

  SyncAccount copyWith({
    String? accountId,
    SyncAccountState? state,
    DateTime? lastSyncAt,
  }) {
    return SyncAccount(
      localUserId: localUserId,
      deviceId: deviceId,
      accountId: accountId ?? this.accountId,
      state: state ?? this.state,
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
    );
  }
}

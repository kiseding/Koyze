import 'sync_account.dart';

final class SyncStateMachine {
  SyncAccount transition(SyncAccount account, SyncAccountState next) {
    final allowed = switch (account.state) {
      SyncAccountState.anonymous => {
        SyncAccountState.authenticated,
        SyncAccountState.merging,
      },
      SyncAccountState.authenticated => {
        SyncAccountState.merging,
        SyncAccountState.syncing,
        SyncAccountState.anonymous,
      },
      SyncAccountState.merging => {
        SyncAccountState.syncing,
        SyncAccountState.syncError,
      },
      SyncAccountState.syncing => {
        SyncAccountState.synced,
        SyncAccountState.syncError,
      },
      SyncAccountState.synced => {
        SyncAccountState.syncing,
        SyncAccountState.anonymous,
        SyncAccountState.merging,
      },
      SyncAccountState.syncError => {
        SyncAccountState.syncing,
        SyncAccountState.merging,
        SyncAccountState.anonymous,
      },
    };
    if (!allowed.contains(next)) {
      throw StateError(
        'Invalid sync state transition: ${account.state.name} -> ${next.name}',
      );
    }
    return account.copyWith(state: next);
  }
}

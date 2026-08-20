import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:koyze/features/sync/data/sync_cursor_store.dart';
import 'package:koyze/features/sync/data/sync_identity_store.dart';
import 'package:koyze/features/sync/data/sync_outbox_repository.dart';
import 'package:koyze/features/sync/domain/sync_account.dart';
import 'package:koyze/features/sync/domain/sync_event.dart';
import 'package:koyze/features/sync/domain/sync_state_machine.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'identity store creates stable anonymous and device identities',
    () async {
      final store = SyncIdentityStore(
        preferences: SharedPreferences.getInstance,
      );
      final first = await store.load();
      final second = await store.load();

      expect(first.localUserId, startsWith('local_'));
      expect(first.deviceId, startsWith('device_'));
      expect(second.localUserId, first.localUserId);
      expect(second.deviceId, first.deviceId);
      expect(first.state, SyncAccountState.anonymous);
    },
  );

  test('event round trip preserves payload and identity fields', () {
    final event = SyncEvent(
      eventId: 'evt_1',
      localUserId: 'local_1',
      deviceId: 'device_1',
      eventType: 'favorite.add',
      entityId: 'song_1',
      payload: {'source': 'tx'},
      createdAt: DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true),
    );

    final decoded = SyncEvent.fromJson(event.toJson());
    expect(decoded.eventId, event.eventId);
    expect(decoded.deviceId, event.deviceId);
    expect(decoded.accountId, event.accountId);
    expect(decoded.payload, event.payload);
    expect(decoded.createdAt, event.createdAt);
  });

  test(
    'outbox append is idempotent and removes accepted events only',
    () async {
      final repo = SyncOutboxRepository(
        preferences: SharedPreferences.getInstance,
      );
      SyncEvent event(String id) => SyncEvent(
        eventId: id,
        localUserId: 'local_1',
        deviceId: 'device_1',
        eventType: 'favorite.add',
        entityId: id,
        payload: const {},
        createdAt: DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true),
      );

      await repo.append(event('evt_1'));
      await repo.append(event('evt_1'));
      await repo.append(event('evt_2'));
      expect((await repo.load()).map((item) => item.eventId), [
        'evt_1',
        'evt_2',
      ]);

      await repo.removeProcessed(['evt_1']);
      expect((await repo.load()).map((item) => item.eventId), ['evt_2']);
    },
  );

  test('cursor store persists non-negative cursor', () async {
    final store = SyncCursorStore(preferences: SharedPreferences.getInstance);
    expect(await store.read(), 0);
    await store.write(12);
    expect(await store.read(), 12);
    expect(() => store.write(-1), throwsArgumentError);
  });

  test('state machine rejects skipping merge and sync phases', () {
    final machine = SyncStateMachine();
    const account = SyncAccount(
      localUserId: 'local_1',
      deviceId: 'device_1',
      state: SyncAccountState.anonymous,
    );

    expect(
      () => machine.transition(account, SyncAccountState.synced),
      throwsStateError,
    );
    expect(
      machine.transition(account, SyncAccountState.authenticated).state,
      SyncAccountState.authenticated,
    );
  });
}

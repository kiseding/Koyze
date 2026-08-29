import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:koyze/features/cloud/domain/cloud_api_client.dart';
import 'package:koyze/features/sync/data/sync_cursor_store.dart';
import 'package:koyze/features/sync/data/sync_identity_store.dart';
import 'package:koyze/features/sync/data/sync_outbox_repository.dart';
import 'package:koyze/features/sync/domain/sync_account.dart';
import 'package:koyze/features/sync/domain/sync_event.dart';
import 'package:koyze/features/sync/domain/sync_phase1_service.dart';
import 'package:koyze/features/sync/domain/sync_state_machine.dart';
import 'package:koyze/features/custom_source/domain/custom_source.dart';
import 'package:koyze/features/custom_source/domain/custom_source_service.dart';
import 'package:koyze/features/playlist/data/playlist_repository.dart';
import 'package:koyze/features/playlist/domain/playlist_service.dart';
import 'package:koyze/features/sync/domain/rating_store.dart';
import 'package:koyze/core/storage/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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

  syncSourceEnablementTests();

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

  test(
    'pushLocalEventsOnly uploads queued favorite events without full sync',
    () async {
      final api = _PushOnlyCloudApi();
      final outbox = SyncOutboxRepository(
        preferences: SharedPreferences.getInstance,
      );
      final service = SyncPhase1Service(api: api, outbox: outbox);
      final recorded = <SyncEvent>[];
      service.onLocalEventRecorded = recorded.add;

      await service.enqueue(
        eventType: 'favorite.add',
        entityId: 'tx:tx:song_1',
        payload: const {'playlistId': 'favorites'},
      );

      expect(recorded.single.eventType, 'favorite.add');
      final report = await service.pushLocalEventsOnly();

      expect(api.fetchAccountStatusCalls, 0);
      expect(api.pullCalls, 0);
      expect(api.pushedEvents.single['eventType'], 'favorite.add');
      expect(api.pushedEvents.single['entityId'], 'tx:tx:song_1');
      expect(await outbox.load(), isEmpty);
      expect(report?.counts, {'收藏': 1});
    },
  );

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

final class _PushOnlyCloudApi extends CloudApiClient {
  final pushedEvents = <Map<String, dynamic>>[];
  int fetchAccountStatusCalls = 0;
  int pullCalls = 0;

  @override
  bool get isLoggedIn => true;

  @override
  String? get accountId => 'acct_1';

  @override
  String? get username => 'user';

  @override
  Future<Map<String, dynamic>> pushSyncEvents({
    required String deviceId,
    required List<Map<String, dynamic>> events,
  }) async {
    pushedEvents.addAll(events.map(Map<String, dynamic>.from));
    return {
      'acceptedEventIds': [for (final event in events) event['eventId']],
    };
  }

  @override
  Future<Map<String, dynamic>> fetchSyncAccountStatus() async {
    fetchAccountStatusCalls++;
    return const {};
  }

  @override
  Future<Map<String, dynamic>> pullSyncEvents({required int cursor}) async {
    pullCalls++;
    return const {'events': [], 'hasMore': false, 'cursor': 0};
  }
}

// 自定义源同步回归：启用状态是设备本地偏好，同步不改变它。
void syncSourceEnablementTests() {
  test(
    'remote upsert keeps local enablement and new sources default disabled',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final sourcesService = CustomSourceService(
        storageLoader: () async => StorageService.instance,
      );
      final phase1 = SyncPhase1Service(
        api: CloudApiClient(
          dio: Dio(),
          preferences: () async => prefs,
        ),
        identity: SyncIdentityStore(preferences: () async => prefs),
        cursor: SyncCursorStore(preferences: () async => prefs),
        outbox: SyncOutboxRepository(preferences: () async => prefs),
      )
        ..attachSources(sourcesService)
        ..attachPlaylists(
          PlaylistService(
            repository: _FakePlaylistRepository(),
            syncRecorder:
                ({required String eventType, required String entityId, Map<String, dynamic>? payload}) async {},
          ),
        )
        ..attachRatings(RatingStore(preferences: () async => prefs))
        ..attachSettingApplier((key, value) async {});

      await sourcesService.init();
      final now = DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true);
      // 用 addSource 直接构造源，避免 importLxMusicScript 触发
      // flutter_js runtime 初始化（CI 上慢/超时，与本测试目标无关）。
      await sourcesService.addSource(
        CustomSource(
          id: 'src_a',
          name: 'A',
          description: '',
          version: '1.0.0',
          author: 'local',
          script: _sourceScript('A'),
          createdAt: now,
          updatedAt: now,
          isEnabled: true,
        ),
      );
      await sourcesService.addSource(
        CustomSource(
          id: 'src_b',
          name: 'B',
          description: '',
          version: '1.0.0',
          author: 'local',
          script: _sourceScript('B'),
          createdAt: now,
          updatedAt: now,
          isEnabled: true,
        ),
      );
      final localA = sourcesService.sources.firstWhere((s) => s.name == 'A');
      final localB = sourcesService.sources.firstWhere((s) => s.name == 'B');
      await sourcesService.toggleSource(localB.id);
      expect(sourcesService.enabledSources.length, 1);

      // 远端推送 A（isEnabled=true 的脏数据）与全新源 C。
      final applied = await phase1.applyPulledEvents([
        {
          'eventId': 'evt_a',
          'eventType': 'custom_source.upsert',
          'entityId': localA.id,
          'payload': {
            'source': localA.copyWith(isEnabled: true).toJson(),
          },
          'createdAt': now.toIso8601String(),
        },
        {
          'eventId': 'evt_c',
          'eventType': 'custom_source.upsert',
          'entityId': 'remote_c',
          'payload': {'source': _remoteSourceJson('remote_c', 'C')},
          'createdAt': now.toIso8601String(),
        },
      ]);
      expect(applied, isTrue);

      // A 保持启用、B 保持禁用、C 默认禁用 → 仍只有 1 个启用。
      expect(sourcesService.sources.where((s) => s.isEnabled).length, 1);
      // 云端推送与本地"同名不同 id"的源（C 复制品 D）也必须保留，
      // 不能被 name|author 去重折叠掉。
      await phase1.applyPulledEvents([
        {
          'eventId': 'evt_d',
          'eventType': 'custom_source.upsert',
          'entityId': 'remote_d',
          'payload': {
            'source': _remoteSourceJson('remote_d', 'C'),
          },
          'createdAt': now.toIso8601String(),
        },
      ]);
      expect(
        sourcesService.sources.any((s) => s.id == 'remote_d'),
        isTrue,
        reason: '同名不同 id 的云端音源被去重丢弃',
      );
      expect(
        sourcesService.sources.firstWhere((s) => s.id == localA.id).isEnabled,
        isTrue,
      );
      expect(
        sourcesService.sources.firstWhere((s) => s.id == localB.id).isEnabled,
        isFalse,
      );
      expect(
        sourcesService.sources.firstWhere((s) => s.id == 'remote_c').isEnabled,
        isFalse,
      );
    },
  );
}

String _sourceScript(String name) =>
    '/*! @name $name */\nconst api = () => 1;';

Map<String, dynamic> _remoteSourceJson(String id, String name) {
  final now = DateTime.fromMillisecondsSinceEpoch(2000, isUtc: true);
  return {
    'id': id,
    'name': name,
    'description': '',
    'version': '1.0.0',
    'author': 'sync',
    'script': _sourceScript(name),
    'createdAt': now.toIso8601String(),
    'updatedAt': now.toIso8601String(),
  };
}

class _FakePlaylistRepository implements PlaylistRepository {
  @override
  Future<PlaylistSnapshot> load() async =>
      PlaylistSnapshot(schemaVersion: 1, playlists: []);

  @override
  Future<void> save(PlaylistSnapshot snapshot) async {}
}

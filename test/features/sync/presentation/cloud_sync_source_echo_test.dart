import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:koyze/core/storage/storage_service.dart';
import 'package:koyze/features/cloud/domain/cloud_api_client.dart';
import 'package:koyze/features/custom_source/domain/custom_source.dart';
import 'package:koyze/features/custom_source/domain/custom_source_service.dart';
import 'package:koyze/features/sync/data/sync_cursor_store.dart';
import 'package:koyze/features/sync/data/sync_identity_store.dart';
import 'package:koyze/features/sync/data/sync_outbox_repository.dart';
import 'package:koyze/features/sync/domain/sync_phase1_service.dart';
import 'package:koyze/features/sync/presentation/cloud_sync_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'enablement and timestamps do not enqueue another source upsert',
    () async {
      final harness = await _SourceSyncHarness.create();
      final source = _source('src_1', enabled: true);
      harness.notifier.attachInitialSources([source]);

      harness.notifier.sourcesChanged([
        source.copyWith(
          isEnabled: false,
          updatedAt: source.updatedAt.add(const Duration(seconds: 5)),
        ),
      ]);
      await harness.settle();

      expect(await harness.phase1.pendingCount(), 0);
      harness.notifier.dispose();
    },
  );

  test(
    'applying a remote source does not echo it back to the outbox',
    () async {
      final harness = await _SourceSyncHarness.create();
      final local = _source('src_1', enabled: true);
      harness.notifier.attachInitialSources([local]);
      await harness.sources.addSource(local);

      harness.notifier.onApplyingRemote(true);
      final remote = local.copyWith(
        script: '/*! @name Remote */\nconst api = () => 1;',
        isEnabled: false,
        updatedAt: DateTime.fromMillisecondsSinceEpoch(5000, isUtc: true),
      );
      await harness.sources.replaceAllSources([remote]);
      harness.notifier.sourcesChanged(harness.sources.sources);
      harness.notifier.onApplyingRemote(false);
      harness.notifier.sourcesChanged(harness.sources.sources);
      await harness.settle();

      expect(await harness.phase1.pendingCount(), 0);
      harness.notifier.dispose();
    },
  );

  test('editing a source definition still records an upsert', () async {
    final harness = await _SourceSyncHarness.create();
    final source = _source('src_1', enabled: true);
    harness.notifier.attachInitialSources([source]);

    harness.notifier.sourcesChanged([
      source.copyWith(script: '/*! @name Edited */\nsearch'),
    ]);
    await harness.settle();

    final pending = await harness.phase1.outbox.load();
    expect(pending, hasLength(1));
    expect(pending.single.eventType, 'custom_source.upsert');
    expect(pending.single.entityId, 'src_1');
    harness.notifier.dispose();
  });

  test('toggling a source keeps the synced timestamp unchanged', () async {
    SharedPreferences.setMockInitialValues({});
    final service = CustomSourceService(
      storageLoader: () async => StorageService.instance,
    );
    await service.init();
    final source = _source('src_toggle', enabled: true);
    await service.addSource(source);
    final before = service.sources.single.updatedAt;

    expect(await service.toggleSource(source.id), isTrue);
    expect(service.sources.single.isEnabled, isFalse);
    expect(service.sources.single.updatedAt, before);
    service.dispose();
  });
}

CustomSource _source(String id, {required bool enabled}) {
  final now = DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true);
  return CustomSource(
    id: id,
    name: 'Source',
    description: '',
    version: '1.0.0',
    author: 'local',
    script: '/*! @name Source */\nconst api = () => 1;',
    createdAt: now,
    updatedAt: now,
    isEnabled: enabled,
  );
}

final class _SourceSyncHarness {
  _SourceSyncHarness({
    required this.phase1,
    required this.notifier,
    required this.sources,
  });

  final SyncPhase1Service phase1;
  final CloudSyncNotifier notifier;
  final CustomSourceService sources;

  static Future<_SourceSyncHarness> create() async {
    final prefs = await SharedPreferences.getInstance();
    final sources = CustomSourceService(
      storageLoader: () async => StorageService.instance,
    );
    await sources.init();
    final phase1 = SyncPhase1Service(
      api: CloudApiClient(dio: Dio(), preferences: () async => prefs),
      identity: SyncIdentityStore(preferences: () async => prefs),
      cursor: SyncCursorStore(preferences: () async => prefs),
      outbox: SyncOutboxRepository(preferences: () async => prefs),
    )..attachSources(sources);
    final notifier = CloudSyncNotifier(phase1: phase1, loggedIn: () => true);
    return _SourceSyncHarness(
      phase1: phase1,
      notifier: notifier,
      sources: sources,
    );
  }

  Future<void> settle() async {
    for (var i = 0; i < 8; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }
}

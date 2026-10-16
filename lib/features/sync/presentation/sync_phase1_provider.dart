import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../cloud/presentation/cloud_provider.dart';
import '../domain/sync_phase1_service.dart';
import '../domain/rating_service.dart';
import '../domain/rating_store.dart';

final syncPhase1ServiceProvider = Provider<SyncPhase1Service>((ref) {
  return SyncPhase1Service(api: ref.watch(cloudApiProvider));
});

final ratingServiceProvider = Provider<RatingService>((ref) {
  final store = RatingStore();
  ref.read(syncPhase1ServiceProvider).attachRatings(store);
  return RatingService(
    store: store,
    sync: ref.watch(syncPhase1ServiceProvider),
  );
});

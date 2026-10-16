import 'rating_store.dart';
import 'sync_phase1_service.dart';

final class RatingService {
  RatingService({required this.store, required this.sync});

  final RatingStore store;
  final SyncPhase1Service sync;

  Future<void> set(String songId, int rating) async {
    await store.set(songId, rating);
    await sync.enqueue(
      eventType: 'rating.set',
      entityId: songId,
      payload: {'rating': rating},
    );
  }

  Future<void> remove(String songId) async {
    await store.remove(songId);
    await sync.enqueue(
      eventType: 'rating.remove',
      entityId: songId,
      payload: const {},
    );
  }
}

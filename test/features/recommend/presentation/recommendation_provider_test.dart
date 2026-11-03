// 「猜你喜欢」什么时候该重算。
//
// 这里钉的是用户能感知的那条线：收藏或歌单变过之后，下次打开推荐页就得
// 看到新结果，而不是等 12 小时 TTL 或者重启软件。反过来，数据没变时不能
// 每帧都重算——一次重算要为每个常听歌手 × 每个音源各发一次搜索。
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/features/recommend/domain/recommendation_engine.dart';
import 'package:koyze/features/recommend/presentation/recommendation_provider.dart';

Future<void> _settle() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  test('数据变过之后 refreshIfStale 才重算', () async {
    var calls = 0;
    final revision = StateProvider<int>((ref) => 0);
    final container = ProviderContainer(
      overrides: [
        recommendationDataRevisionProvider.overrideWith(
          (ref) => ref.watch(revision),
        ),
        recommendationProvider.overrideWith(
          () => RecommendationNotifier(
            loader: () async {
              calls++;
              return const <RecommendedSong>[];
            },
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    // 首算由 build 触发。
    container.read(recommendationProvider);
    await _settle();
    expect(calls, 1);

    // 没人动过数据：问到脸上了也不该重算。
    await container
        .read(recommendationProvider.notifier)
        .refreshIfStale(urgent: true);
    expect(calls, 1);

    // 收藏变了，但只是路过（非 urgent）：节流窗口内先不动。
    container.read(revision.notifier).state = 1;
    await _settle();
    await container.read(recommendationProvider.notifier).refreshIfStale();
    expect(calls, 1);

    // 用户主动打开推荐页：必须立刻用上新数据。
    await container
        .read(recommendationProvider.notifier)
        .refreshIfStale(urgent: true);
    await _settle();
    expect(calls, 2);

    // 重算完就干净了，再问不会再算一次。
    await container
        .read(recommendationProvider.notifier)
        .refreshIfStale(urgent: true);
    expect(calls, 2);
  });

  test('空结果用短 TTL，别让推荐空一整天', () {
    expect(kRecommendationEmptyTtl, lessThan(kRecommendationCacheTtl));
    expect(kRecommendationEmptyTtl.inMinutes, lessThanOrEqualTo(10));
  });
}

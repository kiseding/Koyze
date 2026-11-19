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
            // 这里钉的是「什么时候重算」，不是启动让路，把延迟关掉。
            startupDelay: Duration.zero,
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

  test('冷启动首次计算让路给首帧，但用户一喊就立刻开跑', () async {
    // 这一条钉的是启动期网络风暴的一半：推荐候选是「歌手 × 音源」的笛卡尔积，
    // 以前 build 里立刻发出，正好压在首帧和会话恢复上。现在先等一段，
    // 但用户主动打开推荐页（urgent）时必须跳过等待。
    var calls = 0;
    final container = ProviderContainer(
      overrides: [
        recommendationDataRevisionProvider.overrideWith((ref) => 0),
        recommendationProvider.overrideWith(
          () => RecommendationNotifier(
            startupDelay: const Duration(seconds: 5),
            loader: () async {
              calls++;
              return const <RecommendedSong>[];
            },
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    container.read(recommendationProvider);
    await _settle();
    expect(calls, 0, reason: '启动窗口内不该发请求');

    // 用户主动打开推荐页：不等那 5 秒。
    await container
        .read(recommendationProvider.notifier)
        .refreshIfStale(urgent: true);
    await _settle();
    expect(calls, 1, reason: 'urgent 请求要打断启动让路');
  });
}

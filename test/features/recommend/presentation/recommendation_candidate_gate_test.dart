// 推荐候选收集的并发上限。
//
// 这是启动期网络风暴的处方：候选是「查询词 × 平台」的笛卡尔积，收藏里有
// 五个常听歌手、四个平台就是 20 条请求。全部并发发出去，在弱网下不是更快，
// 而是所有连接挤在同一条链路上集体超时，十秒后又同一毫秒一起失败返回，
// 把 20 个异常砸在同一帧的 UI isolate 上（实测 371ms 停顿）。
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/music_source/platform/built_in_source_manager.dart';
import 'package:koyze/core/network/network_gate.dart';
import 'package:koyze/core/music_source/platform/music_platform.dart';
import 'package:koyze/features/player/domain/music_item.dart';
import 'package:koyze/features/recommend/presentation/recommendation_provider.dart';

/// 这一次批量里所有假平台共享的并发计数。
///
/// 峰值必须按**全局**统计：每个平台自己同时只会有一个在飞，按平台算永远是 1，
/// 量不到闸门。
class _Probe {
  int running = 0;
  int peak = 0;
  int calls = 0;
}

/// 只回一条结果、并按需拖住一小会儿的假平台。
class _FakePlatform extends MusicPlatform {
  _FakePlatform(this.id, this.probe);

  @override
  final String id;

  final _Probe probe;

  @override
  String get name => id;

  @override
  Future<List<MusicItem>> search(
    String keyword, {
    int page = 1,
    int limit = 20,
  }) async {
    probe.calls++;
    probe.running++;
    if (probe.running > probe.peak) probe.peak = probe.running;
    await Future<void>.delayed(const Duration(milliseconds: 4));
    probe.running--;
    return [
      MusicItem(
        id: '$id-$keyword',
        name: keyword,
        singer: keyword,
        source: 'builtin',
        platform: id,
      ),
    ];
  }

  @override
  Future<String?> getLyric(MusicItem music) async => null;

  @override
  MusicItem parseItem(Map<String, dynamic> raw, String source) => MusicItem(
    id: raw['id']?.toString() ?? '',
    name: raw['name']?.toString() ?? '',
    singer: raw['singer']?.toString() ?? '',
    source: source,
    platform: id,
  );
}

void main() {
  test('候选收集真实并发不超过 3，且结果全部落进候选池', () async {
    final probe = _Probe();
    final manager = BuiltInSourceManager(
      platforms: <MusicPlatform>[
        _FakePlatform('kw', probe),
        _FakePlatform('tx', probe),
        _FakePlatform('wy', probe),
      ],
    );
    final into = <String, MusicItem>{};

    // 5 个查询词 × 3 个平台 = 15 条，以前会同时发出去。
    await collectRecommendationCandidates(
      manager: manager,
      platformIds: ['kw', 'tx', 'wy'],
      queries: const ['周杰伦', '陈奕迅', '五月天', '林俊杰', '孙燕姿'],
      into: into,
    );

    expect(probe.peak, kRecommendationSearchConcurrency, reason: '峰值并发要卡在闸门上');
    expect(probe.calls, 15, reason: '限流不能少发请求');
    expect(into.length, 15, reason: '限流不能丢结果');
  });

  test('同一个闸门可以被两次收集复用，峰值不翻倍', () async {
    final probe = _Probe();
    final manager = BuiltInSourceManager(
      platforms: <MusicPlatform>[
        _FakePlatform('kw', probe),
        _FakePlatform('tx', probe),
      ],
    );
    final gate = NetworkGate(maxConcurrent: kRecommendationSearchConcurrency);
    final into = <String, MusicItem>{};

    // 模拟「常听歌手」+「口味提示」两轮；真实代码里它们共用一份名额。
    await collectRecommendationCandidates(
      manager: manager,
      platformIds: ['kw', 'tx'],
      queries: const ['周杰伦', '陈奕迅', '五月天'],
      into: into,
      gate: gate,
    );
    await collectRecommendationCandidates(
      manager: manager,
      platformIds: ['kw', 'tx'],
      queries: const ['粤语老歌', '八九十年代'],
      into: into,
      gate: gate,
    );

    expect(probe.peak, lessThanOrEqualTo(kRecommendationSearchConcurrency));
    expect(probe.peak, greaterThan(1), reason: '确实并行过，不是串行跑完的');
    expect(into.length, 10);
  });

  test('单个平台抛异常不影响其余请求', () async {
    final good = _FakePlatform('kw', _Probe());
    final bad = _ThrowingPlatform('tx');
    final manager = BuiltInSourceManager(
      platforms: <MusicPlatform>[good, bad],
    );
    final into = <String, MusicItem>{};

    await collectRecommendationCandidates(
      manager: manager,
      platformIds: ['kw', 'tx'],
      queries: const ['周杰伦', '陈奕迅'],
      into: into,
    );

    expect(into.length, 2, reason: '好平台的 2 条要留下');
  });
}

class _ThrowingPlatform extends MusicPlatform {
  _ThrowingPlatform(this.id);

  @override
  final String id;

  @override
  String get name => id;

  @override
  Future<List<MusicItem>> search(
    String keyword, {
    int page = 1,
    int limit = 20,
  }) async {
    throw StateError('source down');
  }

  @override
  Future<String?> getLyric(MusicItem music) async => null;

  @override
  MusicItem parseItem(Map<String, dynamic> raw, String source) => MusicItem(
    id: raw['id']?.toString() ?? '',
    name: raw['name']?.toString() ?? '',
    singer: raw['singer']?.toString() ?? '',
    source: source,
    platform: id,
  );
}

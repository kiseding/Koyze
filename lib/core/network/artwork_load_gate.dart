import 'dart:async';
import 'dart:collection';

/// 封面下载的并发闸门。
///
/// 打开一页歌单时首屏十几行会同时发起封面请求：十几条连接一起排队、
/// 一起解码，正好压在「列表挂载后的那一两帧」上（延后挂载只是把这段
/// 成本挪到动效之后，并没有让它变便宜）。限到 5 条后新请求排队等前面
/// 结束，帧就有喘息空间。
///
/// 只挡网络下载：磁盘 / 内存缓存命中的路径本来就不经过这里，不会因为
/// 排队反而变慢。
class ArtworkLoadGate {
  ArtworkLoadGate({this.maxConcurrent = 5}) : assert(maxConcurrent > 0);

  /// 同一时刻允许在跑的下载数。
  final int maxConcurrent;

  final Queue<Completer<void>> _waiting = Queue<Completer<void>>();
  int _active = 0;

  /// 当前占着名额的任务数。
  int get activeCount => _active;

  /// 还在排队的任务数。
  int get waitingCount => _waiting.length;

  /// 占一个名额跑 [action]，无论成功失败都会还回去。
  Future<T> run<T>(Future<T> Function() action) async {
    await _acquire();
    try {
      return await action();
    } finally {
      _release();
    }
  }

  Future<void> _acquire() {
    if (_active < maxConcurrent) {
      _active += 1;
      return Future<void>.value();
    }
    final completer = Completer<void>();
    _waiting.add(completer);
    return completer.future;
  }

  void _release() {
    if (_waiting.isNotEmpty) {
      // 名额直接交给队首：先减再加会让两个等待者同时被放进来。
      _waiting.removeFirst().complete();
      return;
    }
    _active -= 1;
  }
}

/// 进程内共用的一份名额。
final ArtworkLoadGate artworkLoadGate = ArtworkLoadGate();

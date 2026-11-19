// Copyright 2024 Koyze Contributors
// Licensed under the Apache License, Version 2.0

import 'dart:async';
import 'dart:collection';

/// 一批网络任务的并发闸门。
///
/// 与 [ArtworkLoadGate] 是同一套机制，区别在适用范围：那个是进程内单例、
/// 专给封面下载用；这个是**每次任务现建一个**，名额跟着这一次批量走，跑完
/// 就丢。适合「先攒出一张请求清单、再限流跑完」的场景（推荐候选、榜单预取）。
///
/// 为什么要限：启动那一两秒里把 N 个音源请求同时发出去，在弱网下不是
/// 「快」，而是所有连接一起排在同一个 TCP 队列里集体 connectionTimeout，
/// 十秒后又**同时**失败返回，25 个异常挤在同一帧回到 UI isolate——主线程被
/// 一次性占住几百毫秒。限到 2~3 条之后，前几条出结果或超时了才发下一条，
/// 失败时刻自然错开，且首屏该用的数据仍然排在最前面。
class NetworkGate {
  NetworkGate({this.maxConcurrent = 3}) : assert(maxConcurrent > 0);

  /// 同一时刻允许在跑的任务数。
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

// 播放层用到的两条流组合工具。
//
// 为什么自己写：Dart 标准库既没有 `Stream.merge`（那是 rxdart 的扩展），
// 也没有窗口节流。抽象层刻意不引入 rxdart —— 它会把「引擎适配」这件事
// 和另一套流语义绑在一起，而这里只需要两个明确的行为。

import 'dart:async';

/// 把多条流合并成一条：任一来源发出就转发一次，全部结束后关闭。
///
/// 只支持「一堆同类型流 → 一条流」这个唯一用途。任一来源出错就向下游
/// 传递错误并立即关闭合并流——播放层把流错误当致命信号处理，继续转发
/// 后续事件只会让状态机读到半真半假的数据。
Stream<T> mergeStreams<T>(List<Stream<T>> sources) {
  final controller = StreamController<T>();
  var remaining = sources.length;
  if (remaining == 0) {
    controller.close();
    return controller.stream;
  }
  final subscriptions = <StreamSubscription<T>>[];
  void finish() {
    if (--remaining > 0) return;
    for (final subscription in subscriptions) {
      unawaited(subscription.cancel());
    }
    controller.close();
  }

  controller.onListen = () {
    for (final source in sources) {
      subscriptions.add(
        source.listen(
          controller.add,
          onError: (Object error, StackTrace stackTrace) {
            controller.addError(error, stackTrace);
            finish();
          },
          onDone: finish,
        ),
      );
    }
  };
  controller.onCancel = () {
    for (final subscription in subscriptions) {
      unawaited(subscription.cancel());
    }
  };
  return controller.stream;
}

/// 窗口节流：立即放行第一个值，窗口内的后续值只保留最后一个，窗口关闭
/// 时补发。
///
/// **必须保留尾值**。暂停、播放结束这类事件往往正好落在窗口里，丢掉就会
/// 让上层停在旧状态（暂停了但锁屏仍显示播放中）。
///
/// 用 `List` 当单值缓冲而不是可空字段：`T` 可能是 `void`，而 `void?` 的
/// 判空与赋值在 Dart 里都不成立。
Stream<T> throttleStream<T>(Stream<T> source, Duration window) {
  late final StreamController<T> controller;
  final buffer = <T>[];
  StreamSubscription<T>? subscription;
  Timer? timer;

  void flush() {
    timer = null;
    if (buffer.isEmpty) return;
    final value = buffer.removeLast();
    buffer.clear();
    controller.add(value);
  }

  controller = StreamController<T>(
    onListen: () {
      subscription = source.listen(
        (value) {
          if (timer != null) {
            buffer
              ..clear()
              ..add(value);
            return;
          }
          controller.add(value);
          timer = Timer(window, flush);
        },
        onError: controller.addError,
        onDone: () {
          timer?.cancel();
          timer = null;
          flush();
          controller.close();
        },
      );
    },
    onCancel: () {
      timer?.cancel();
      timer = null;
      buffer.clear();
      return subscription?.cancel();
    },
  );
  return controller.stream;
}

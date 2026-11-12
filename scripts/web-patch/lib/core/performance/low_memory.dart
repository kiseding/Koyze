// Web 版：浏览器拿不到物理内存，也不做 dart:ffi 调用。
// 公开 API 与原生版完全一致，UI 层引用 LowMemory.active 的代码零改动。

/// Devices at or below this much physical RAM default to simplified effects.
const lowMemoryLimitBytes = 4 * 1024 * 1024 * 1024;

bool isLowMemoryDevice(int? totalBytes) {
  if (totalBytes == null || totalBytes <= 0) return false;
  return totalBytes <= lowMemoryLimitBytes;
}

bool resolveSimplifyEffects({required bool lowMemoryDevice, bool? stored}) {
  return stored ?? lowMemoryDevice;
}

abstract final class LowMemory {
  static bool active = false;

  static Future<void> detect() async {
    // 浏览器不暴露物理内存；特效档位完全由设置里的用户开关决定。
    active = false;
  }
}

Future<int?> totalPhysicalMemoryBytes() async => null;

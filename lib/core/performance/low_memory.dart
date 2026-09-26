import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

/// Devices at or below this much physical RAM default to simplified effects.
/// The fullscreen cover blur, the Android floating player, and loading
/// indicators stay. A saved settings choice overrides this default.
const lowMemoryLimitBytes = 4 * 1024 * 1024 * 1024;

bool isLowMemoryDevice(int? totalBytes) {
  if (totalBytes == null || totalBytes <= 0) return false;
  return totalBytes <= lowMemoryLimitBytes;
}

/// `stored` is the user's switch. When it is unset, follow device memory.
bool resolveSimplifyEffects({required bool lowMemoryDevice, bool? stored}) {
  return stored ?? lowMemoryDevice;
}

abstract final class LowMemory {
  static bool active = false;

  static Future<void> detect() async {
    try {
      active = isLowMemoryDevice(await totalPhysicalMemoryBytes());
    } catch (_) {
      active = false;
    }
  }
}

Future<int?> totalPhysicalMemoryBytes() async {
  if (kIsWeb) return null;
  if (Platform.isAndroid || Platform.isLinux) return _memInfoBytes();
  if (Platform.isMacOS || Platform.isIOS) return _appleMemoryBytes();
  if (Platform.isWindows) return _windowsMemoryBytes();
  return null;
}

Future<int?> _memInfoBytes() async {
  final text = await File('/proc/meminfo').readAsString();
  final match = RegExp(r'MemTotal:\s+(\d+)\s+kB').firstMatch(text);
  if (match == null) return null;
  return int.parse(match.group(1)!) * 1024;
}

int? _appleMemoryBytes() {
  final sysctlbyname = DynamicLibrary.process()
      .lookupFunction<
        Int32 Function(
          Pointer<Utf8>,
          Pointer<Uint64>,
          Pointer<Uint64>,
          Pointer<Void>,
          Uint64,
        ),
        int Function(
          Pointer<Utf8>,
          Pointer<Uint64>,
          Pointer<Uint64>,
          Pointer<Void>,
          int,
        )
      >('sysctlbyname');
  final name = 'hw.memsize'.toNativeUtf8();
  final value = calloc<Uint64>();
  final size = calloc<Uint64>()..value = sizeOf<Uint64>();
  try {
    final status = sysctlbyname(name, value, size, nullptr, 0);
    if (status != 0) return null;
    return value.value;
  } finally {
    calloc.free(name);
    calloc.free(value);
    calloc.free(size);
  }
}

final class _MemoryStatusEx extends Struct {
  @Uint32()
  external int length;

  @Uint32()
  external int memoryLoad;

  @Uint64()
  external int totalPhys;

  @Uint64()
  external int availPhys;

  @Uint64()
  external int totalPageFile;

  @Uint64()
  external int availPageFile;

  @Uint64()
  external int totalVirtual;

  @Uint64()
  external int availVirtual;

  @Uint64()
  external int availExtendedVirtual;
}

int? _windowsMemoryBytes() {
  final statusEx = DynamicLibrary.open('kernel32.dll')
      .lookupFunction<
        Int32 Function(Pointer<_MemoryStatusEx>),
        int Function(Pointer<_MemoryStatusEx>)
      >('GlobalMemoryStatusEx');
  final status = calloc<_MemoryStatusEx>();
  try {
    status.ref.length = sizeOf<_MemoryStatusEx>();
    if (statusEx(status) == 0) return null;
    return status.ref.totalPhys;
  } finally {
    calloc.free(status);
  }
}

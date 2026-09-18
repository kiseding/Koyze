import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// 预设曲线上的一个控制点。
@immutable
class EqualizerControlPoint {
  const EqualizerControlPoint(this.frequencyHz, this.gainDb);

  final double frequencyHz;
  final double gainDb;
}

/// 均衡器预设。
///
/// 用「频率 → 增益」的控制点描述频响曲线，而不是固定长度的增益数组：
/// Android 上不同设备的均衡器段数并不一致（常见 5 段，也有 10 段实现），
/// 曲线可以插值到任意段数上。
@immutable
class EqualizerPreset {
  const EqualizerPreset({
    required this.id,
    required this.label,
    required this.curve,
  });

  final String id;
  final String label;

  /// 按频率升序排列的控制点。
  final List<EqualizerControlPoint> curve;

  /// 在 [frequencyHz] 处取值。频率轴取对数（听感近似线性），
  /// 两端之外取端点值。
  double gainAt(double frequencyHz) {
    if (curve.isEmpty) return 0;
    if (frequencyHz <= 0 || curve.length == 1) return curve.first.gainDb;
    if (frequencyHz <= curve.first.frequencyHz) return curve.first.gainDb;
    for (var i = 1; i < curve.length; i++) {
      final previous = curve[i - 1];
      final next = curve[i];
      if (frequencyHz > next.frequencyHz) continue;
      final span = math.log(next.frequencyHz / previous.frequencyHz);
      if (span <= 0) return next.gainDb;
      final ratio = math.log(frequencyHz / previous.frequencyHz) / span;
      return previous.gainDb + (next.gainDb - previous.gainDb) * ratio;
    }
    return curve.last.gainDb;
  }

  /// 把曲线采样到给定的中心频率上，得到可直接施加的频段增益。
  List<double> gainsFor(List<double> centerFrequencies) => <double>[
    for (final frequency in centerFrequencies) gainAt(frequency),
  ];
}

/// 内置预设。顺序即界面展示顺序：前面是「原声」与常用风格，
/// 后面是单频段增强。
const List<EqualizerPreset> equalizerPresets = <EqualizerPreset>[
  EqualizerPreset(
    id: 'flat',
    label: '原声',
    curve: <EqualizerControlPoint>[
      EqualizerControlPoint(60, 0),
      EqualizerControlPoint(230, 0),
      EqualizerControlPoint(910, 0),
      EqualizerControlPoint(3600, 0),
      EqualizerControlPoint(14000, 0),
    ],
  ),
  EqualizerPreset(
    id: 'pop',
    label: '流行',
    curve: <EqualizerControlPoint>[
      EqualizerControlPoint(60, 1),
      EqualizerControlPoint(230, 2),
      EqualizerControlPoint(910, 1),
      EqualizerControlPoint(3600, 2),
      EqualizerControlPoint(14000, 1),
    ],
  ),
  EqualizerPreset(
    id: 'rock',
    label: '摇滚',
    curve: <EqualizerControlPoint>[
      EqualizerControlPoint(60, 4),
      EqualizerControlPoint(230, 2),
      EqualizerControlPoint(910, -1),
      EqualizerControlPoint(3600, 2),
      EqualizerControlPoint(14000, 3),
    ],
  ),
  EqualizerPreset(
    id: 'jazz',
    label: '爵士',
    curve: <EqualizerControlPoint>[
      EqualizerControlPoint(60, 3),
      EqualizerControlPoint(230, 2),
      EqualizerControlPoint(910, 0),
      EqualizerControlPoint(3600, 2),
      EqualizerControlPoint(14000, 3),
    ],
  ),
  EqualizerPreset(
    id: 'classical',
    label: '古典',
    curve: <EqualizerControlPoint>[
      EqualizerControlPoint(60, 0),
      EqualizerControlPoint(230, 0),
      EqualizerControlPoint(910, -1),
      EqualizerControlPoint(3600, 2),
      EqualizerControlPoint(14000, 4),
    ],
  ),
  EqualizerPreset(
    id: 'electronic',
    label: '电子',
    curve: <EqualizerControlPoint>[
      EqualizerControlPoint(60, 5),
      EqualizerControlPoint(230, 3),
      EqualizerControlPoint(910, -1),
      EqualizerControlPoint(3600, 2),
      EqualizerControlPoint(14000, 4),
    ],
  ),
  EqualizerPreset(
    id: 'folk',
    label: '民谣',
    curve: <EqualizerControlPoint>[
      EqualizerControlPoint(60, 2),
      EqualizerControlPoint(230, 1),
      EqualizerControlPoint(910, 2),
      EqualizerControlPoint(3600, 1),
      EqualizerControlPoint(14000, 1),
    ],
  ),
  EqualizerPreset(
    id: 'vocal',
    label: '人声',
    curve: <EqualizerControlPoint>[
      EqualizerControlPoint(60, -2),
      EqualizerControlPoint(230, 0),
      EqualizerControlPoint(910, 4),
      EqualizerControlPoint(3600, 3),
      EqualizerControlPoint(14000, -1),
    ],
  ),
  EqualizerPreset(
    id: 'bass',
    label: '低音增强',
    curve: <EqualizerControlPoint>[
      EqualizerControlPoint(60, 6),
      EqualizerControlPoint(230, 4),
      EqualizerControlPoint(910, 1),
      EqualizerControlPoint(3600, 0),
      EqualizerControlPoint(14000, 0),
    ],
  ),
  EqualizerPreset(
    id: 'treble',
    label: '高音增强',
    curve: <EqualizerControlPoint>[
      EqualizerControlPoint(60, 0),
      EqualizerControlPoint(230, 0),
      EqualizerControlPoint(910, 0),
      EqualizerControlPoint(3600, 4),
      EqualizerControlPoint(14000, 6),
    ],
  ),
];

/// 默认预设 id。
const String kDefaultPresetId = 'flat';

/// 按 id 查预设，找不到返回 null。
EqualizerPreset? equalizerPresetById(String id) {
  for (final preset in equalizerPresets) {
    if (preset.id == id) return preset;
  }
  return null;
}

/// 预设标签；未知 id（含自定义）回落到「自定义」。
String equalizerPresetLabel(String id) =>
    equalizerPresetById(id)?.label ?? '自定义';

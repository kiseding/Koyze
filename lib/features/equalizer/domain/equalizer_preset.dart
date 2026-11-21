import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:koyze/core/audio/equalizer_gain.dart';

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
  ///
  /// 采样后再做响度对齐：平均增益回到 0 dB 附近，峰值不超过安全天花板，
  /// 这样开均衡器不会整首变小，也不会因叠峰削波。
  List<double> gainsFor(List<double> centerFrequencies) =>
      normalizeEqualizerGains(<double>[
        for (final frequency in centerFrequencies) gainAt(frequency),
      ]);
}

/// 内置预设。顺序即界面展示顺序：前面是「原声」与常用风格，
/// 后面是单频段增强。
///
/// 曲线设计原则（改动前请先读）：
///
/// 1. 每条曲线的**平均值刻意保持在 0 dB**。`gainsFor` 会先减均值对齐响度，
///    平均值已经是 0 时这一步就变成恒等变换，设计值能 1:1 落到设备上；
///    否则会被整体平移，甚至平移出天花板而被二次削峰（历史上「电子」的
///    910Hz 就从 -2 被平移成了 -3.6）。
/// 2. 每条曲线的**形状必须明显不同**，不能只差一个整体抬高。相邻预设的
///    响度差在 1.9 dB 以上才听得出区别；只差一个常数位移等于没差别
///    （历史上「摇滚」与「电子」只差 0.30 dB，换预设毫无感觉）。
/// 3. 峰值控制在 5 dB 以内、谷值不低于 -7 dB。五段布局的相邻段相隔约
///    1.95 个倍频程，叠加后峰峰值可达单段的 1.3 倍，留足余量才不会削波。
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
  // 流行：低频铺底 + 中高频提亮，超高频略收（电音合成器的齿音多）。
  EqualizerPreset(
    id: 'pop',
    label: '流行',
    curve: <EqualizerControlPoint>[
      EqualizerControlPoint(60, 4),
      EqualizerControlPoint(230, 2),
      EqualizerControlPoint(910, -1),
      EqualizerControlPoint(3600, 2),
      EqualizerControlPoint(14000, -7),
    ],
  ),
  // 摇滚：低频推进 + 中频大幅挖空（吉他/军鼓的经典「笑脸」），
  // 与电子同为两头翘，但凹陷落在 910Hz 且幅度更深、超高频不抬。
  EqualizerPreset(
    id: 'rock',
    label: '摇滚',
    curve: <EqualizerControlPoint>[
      EqualizerControlPoint(60, 5),
      EqualizerControlPoint(230, 1),
      EqualizerControlPoint(910, -5),
      EqualizerControlPoint(3600, 2),
      EqualizerControlPoint(14000, -3),
    ],
  ),
  // 爵士：低频温和、中频饱满、高频收敛，听的是铜管与人声的圆润。
  // 唯一一条整体下坡的曲线（除单频段预设外），与流行/摇滚明显区分。
  EqualizerPreset(
    id: 'jazz',
    label: '爵士',
    curve: <EqualizerControlPoint>[
      EqualizerControlPoint(60, 3),
      EqualizerControlPoint(230, 2),
      EqualizerControlPoint(910, 0),
      EqualizerControlPoint(3600, -1),
      EqualizerControlPoint(14000, -4),
    ],
  ),
  // 古典：一条**温和**的整段上坡。厅堂录音的低频本就偏厚，收一点更通透；
  // 高频只轻轻抬起，避免弦乐泛音过亮发刺。与「高音增强」那种陡上坡
  // 明显不同——两者的区别不在方向，而在幅度与拐点位置。
  EqualizerPreset(
    id: 'classical',
    label: '古典',
    curve: <EqualizerControlPoint>[
      EqualizerControlPoint(60, -3),
      EqualizerControlPoint(230, -1),
      EqualizerControlPoint(910, 0),
      EqualizerControlPoint(3600, 1),
      EqualizerControlPoint(14000, 3),
    ],
  ),
  // 电子：极低频顶起、中频大幅退让、超高频再抬一档，是「两头翘」里
  // 凹陷位置最高的一条（3600Hz），跟摇滚的 910Hz 凹陷错开。
  EqualizerPreset(
    id: 'electronic',
    label: '电子',
    curve: <EqualizerControlPoint>[
      EqualizerControlPoint(60, 5),
      EqualizerControlPoint(230, 0),
      EqualizerControlPoint(910, -4),
      EqualizerControlPoint(3600, -3),
      EqualizerControlPoint(14000, 2),
    ],
  ),
  // 民谣：中高频突出（原声吉他的箱体共鸣在 900Hz 附近），两端都收。
  EqualizerPreset(
    id: 'folk',
    label: '民谣',
    curve: <EqualizerControlPoint>[
      EqualizerControlPoint(60, -3),
      EqualizerControlPoint(230, 1),
      EqualizerControlPoint(910, 5),
      EqualizerControlPoint(3600, -1),
      EqualizerControlPoint(14000, -2),
    ],
  ),
  // 人声：中频极突出，低频与超高频同时退让，齿音不刺。
  EqualizerPreset(
    id: 'vocal',
    label: '人声',
    curve: <EqualizerControlPoint>[
      EqualizerControlPoint(60, -5),
      EqualizerControlPoint(230, -3),
      EqualizerControlPoint(910, 5),
      EqualizerControlPoint(3600, 3),
      EqualizerControlPoint(14000, 0),
    ],
  ),
  // 低音增强：一条整齐的下坡，低频全抬、高频全收。
  EqualizerPreset(
    id: 'bass',
    label: '低音增强',
    curve: <EqualizerControlPoint>[
      EqualizerControlPoint(60, 5),
      EqualizerControlPoint(230, 4),
      EqualizerControlPoint(910, 0),
      EqualizerControlPoint(3600, -4),
      EqualizerControlPoint(14000, -5),
    ],
  ),
  // 高音增强：低音增强的镜像，一条整齐的上坡。
  EqualizerPreset(
    id: 'treble',
    label: '高音增强',
    curve: <EqualizerControlPoint>[
      EqualizerControlPoint(60, -4),
      EqualizerControlPoint(230, -4),
      EqualizerControlPoint(910, -1),
      EqualizerControlPoint(3600, 4),
      EqualizerControlPoint(14000, 5),
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

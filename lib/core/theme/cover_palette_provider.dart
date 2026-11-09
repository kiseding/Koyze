import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/player/presentation/player_provider.dart';
import 'cover_palette.dart';

/// 封面取色服务（单例，带 URL 缓存）。
final coverPaletteServiceProvider = Provider<CoverPaletteService>((ref) {
  return CoverPaletteService.instance;
});

/// 同一次播放里取色失败后的补试间隔。
///
/// 换歌的头一两秒封面经常还没落到磁盘（播放页/锁屏封面是随后才下的），
/// 首试拿不到就整首退回手选色会显得"开关不生效"，这里补几次把窗口盖住。
const List<Duration> kCoverPaletteRetryDelays = <Duration>[
  Duration(milliseconds: 600),
  Duration(milliseconds: 1500),
  Duration(seconds: 3),
];

/// 当前曲目的封面调色板。
///
/// 以封面 URL 为键：同一首歌元数据刷新（例如封面补全）会重新取一次，换歌
/// 自然跟着换。拿不到就返回 null，调用方退回用户手选的主题色——不会让界面
/// 停在上一首的颜色上。
final coverPaletteProvider = FutureProvider<CoverPalette?>((ref) async {
  final url = ref.watch(
    currentMusicProvider.select((music) => music?.artwork ?? ''),
  );
  if (url.isEmpty) return null;
  final service = ref.watch(coverPaletteServiceProvider);
  for (var attempt = 0; ; attempt++) {
    final palette = await service.paletteFor(
      url,
      // 补试是同一首歌内部的主动重试，应该穿过失败冷却期。
      ignoreFailureCooldown: attempt > 0,
    );
    if (palette != null) return palette;
    if (attempt >= kCoverPaletteRetryDelays.length) return null;
    await Future<void>.delayed(kCoverPaletteRetryDelays[attempt]);
    // 期间换歌了：把结果让给新一次计算，别再往回写旧颜色。
    if (ref.read(currentMusicProvider)?.artwork != url) return null;
  }
});

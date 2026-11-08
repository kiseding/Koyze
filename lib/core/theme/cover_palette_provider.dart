import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/player/presentation/player_provider.dart';
import 'cover_palette.dart';

/// 封面取色服务（单例，带 URL 缓存）。
final coverPaletteServiceProvider = Provider<CoverPaletteService>((ref) {
  return CoverPaletteService.instance;
});

/// 当前曲目的封面调色板。
///
/// 以封面 URL 为键：同一首歌元数据刷新（例如封面补全）会重新取一次，换歌
/// 自然跟着换。拿不到就返回 null，调用方退回用户手选的主题色——不会让界面
/// 停在上一首的颜色上。
final coverPaletteProvider = FutureProvider<CoverPalette?>((ref) async {
  final music = ref.watch(currentMusicProvider);
  final url = music?.artwork ?? '';
  if (url.isEmpty) return null;
  return ref.watch(coverPaletteServiceProvider).paletteFor(url);
});

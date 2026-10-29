import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/radio_browser_client.dart';
import '../domain/radio_station.dart';

final radioBrowserClientProvider = Provider<RadioBrowserClient>(
  (ref) => RadioBrowserClient(),
);

/// 当前选中的风格标签；空串代表「热门」。
final radioTagProvider = StateProvider<String>((ref) => '');

/// 搜索框里的关键字。
final radioQueryProvider = StateProvider<String>((ref) => '');

/// 风格标签来源。Radio Browser 没有「热门标签」接口的稳定版本，这里用一组
/// 覆盖面广、跨语种都有内容的固定标签，避免首屏空白。
const List<String> kRadioTags = [
  'jazz',
  'classical',
  'electronic',
  'rock',
  'pop',
  'lofi',
  'news',
  'talk',
];

/// 电台列表：有关键字就搜、有标签就筛、都没有就拉热门。
final radioStationsProvider = FutureProvider.autoDispose<List<RadioStation>>((
  ref,
) async {
  final client = ref.watch(radioBrowserClientProvider);
  final query = ref.watch(radioQueryProvider).trim();
  final tag = ref.watch(radioTagProvider).trim();
  if (query.isNotEmpty) return client.search(query);
  if (tag.isNotEmpty) return client.byTag(tag);
  return client.popular();
});

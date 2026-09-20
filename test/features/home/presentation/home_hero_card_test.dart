import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/features/home/presentation/home_hero_card.dart';

void main() {
  test('defaults to favorites and select is exclusive', () {
    final notifier = HomeHeroCardNotifier();
    expect(notifier.state, HomeHeroCardId.favorites);

    notifier.select(HomeHeroCardId.local);
    expect(notifier.state, HomeHeroCardId.local);

    notifier.select(HomeHeroCardId.recommend);
    expect(notifier.state, HomeHeroCardId.recommend);
    expect(HomeHeroCardId.values.where((id) => id == notifier.state).length, 1);
  });

  test('selecting the current card is a no-op', () {
    final notifier = HomeHeroCardNotifier();
    notifier.select(HomeHeroCardId.favorites);
    expect(notifier.state, HomeHeroCardId.favorites);
  });

  test('tryParse accepts known ids only', () {
    expect(HomeHeroCardIdX.tryParse('nas'), HomeHeroCardId.nas);
    expect(HomeHeroCardIdX.tryParse('favorites'), HomeHeroCardId.favorites);
    expect(HomeHeroCardIdX.tryParse('nope'), isNull);
    expect(HomeHeroCardIdX.tryParse(''), isNull);
    expect(HomeHeroCardIdX.tryParse(null), isNull);
  });

  test('options match playlist tab cards in the same order', () {
    expect(homeHeroCardOptions.map((item) => item.title).toList(), [
      '收藏列表',
      '猜你喜欢',
      '本地音乐',
      'NAS 乐库',
      '最近播放',
    ]);
    expect(homeHeroCardOptions.map((item) => item.id).toSet().length, 5);
  });
}

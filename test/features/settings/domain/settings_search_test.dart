import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/features/settings/domain/settings_search.dart';

class _Target implements SettingsSearchTarget {
  const _Target(
    this.title, {
    this.sectionLabel = 'Playback',
    this.subtitle = '',
    this.keywords = const [],
  });

  @override
  final String title;

  @override
  final String sectionLabel;

  @override
  final String subtitle;

  @override
  final List<String> keywords;
}

List<String> _titles(List<_Target> hits) => [for (final hit in hits) hit.title];

void main() {
  const language = _Target('Language', sectionLabel: 'Appearance');
  const translate = _Target(
    'Translate',
    sectionLabel: 'Appearance',
    keywords: ['language'],
  );
  const darkMode = _Target(
    'Dark mode',
    sectionLabel: 'Appearance',
    keywords: ['night', '深色'],
  );
  const quality = _Target(
    'Audio quality',
    sectionLabel: 'Playback',
    subtitle: 'High (320 kbps)',
  );
  const downloadQuality = _Target(
    'Download quality',
    sectionLabel: 'Downloads',
  );
  const wifi = _Target('仅 Wi-Fi', sectionLabel: 'Downloads', keywords: ['流量']);
  final all = [language, translate, darkMode, quality, downloadQuality, wifi];

  test('empty query keeps every row in page order', () {
    expect(_titles(searchSettings(all, '')), _titles(all));
    expect(_titles(searchSettings(all, '   ')), _titles(all));
  });

  test('a row named exactly after the query outranks a keyword hit', () {
    expect(_titles(searchSettings(all, 'language')), ['Language', 'Translate']);
  });

  test('matching ignores case and punctuation', () {
    expect(_titles(searchSettings(all, 'wifi')), ['仅 Wi-Fi']);
    expect(_titles(searchSettings(all, 'DARK')), ['Dark mode']);
  });

  test('every token has to hit, so a second word narrows', () {
    expect(_titles(searchSettings(all, 'quality')), [
      'Audio quality',
      'Download quality',
    ]);
    expect(_titles(searchSettings(all, 'audio quality')), ['Audio quality']);
    expect(_titles(searchSettings(all, 'audio dark')), isEmpty);
  });

  test('chinese keywords reach the row they belong to', () {
    expect(_titles(searchSettings(all, '深色')), ['Dark mode']);
    expect(_titles(searchSettings(all, '流量')), ['仅 Wi-Fi']);
  });

  test('subtitle and section matches come last but still show up', () {
    expect(_titles(searchSettings(all, '320')), ['Audio quality']);
    // Section-only hits rank below the rows that carry the word themselves.
    expect(_titles(searchSettings(all, 'downloads')), [
      'Download quality',
      '仅 Wi-Fi',
    ]);
  });

  test('nothing matching returns an empty list', () {
    expect(searchSettings(all, '不存在'), isEmpty);
  });

  test('ties keep page order instead of resorting', () {
    const first = _Target('Alpha', keywords: ['shared']);
    const second = _Target('Beta', keywords: ['shared']);
    expect(_titles(searchSettings([first, second], 'shared')), [
      'Alpha',
      'Beta',
    ]);
  });
}

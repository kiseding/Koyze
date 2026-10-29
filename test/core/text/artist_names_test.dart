import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/text/artist_names.dart';

void main() {
  group('splitArtistNames', () {
    test('splits on explicit separators', () {
      expect(splitArtistNames('A;B'), ['A', 'B']);
      expect(splitArtistNames('A；B'), ['A', 'B']);
      expect(splitArtistNames('A、B'), ['A', 'B']);
      expect(splitArtistNames('A|B'), ['A', 'B']);
      expect(splitArtistNames('A｜B'), ['A', 'B']);
    });

    test('splits on a spaced slash only', () {
      expect(splitArtistNames('A / B'), ['A', 'B']);
      // 紧凑的斜杠多半是乐队名的一部分。
      expect(splitArtistNames('AC/DC'), ['AC/DC']);
      expect(splitArtistNames('A/B'), ['A/B']);
    });

    test('never splits on ampersands', () {
      expect(splitArtistNames('Simon & Garfunkel'), ['Simon & Garfunkel']);
      expect(splitArtistNames('A & B'), ['A & B']);
    });

    test('treats feat markers as separators', () {
      expect(splitArtistNames('A feat. B'), ['A', 'B']);
      expect(splitArtistNames('A ft. B'), ['A', 'B']);
      expect(splitArtistNames('A FEATURING B'), ['A', 'B']);
      // 不带空格的 "ft." 可能是名字的一部分，保持原样。
      expect(splitArtistNames('Gift.'), ['Gift.']);
    });

    test('trims, drops empties and dedupes case-insensitively', () {
      expect(splitArtistNames(' A ;; B ; A '), ['A', 'B']);
    });

    test('keeps original casing and order', () {
      expect(splitArtistNames('b;A;c'), ['b', 'A', 'c']);
    });

    test('returns a single entry when there is nothing to split', () {
      expect(splitArtistNames('Solo'), ['Solo']);
      expect(splitArtistNames('  周杰伦  '), ['周杰伦']);
    });

    test('returns an empty list for blank input', () {
      expect(splitArtistNames(''), isEmpty);
      expect(splitArtistNames('   '), isEmpty);
    });

    test('handles a realistic multi-artist line', () {
      expect(
        splitArtistNames('Calvin Harris; Dua Lipa / Young Thug feat. Pharrell'),
        ['Calvin Harris', 'Dua Lipa', 'Young Thug', 'Pharrell'],
      );
    });
  });

  test('artistNamesOf delegates to the same rules', () {
    expect(artistNamesOf('A;B'), splitArtistNames('A;B'));
  });
}

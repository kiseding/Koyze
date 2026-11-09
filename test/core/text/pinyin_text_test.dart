import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/text/pinyin_text.dart';

void main() {
  group('拼音转换', () {
    test('全拼', () {
      expect(PinyinText.full('周杰伦'), 'zhoujielun');
      expect(PinyinText.full('晴天'), 'qingtian');
    });

    test('首字母', () {
      expect(PinyinText.initials('周杰伦'), 'zjl');
      expect(PinyinText.initials('稻香'), 'dx');
    });

    test('词组按整体读音，不做单字拼接', () {
      // 「重」单字是 zhong，在「重庆」里读 chong。
      expect(PinyinText.full('重庆'), 'chongqing');
    });

    test('英文原样保留并小写', () {
      expect(PinyinText.full('Lemon'), 'lemon');
      expect(PinyinText.initials('Lemon'), 'lemon');
    });

    test('空串返回空', () {
      expect(PinyinText.full(''), '');
      expect(PinyinText.initials(''), '');
    });
  });

  group('排序', () {
    test('中文按读音比较，不按码值', () {
      expect(PinyinText.compare('稻香', '晴天'), lessThan(0));
      expect(PinyinText.compare('晴天', '稻香'), greaterThan(0));
    });

    test('中英混排时英文按字母插入', () {
      final titles = ['周杰伦', 'Apple', '爱', 'Lemon'];
      titles.sort(PinyinText.compare);
      expect(titles, ['爱', 'Apple', 'Lemon', '周杰伦']);
    });

    test('拼音相同的串退回原值比较，顺序稳定', () {
      expect(PinyinText.compare('abc', 'ABC'), greaterThan(0));
    });
  });

  group('归一化', () {
    test('全角转半角', () {
      expect(normalize('ＡＢＣ１２３'), 'abc123');
    });

    test('去掉首尾空白并小写', () {
      expect(normalize('  Lemon  '), 'lemon');
    });
  });
}

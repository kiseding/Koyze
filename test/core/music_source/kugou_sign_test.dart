import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/music_source/platform/kugou_sign.dart';

void main() {
  group('kugouSign', () {
    test('按参数名排序后拼 k=v，前后各套一次密钥', () {
      // md5('K' + 'a=1b=2' + 'B' + 'K')：顺序敏感，参数表再乱也不影响结果。
      expect(
        kugouSign('K', {'b': '2', 'a': '1'}, 'B'),
        'be981aad77b78ed10e8f931482e1aa68',
      );
      expect(
        kugouSign('K', {'a': '1', 'b': '2'}, 'B'),
        kugouSign('K', {'b': '2', 'a': '1'}, 'B'),
      );
    });

    test('没有 body 时等价于空串', () {
      expect(kugouSign('K', {'a': '1'}), kugouSign('K', {'a': '1'}, ''));
    });

    test('签名本身不参与计算，重复调用不会把上一次的结果算进去', () {
      final params = <String, String>{'a': '1', 'b': '2'};
      params['signature'] = kugouSign('K', params);
      final first = params['signature'];
      params['signature'] = kugouSign('K', params);

      expect(params['signature'], first);
    });

    test('网页登录用同一把密钥', () {
      const webKey = 'NVPh5oo715z5DIWAeQlhMDsWXXQV4hwt';
      expect(
        kugouSign(webKey, {'b': '2', 'a': '1'}),
        '70ccbef64fdcc9271fe883d1d7f07395',
      );
    });
  });

  test('kugouDeviceMid 是 32 位小写十六进制，且每次不同', () {
    final first = kugouDeviceMid();
    final second = kugouDeviceMid();

    expect(first, matches(RegExp(r'^[0-9a-f]{32}$')));
    expect(second, isNot(first));
  });
}

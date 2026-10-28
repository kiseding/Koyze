import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/features/car_mode/domain/car_connection.dart';

void main() {
  group('CarConnection.parse', () {
    test('recognises the two tokens the bridge sends', () {
      expect(CarConnection.parse('connected'), CarConnection.connected);
      expect(CarConnection.parse('disconnected'), CarConnection.disconnected);
    });

    test('anything it does not know becomes unsupported', () {
      // 宁可不切布局，也不要在不认识的设备上自作聪明。
      expect(CarConnection.parse('unsupported'), CarConnection.unsupported);
      expect(CarConnection.parse(null), CarConnection.unsupported);
      expect(CarConnection.parse(''), CarConnection.unsupported);
      expect(CarConnection.parse('CONNECTED'), CarConnection.unsupported);
      expect(CarConnection.parse(42), CarConnection.unsupported);
    });
  });

  test('only connected counts as connected', () {
    expect(CarConnection.connected.isConnected, isTrue);
    expect(CarConnection.disconnected.isConnected, isFalse);
    expect(CarConnection.unsupported.isConnected, isFalse);
  });

  test('a detached link reports its fixed value and then ends', () async {
    expect(
      await const DetachedCarLink().status.toList(),
      [CarConnection.unsupported],
    );
    expect(
      await const DetachedCarLink(CarConnection.connected).status.toList(),
      [CarConnection.connected],
    );
  });
}

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:koyze/features/car_mode/domain/car_connection.dart';
import 'package:koyze/features/car_mode/presentation/car_mode_provider.dart';
import 'package:koyze/core/storage/storage_service.dart';
import 'package:koyze/features/settings/presentation/settings_provider.dart';

/// 可控的连接源：测试里自己决定什么时候「连上车机」。
class _FakeCarLink implements CarLink {
  final StreamController<CarConnection> _controller =
      StreamController<CarConnection>.broadcast();

  @override
  Stream<CarConnection> get status => _controller.stream;

  void emit(CarConnection connection) => _controller.add(connection);

  void fail(Object error) => _controller.addError(error);

  Future<void> dispose() => _controller.close();
}

class _FixedConnection extends CarConnectionNotifier {
  _FixedConnection(this._value);

  final CarConnection _value;

  @override
  CarConnection build() => _value;
}

class _FixedPreference extends CarModePreferenceNotifier {
  _FixedPreference(this._value);

  final CarModePreference _value;

  @override
  CarModePreference build() => _value;
}

class _FixedLandscape extends ForceLandscapeNotifier {
  _FixedLandscape(this._value);

  final bool _value;

  @override
  bool build() => _value;
}

/// 每个用例拿一份新的 StorageService：单例缓存的是旧 SharedPreferences，
/// 会带着上一个用例写进去的值。
Future<StorageService> _freshStorage() async =>
    StorageService.forTesting(await SharedPreferences.getInstance());

ProviderContainer _container({
  CarConnection connection = CarConnection.unsupported,
  CarModePreference preference = CarModePreference.auto,
  bool forceLandscape = false,
}) {
  final container = ProviderContainer(
    overrides: [
      carConnectionProvider.overrideWith(() => _FixedConnection(connection)),
      carModePreferenceProvider.overrideWith(() => _FixedPreference(preference)),
      forceLandscapeProvider.overrideWith(() => _FixedLandscape(forceLandscape)),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CarModePreference', () {
    test('defaults to auto for missing or unknown values', () {
      expect(CarModePreference.parse(null), CarModePreference.auto);
      expect(CarModePreference.parse('nope'), CarModePreference.auto);
      expect(CarModePreference.parse(''), CarModePreference.auto);
    });

    test('round-trips its own names', () {
      for (final value in CarModePreference.values) {
        expect(CarModePreference.parse(value.name), value);
      }
    });
  });

  group('preference storage', () {
    test('reads the stored value', () async {
      SharedPreferences.setMockInitialValues({
        CarModePreference.storageKey: 'always',
      });
      final notifier = CarModePreferenceNotifier(storage: _freshStorage);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(notifier.value, CarModePreference.always);
    });

    test('a missing key keeps the default', () async {
      SharedPreferences.setMockInitialValues({});
      final notifier = CarModePreferenceNotifier(storage: _freshStorage);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(notifier.value, CarModePreference.auto);
    });

    test('set writes through', () async {
      SharedPreferences.setMockInitialValues({});
      final notifier = CarModePreferenceNotifier(storage: _freshStorage);
      await notifier.set(CarModePreference.off);
      expect(notifier.value, CarModePreference.off);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(CarModePreference.storageKey), 'off');
    });
  });

  group('carModeActive', () {
    test('off never activates, even when the head unit is connected', () {
      final container = _container(
        connection: CarConnection.connected,
        preference: CarModePreference.off,
      );
      expect(container.read(carModeActiveProvider), isFalse);
    });

    test('always activates without a connection', () {
      final container = _container(preference: CarModePreference.always);
      expect(container.read(carModeActiveProvider), isTrue);
    });

    test('auto follows the connection', () {
      expect(
        _container(
          connection: CarConnection.connected,
        ).read(carModeActiveProvider),
        isTrue,
      );
      expect(
        _container(
          connection: CarConnection.disconnected,
        ).read(carModeActiveProvider),
        isFalse,
      );
    });

    test('auto stays off when the device has no Car Kit', () {
      final container = _container();
      expect(container.read(carModeActiveProvider), isFalse);
    });
  });

  group('landscapeShell', () {
    test('either the manual switch or car mode turns it on', () {
      expect(
        _container(forceLandscape: true).read(landscapeShellProvider),
        isTrue,
      );
      expect(
        _container(preference: CarModePreference.always)
            .read(landscapeShellProvider),
        isTrue,
      );
    });

    test('off and disconnected leave the normal shell alone', () {
      expect(
        _container(preference: CarModePreference.off)
            .read(landscapeShellProvider),
        isFalse,
      );
      expect(_container().read(landscapeShellProvider), isFalse);
    });
  });

  group('CarConnectionNotifier', () {
    test('starts unsupported and follows the link', () async {
      final link = _FakeCarLink();
      addTearDown(link.dispose);
      final container = ProviderContainer(
        overrides: [carLinkProvider.overrideWithValue(link)],
      );
      addTearDown(container.dispose);

      expect(container.read(carConnectionProvider), CarConnection.unsupported);

      link.emit(CarConnection.connected);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(carConnectionProvider), CarConnection.connected);

      link.emit(CarConnection.disconnected);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(carConnectionProvider), CarConnection.disconnected);
    });

    test('a channel error degrades to unsupported instead of throwing', () async {
      final link = _FakeCarLink();
      addTearDown(link.dispose);
      final container = ProviderContainer(
        overrides: [carLinkProvider.overrideWithValue(link)],
      );
      addTearDown(container.dispose);

      link.emit(CarConnection.connected);
      await Future<void>.delayed(Duration.zero);
      link.fail(StateError('bridge died'));
      await Future<void>.delayed(Duration.zero);

      expect(container.read(carConnectionProvider), CarConnection.unsupported);
    });
  });
}

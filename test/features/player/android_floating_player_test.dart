import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/features/player/platform/android_floating_player.dart';

void main() {
  test('floating player only shows for an enabled background track', () {
    expect(
      shouldShowAndroidFloatingPlayer(
        enabled: true,
        permissionGranted: true,
        inBackground: true,
        hasTrack: true,
        dismissed: false,
      ),
      isTrue,
    );
    expect(
      shouldShowAndroidFloatingPlayer(
        enabled: false,
        permissionGranted: true,
        inBackground: true,
        hasTrack: true,
        dismissed: false,
      ),
      isFalse,
    );
    expect(
      shouldShowAndroidFloatingPlayer(
        enabled: true,
        permissionGranted: true,
        inBackground: false,
        hasTrack: true,
        dismissed: false,
      ),
      isFalse,
    );
    expect(
      shouldShowAndroidFloatingPlayer(
        enabled: true,
        permissionGranted: false,
        inBackground: true,
        hasTrack: true,
        dismissed: false,
      ),
      isFalse,
    );
    expect(
      shouldShowAndroidFloatingPlayer(
        enabled: true,
        permissionGranted: true,
        inBackground: true,
        hasTrack: false,
        dismissed: false,
      ),
      isFalse,
    );
    expect(
      shouldShowAndroidFloatingPlayer(
        enabled: true,
        permissionGranted: true,
        inBackground: true,
        hasTrack: true,
        dismissed: true,
      ),
      isFalse,
    );
  });
}

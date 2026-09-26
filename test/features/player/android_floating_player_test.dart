import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/features/player/platform/android_floating_player.dart';

void main() {
  test('floating player colors follow the app theme', () {
    expect(
      floatingPlayerFollowsDarkTheme(
        mode: ThemeMode.dark,
        platformBrightness: Brightness.light,
      ),
      isTrue,
    );
    expect(
      floatingPlayerFollowsDarkTheme(
        mode: ThemeMode.light,
        platformBrightness: Brightness.dark,
      ),
      isFalse,
    );
    expect(
      floatingPlayerFollowsDarkTheme(
        mode: ThemeMode.system,
        platformBrightness: Brightness.dark,
      ),
      isTrue,
    );
  });

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

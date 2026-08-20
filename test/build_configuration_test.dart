import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('root toolchain requirements match the supported Flutter release', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();

    expect(pubspec, contains("sdk: '>=3.12.0 <4.0.0'"));
    expect(pubspec, contains("flutter: '>=3.44.0'"));
  });

  test('platform workflows use the same pinned Flutter patch release', () {
    for (final platform in ['android', 'ios', 'windows']) {
      final workflow = File(
        '.github/workflows/build-$platform.yml',
      ).readAsStringSync();
      expect(workflow, contains("flutter-version: '3.44.9'"), reason: platform);
      expect(
        RegExp(r"flutter-version: '([^']+)'").allMatches(workflow),
        hasLength(1),
        reason: platform,
      );
    }
  });

  test('official build workflow actions are pinned to full SHAs', () {
    for (final platform in ['android', 'ios', 'windows']) {
      final workflow = File(
        '.github/workflows/build-$platform.yml',
      ).readAsStringSync();
      for (final action in ['actions/checkout', 'actions/upload-artifact']) {
        expect(
          RegExp(
            'uses: $action@[0-9a-f]{40}\\s+# v[0-9]+\\.[0-9]+\\.[0-9]+',
          ).hasMatch(workflow),
          isTrue,
          reason: '$platform $action',
        );
      }
    }
    final android = File(
      '.github/workflows/build-android.yml',
    ).readAsStringSync();
    expect(
      RegExp(
        r'uses: actions/setup-java@[0-9a-f]{40}\s+# v[0-9]+\.[0-9]+\.[0-9]+',
      ).hasMatch(android),
      isTrue,
    );
  });

  test('build workflows use the reviewed Flutter action major', () {
    for (final platform in ['android', 'ios', 'windows']) {
      final workflow = File(
        '.github/workflows/build-$platform.yml',
      ).readAsStringSync();
      expect(
        RegExp(
          r'uses: subosito/flutter-action@v2\s*$',
          multiLine: true,
        ).allMatches(workflow),
        hasLength(1),
        reason: platform,
      );
    }
  });

  test('iOS CI gates the build on analysis and deterministic tests', () {
    final workflow = File('.github/workflows/build-ios.yml').readAsStringSync();
    final analyze = workflow.indexOf('run: flutter analyze --no-fatal-infos');
    final test = workflow.indexOf('run: flutter test --exclude-tags live');
    final build = workflow.indexOf('run: flutter build ios');

    expect(analyze, greaterThanOrEqualTo(0));
    expect(test, greaterThan(analyze));
    expect(build, greaterThan(test));
  });

  test('iOS CI publishes only the Apple ID sideload IPA', () {
    final workflow = File('.github/workflows/build-ios.yml').readAsStringSync();

    expect(workflow, contains('Koyze-Apple-ID-Sideload.ipa'));
    expect(workflow, contains('Koyze-Apple-ID-Sideload-IPA'));
    expect(
      workflow,
      contains("rm -rf build/ios/ipa-sideload/Payload/Runner.app/PlugIns"),
    );
    expect(workflow, isNot(contains('Koyze-unsigned.ipa')));
    expect(workflow, isNot(contains('Koyze-unsigned-IPA')));
  });

  test('iOS source transport completes each Flutter result only once', () {
    final appDelegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();

    expect(appDelegate, contains('private final class FlutterResultGate'));
    expect(appDelegate, contains('guard !completed else'));
    expect(appDelegate, contains('resultGate.complete('));
    expect(appDelegate, contains('bytes[10] == 0xff'));
    expect(appDelegate, contains('Self.isPrivateIPv4(bytes[12], bytes[13])'));
  });

  test('Workers deployment does not print the login token response', () {
    final workflow = File(
      '.github/workflows/deploy-workers.yml',
    ).readAsStringSync();

    expect(workflow, isNot(contains('cat /tmp/login.json')));
    expect(workflow, contains("TOKEN=\"\$(jq -er '.token' /tmp/login.json)\""));
  });

  test('Windows CI validates and publishes a complete portable bundle', () {
    final workflow = File(
      '.github/workflows/build-windows.yml',
    ).readAsStringSync();
    final analyze = workflow.indexOf('run: flutter analyze --no-fatal-infos');
    final test = workflow.indexOf(
      'run: flutter test test/build_configuration_test.dart',
    );
    final build = workflow.indexOf('run: flutter build windows --release');

    expect(analyze, greaterThanOrEqualTo(0));
    expect(test, greaterThan(analyze));
    expect(build, greaterThan(test));
    expect(workflow, contains('quickjs_c_bridge.dll'));
    expect(workflow, contains('Koyze-Windows-x64.zip'));
  });

  test('Windows playback skips silence keepalive and proxies headers', () {
    final handler = File(
      'lib/core/audio/audio_handler.dart',
    ).readAsStringSync();

    expect(handler, contains('useSilenceKeepalive'));
    expect(handler, contains('!Platform.isWindows'));
    expect(handler, contains('useProxyForRequestHeaders: Platform.isWindows'));
  });

  test('Windows close uses themed Flutter dialog and single instance', () {
    final runner = File('windows/runner/win32_window.cpp').readAsStringSync();
    final main = File('windows/runner/main.cpp').readAsStringSync();
    final cmake = File('windows/runner/CMakeLists.txt').readAsStringSync();
    final handler = File(
      'lib/core/windows/windows_close_handler.dart',
    ).readAsStringSync();

    expect(runner, contains('case WM_CLOSE'));
    expect(runner, isNot(contains('MessageBoxW')));
    expect(runner, contains('Shell_NotifyIconW(NIM_ADD'));
    expect(runner, contains('Shell_NotifyIconW(NIM_DELETE'));
    expect(runner, contains('ShowWindow(window_handle_, SW_HIDE)'));
    expect(runner, contains('RestoreFromTray'));
    expect(main, contains('CreateMutexW'));
    expect(main, contains('ERROR_ALREADY_EXISTS'));
    expect(main, contains('Koyze.RestoreInstance'));
    expect(handler, contains("MethodChannel('koyze/window')"));
    expect(handler, contains('showDialog<_CloseSelection>'));
    expect(handler, contains('下次不再询问'));
    expect(handler, contains("'windows_close_action'"));
    expect(cmake, contains('"shell32.lib"'));
    expect(cmake, contains('PRIVATE "/utf-8"'));
  });

  test('Android CI requires signing and publishes verified APKs and AAB', () {
    final workflow = File(
      '.github/workflows/build-android.yml',
    ).readAsStringSync();
    final analyze = workflow.indexOf('run: flutter analyze --no-fatal-infos');
    final test = workflow.indexOf('run: flutter test --exclude-tags live');
    final build = workflow.indexOf('flutter build apk --release');
    final signingCheck = workflow.indexOf(
      'name: Require Android release signing secrets',
    );

    expect(analyze, greaterThanOrEqualTo(0));
    expect(test, greaterThan(analyze));
    expect(build, greaterThan(test));
    expect(signingCheck, greaterThanOrEqualTo(0));
    expect(signingCheck, lessThan(analyze));
    expect(workflow, contains('--split-per-abi'));
    expect(workflow, contains('app-arm64-v8a-release.apk'));
    expect(workflow, contains('app-armeabi-v7a-release.apk'));
    expect(workflow, contains('app-x86_64-release.apk'));
    expect(workflow, contains('Koyze-Android-APKs'));
    expect(workflow, contains('flutter build appbundle --release'));
    expect(workflow, contains('app-release.aab'));
    expect(workflow, contains('Koyze-Android-AAB'));
    expect(workflow, contains('ANDROID_KEYSTORE_BASE64'));
    expect(workflow, isNot(contains('ANDROID_KEYSTORE_BASE64 !=')));
    expect(workflow, contains('Verify Android release signatures'));
    expect(workflow, contains('apksigner" verify'));
    expect(workflow, contains('zipalign" -c -P 16 -v 4'));
    expect(workflow, contains('jarsigner -verify -certs'));
  });

  test('Android host declares background media playback support', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final activity = File(
      'android/app/src/main/kotlin/com/koyze/app/MainActivity.kt',
    ).readAsStringSync();

    expect(manifest, contains('android.permission.INTERNET'));
    expect(manifest, contains('FOREGROUND_SERVICE_MEDIA_PLAYBACK'));
    expect(manifest, contains('android.permission.POST_NOTIFICATIONS'));
    expect(manifest, contains('READ_MEDIA_AUDIO'));
    expect(manifest, contains('READ_EXTERNAL_STORAGE'));
    expect(manifest, contains('android:foregroundServiceType="mediaPlayback"'));
    expect(manifest, contains('android:stopWithTask="false"'));
    expect(manifest, contains('android:allowBackup="false"'));
    expect(
      manifest,
      contains('android:dataExtractionRules="@xml/data_extraction_rules"'),
    );
    expect(manifest, contains('android:fullBackupContent="@xml/backup_rules"'));
    expect(activity, contains('AudioServiceActivity'));
    final main = File('lib/main.dart').readAsStringSync();
    expect(main, contains('Permission.notification.request()'));
    expect(main, contains('androidStopForegroundOnPause: false'));
    expect(main, contains('androidNotificationOngoing: false'));
    final iosInfo = File('ios/Runner/Info.plist').readAsStringSync();
    expect(iosInfo, contains('<key>UIBackgroundModes</key>'));
    expect(iosInfo, contains('<string>audio</string>'));
  });

  test('Android host aligns the legacy flutter_js Kotlin target', () {
    final build = File('android/build.gradle.kts').readAsStringSync();

    expect(build, contains('if (name == "flutter_js")'));
    expect(build, contains('JvmTarget.JVM_11'));
    expect(
      build,
      contains('pluginManager.apply("org.jetbrains.kotlin.android")'),
    );
    expect(build, contains('JvmTarget.JVM_17'));
  });

  test('Android release disables R8 for runtime plugin compatibility', () {
    final build = File('android/app/build.gradle.kts').readAsStringSync();

    expect(build, contains('rootProject.file("key.properties")'));
    expect(
      build,
      contains('providers.gradleProperty("allowDebugReleaseSigning")'),
    );
    expect(build, contains('requestsRelease && !hasReleaseSigning'));
    expect(
      build,
      contains('allowDebugReleaseSigning -> signingConfigs.getByName("debug")'),
    );
    expect(build, contains('isMinifyEnabled = false'));
    expect(build, contains('isShrinkResources = false'));
    expect(build, isNot(contains('proguardFiles(')));
  });

  test('Android backup policy excludes all application data', () {
    final legacy = File(
      'android/app/src/main/res/xml/backup_rules.xml',
    ).readAsStringSync();
    final modern = File(
      'android/app/src/main/res/xml/data_extraction_rules.xml',
    ).readAsStringSync();

    for (final domain in [
      'root',
      'file',
      'database',
      'sharedpref',
      'external',
    ]) {
      expect(legacy, contains('<exclude domain="$domain" path="." />'));
      expect(modern, contains('<exclude domain="$domain" path="." />'));
    }
    expect(modern, contains('<cloud-backup'));
    expect(modern, contains('<device-transfer>'));
  });

  test('Widget Extension inherits Flutter build name and number', () {
    final project = File(
      'ios/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();
    final widgetConfigurations = RegExp(
      r'AA000000000000000000000[DEF] /\* (?:Debug|Release|Profile) \*/ = \{'
      r'.*?CURRENT_PROJECT_VERSION = "\$\(FLUTTER_BUILD_NUMBER\)";'
      r'.*?MARKETING_VERSION = "\$\(FLUTTER_BUILD_NAME\)";',
      dotAll: true,
    ).allMatches(project);

    expect(widgetConfigurations, hasLength(3));
  });
}

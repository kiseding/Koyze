import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('root toolchain requirements match the supported Flutter release', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();

    expect(pubspec, contains("sdk: '>=3.12.0 <4.0.0'"));
    expect(pubspec, contains("flutter: '>=3.44.0'"));
  });

  test('built-in platforms never resolve audio urls', () {
    final dir = Directory('lib/core/music_source/platform');
    final files = dir
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .toList();

    expect(files, isNotEmpty);

    // 本项目不内置任何音源。内置平台只允许提供元数据，一旦这些实现被加回来，
    // 就等于把音频分发能力重新打包进应用。
    const forbidden = [
      'getMusicUrl(',
      'trackercdn.kugou.com',
      'fcg_music_express',
      'antiserver.kuwo.cn',
      'enhance/player/url',
      'getSongInfo.php',
    ];
    for (final file in files) {
      final source = file.readAsStringSync();
      for (final token in forbidden) {
        expect(
          source.contains(token),
          isFalse,
          reason: '${file.path} 不应包含内置音频取址实现（$token）',
        );
      }
    }
  });

  test('settings about row reads the single version constant', () {
    final settings = File(
      'lib/features/settings/presentation/settings_screen.dart',
    ).readAsStringSync();
    final strings = File('lib/l10n/app_strings.dart').readAsStringSync();
    expect(strings, contains('_l10n.version'));

    // 版本号只在 lib/core/app_version.dart 里写一次（具体数值与 pubspec 的
    // 一致性由 test/core/app_version_test.dart 钉住），设置页引用常量而不是
    // 再硬编码一份字符串，否则发版时两处会不同步。
    expect(settings, contains('name: s.version, value: kAppVersionLabel'));
    expect(settings, isNot(contains(RegExp(r"value: 'v[0-9]+\\.[0-9]+"))));
    // Copy moved to ARB in the l10n migration. Assert the pair exists in the
    // ARB source of truth instead of grepping the facade for a ternary.
    expect(
      File('lib/l10n/app_en.arb').readAsStringSync(),
      contains('"version"'),
    );
    expect(
      File('lib/l10n/app_zh.arb').readAsStringSync(),
      contains('"version": "版本"'),
    );
  });

  test('platform workflows use the same pinned Flutter patch release', () {
    for (final platform in ['android', 'ios', 'linux', 'macos', 'windows']) {
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
    for (final platform in ['android', 'ios', 'linux', 'macos', 'windows']) {
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
    for (final platform in ['android', 'ios', 'linux', 'macos', 'windows']) {
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

  test('iOS CI gates the build on analysis and build config', () {
    final workflow = File('.github/workflows/build-ios.yml').readAsStringSync();
    final analyze = workflow.indexOf('run: flutter analyze --no-fatal-infos');
    final config = workflow.indexOf(
      'run: flutter test test/build_configuration_test.dart',
    );
    final build = workflow.indexOf('run: flutter build ios');

    expect(analyze, greaterThanOrEqualTo(0));
    expect(config, greaterThan(analyze));
    expect(build, greaterThan(config));
  });

  test('iOS CI leaves the full suite to the quality gate', () {
    // 全量测试只在 quality.yml 跑（分片）。iOS 那次单片串行在 macOS 上要
    // 751s，而 macOS 并不补上 Linux 测不到的覆盖——平台相关断言只有
    // platform_defaults_test 那一处，它在两个宿主上验证的是同一个表达式。
    // 别把这行加回去：加了就等于让每次 push 多花 12 分钟重跑一遍已有的结果。
    final workflow = File('.github/workflows/build-ios.yml').readAsStringSync();

    expect(workflow, isNot(contains('flutter test --exclude-tags live')));
  });

  test('iOS CI publishes only the Apple ID sideload IPA', () {
    final workflow = File('.github/workflows/build-ios.yml').readAsStringSync();

    expect(workflow, contains('Koyze-Apple-ID-Sideload.ipa'));
    expect(workflow, contains('Koyze-Apple-ID-Sideload-IPA'));
    expect(
      workflow,
      contains('rm -rf build/ios/ipa-sideload/Payload/Runner.app/PlugIns'),
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

  test('HarmonyOS HAP validation requires ABI-matched QuickJS libraries', () {
    for (final workflowName in [
      '.github/workflows/build-harmonyos-online.yml',
    ]) {
      final workflow = File(workflowName).readAsStringSync();
      expect(workflow, contains('libs/arm64-v8a/libquickjs_c_bridge.so'));
      expect(workflow, contains('libs/arm64-v8a/libc++_shared.so'));
      expect(workflow, contains('libs/x86_64/libquickjs_c_bridge.so'));
      expect(workflow, contains('libs/x86_64/libc++_shared.so'));
      expect(workflow, contains("'quickjs':"));
      expect(workflow, contains("'cxx':"));
    }

    final vendored = File(
      'third_party/flutter_js/VENDORED.md',
    ).readAsStringSync();
    expect(vendored, contains('x86_64/libquickjs_c_bridge.so'));
    expect(vendored, contains('x86_64/libc++_shared.so'));
  });

  test('HarmonyOS CI restores the prebuilt libmpv after wiping entry/libs', () {
    final workflow = File(
      '.github/workflows/build-harmonyos-online.yml',
    ).readAsStringSync();

    // `ohos/entry/libs` 是构建输出目录，切换架构前会被整个删掉。预编译的
    // libmpv 放在 third_party 下，必须在删完之后、构建之前重新铺回去——
    // 漏了这一步 HAP 里就没有 libmpv.so，而且**不会有任何报错**，只是
    // 播放引擎静默退回 just_audio。
    final wipe = workflow.indexOf(
      'rm -rf build/ohos ohos/entry/build ohos/entry/libs',
    );
    expect(wipe, isNonNegative);
    final stage = workflow.indexOf('scripts/ohos/stage-libmpv.sh');
    expect(stage, greaterThan(wipe));

    // 最终 HAP 的内容校验必须点名 libmpv，否则上面那步被删掉也没人发现。
    expect(workflow, contains("'mpv': ('libs/arm64-v8a/libmpv.so', 183)"));

    // 预编译库本体要在仓库里，CI 才能铺得回去。
    expect(
      File('third_party/ohos-libmpv/arm64-v8a/libmpv.so').existsSync(),
      isTrue,
    );
    // 缺了它 libmpv 连加载都过不了，必须同目录携带。
    expect(
      File('third_party/ohos-libmpv/arm64-v8a/libc++_shared.so').existsSync(),
      isTrue,
    );
  });

  test('HarmonyOS CI pins a self-consistent engine/Dart toolchain', () {
    final online = File(
      '.github/workflows/build-harmonyos-online.yml',
    ).readAsStringSync();

    // 引擎工件只在 tag 3.44.9+ohos-0.0.1-canary1（har revision 7c82f544）上
    // 完整；分支 HEAD 已换成只有 artifacts.zip 的 revision，按分支拉会缺
    // AOT 生成器，所以必须按 tag 锁定。
    expect(
      online,
      contains('FLUTTER_OHOS_REF: 3.44.9+ohos-0.0.1-canary1'),
    );
    expect(online, contains(r'-b "$FLUTTER_OHOS_REF"'));

    for (final workflowName in [
      '.github/workflows/build-harmonyos-online.yml',
    ]) {
      final workflow = File(workflowName).readAsStringSync();

      // 绝不能用 dart-sdk 的通用 gen_snapshot 顶替 ohos 专用生成器：那会产出
      // libflutter.so(3.12.2) + libapp.so(3.13.x) 的包，安装后报
      // "VM snapshot invalid and could not be inferred from settings"。
      expect(workflow, isNot(contains('sdk_snapshot')));

      // 引擎 VM 版本与 AOT 生成器版本必须一致，且最终 HAP 还要再查一次。
      expect(workflow, contains('libflutter.so'));
      expect(workflow, contains('VM snapshot invalid'));
      expect(workflow, contains('windows_simarm64'));
      expect(workflow, contains('windows_x64'));
    }
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

  test('Linux CI validates and publishes a complete portable bundle', () {
    final workflow = File(
      '.github/workflows/build-linux.yml',
    ).readAsStringSync();
    final analyze = workflow.indexOf('run: flutter analyze --no-fatal-infos');
    final test = workflow.indexOf(
      'run: flutter test test/build_configuration_test.dart',
    );
    final build = workflow.indexOf('run: flutter build linux --release');

    expect(analyze, greaterThanOrEqualTo(0));
    expect(test, greaterThan(analyze));
    expect(build, greaterThan(test));
    expect(workflow, contains('libgtk-3-dev'));
    expect(workflow, contains('libsecret-1-dev'));
    expect(workflow, contains('libflutter_js_plugin.so'));
    expect(workflow, contains('data/app_icon.png'));
    expect(workflow, contains('Koyze-Linux-x64.tar.gz'));
    expect(
      File('linux/CMakeLists.txt').readAsStringSync(),
      contains('APPLICATION_ID "com.koyze.app"'),
    );
  });

  test('macOS CI validates and publishes an unsigned app archive', () {
    final workflow = File(
      '.github/workflows/build-macos.yml',
    ).readAsStringSync();
    final analyze = workflow.indexOf('run: flutter analyze --no-fatal-infos');
    final test = workflow.indexOf(
      'run: flutter test test/build_configuration_test.dart',
    );
    final build = workflow.indexOf('run: flutter build macos --release');

    expect(analyze, greaterThanOrEqualTo(0));
    expect(test, greaterThan(analyze));
    expect(build, greaterThan(test));
    expect(workflow, contains('Koyze.app'));
    expect(workflow, contains('Koyze-macOS.zip'));
    expect(
      File('macos/Runner/Release.entitlements').readAsStringSync(),
      contains('com.apple.security.network.client'),
    );
    expect(
      File('macos/Runner/Configs/AppInfo.xcconfig').readAsStringSync(),
      contains('PRODUCT_BUNDLE_IDENTIFIER = com.koyze.app'),
    );
  });

  test('Windows playback skips silence keepalive and proxies headers', () {
    final handler = File(
      'lib/core/audio/audio_handler.dart',
    ).readAsStringSync();

    expect(handler, contains('useSilenceKeepalive'));
    // Host-derived defaults now live in one seam so tests can pin them; the
    // production values must still come from the platform.
    // 静音保活只对 Apple 平台有意义：just_audio_windows 不支持，鸿蒙移植
    // 也没有实现 silence 源类型（会直接抛 Unknown AudioSource type）。
    expect(
      handler,
      contains('useSilenceKeepalive: Platform.isIOS || Platform.isMacOS'),
    );
    expect(handler, contains('streamLocalFiles: Platform.isWindows'));
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
    expect(handler, contains('showKoyzeDialog<_CloseSelection>'));
    expect(handler, contains('下次不再询问'));
    expect(handler, contains("'windows_close_action'"));
    expect(cmake, contains('"shell32.lib"'));
    expect(cmake, contains('PRIVATE "/utf-8"'));
  });

  test('Windows title bar is an immersive client caption', () {
    final runner = File('windows/runner/win32_window.cpp').readAsStringSync();
    final mainCpp = File('windows/runner/main.cpp').readAsStringSync();
    final channel = File(
      'windows/runner/flutter_window.cpp',
    ).readAsStringSync();
    final bar = File(
      'lib/core/windows/windows_caption_bar.dart',
    ).readAsStringSync();
    final app = File('lib/app.dart').readAsStringSync();
    final close = File(
      'lib/core/windows/windows_close_handler.dart',
    ).readAsStringSync();

    expect(runner, contains('WM_NCCALCSIZE'));
    expect(runner, contains('DwmExtendFrameIntoClientArea'));
    expect(runner, contains('DWMWA_COLOR_NONE'));
    expect(
      runner,
      contains(
        'style &= ~(WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX | WS_MAXIMIZEBOX)',
      ),
    );
    expect(runner, contains('case WM_ERASEBKGND:'));
    expect(runner, contains('SWP_FRAMECHANGED'));
    expect(runner, contains('kCornerRadiusDip = 24'));
    expect(runner, contains('CreateRoundRectRgn'));
    expect(bar, contains('EdgeInsets.only(top: 8, right: 16)'));
    expect(runner, contains('HTTRANSPARENT'));
    expect(runner, contains('WM_NCUAHDRAWCAPTION'));
    expect(runner, contains('DWMWA_CAPTION_COLOR'));
    expect(runner, contains('DWMNCRP_DISABLED'));
    expect(runner, contains('const MARGINS margins = {0, 0, 0, 0}'));
    expect(mainCpp, contains('kImmersiveCaptionHeight = 40'));
    expect(mainCpp, contains('kNonClientHeight = 0'));
    expect(channel, contains('startDragging'));
    expect(channel, contains('toggleMaximize'));
    expect(channel, contains('closeWindow'));
    expect(channel, contains('"windowState"'));
    expect(bar, contains('barHeight = 40'));
    expect(bar, contains('windowsCaptionMaximized'));
    expect(app, contains('WindowsCaptionFrame'));
    expect(close, contains('applyWindowsWindowState'));
  });

  test('Android CI requires signing and publishes verified APKs', () {
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
    expect(workflow, contains('Koyze-\${version}-\${abi}.apk'));
    expect(workflow, contains('for apk in build/android-release/*.apk'));
    expect(workflow, contains('Koyze-Android-APKs'));
    expect(workflow, isNot(contains('flutter build appbundle')));
    expect(workflow, isNot(contains('.aab')));
    expect(workflow, isNot(contains('Koyze-Android-AAB')));
    expect(workflow, contains('ANDROID_KEYSTORE_BASE64'));
    expect(workflow, isNot(contains('ANDROID_KEYSTORE_BASE64 !=')));
    expect(workflow, contains('Verify Android release signatures'));
    expect(workflow, contains('apksigner" verify'));
    expect(workflow, contains('zipalign" -c -P 16 -v 4'));
    expect(workflow, isNot(contains('jarsigner')));
  });

  test('Android Gradle prefers GCS Maven Central to avoid CI 429s', () {
    final init = File('android/init.gradle').readAsStringSync();
    final properties = File('android/gradle.properties').readAsStringSync();
    final settings = File('android/settings.gradle.kts').readAsStringSync();
    final workflow = File(
      '.github/workflows/build-android.yml',
    ).readAsStringSync();

    const gcsMirror = 'maven-central.storage-download.googleapis.com/maven2';
    expect(init, contains('beforeSettings'));
    expect(init, contains(gcsMirror));
    expect(init, contains('gradlePluginPortal()'));
    expect(init, contains('google()'));
    expect(
      init.indexOf(gcsMirror),
      lessThan(init.indexOf('gradlePluginPortal()')),
    );
    expect(init, contains("setUrl('https://$gcsMirror/')"));
    expect(init, isNot(contains('url = gcsMavenCentral')));
    expect(init, isNot(contains('repo.url =')));
    expect(init, isNot(contains('kotlin-dsl')));
    expect(
      properties,
      contains('org.gradle.internal.repository.max.tentatives=10'),
    );
    expect(settings, contains(gcsMirror));
    expect(
      settings.indexOf(gcsMirror),
      lessThan(settings.indexOf('mavenCentral()')),
    );
    expect(workflow, contains('android/init.gradle'));
    expect(workflow, contains('.gradle/init.d'));
    expect(workflow, contains('cache: gradle'));
    final installInit = workflow.indexOf('.gradle/init.d');
    final build = workflow.indexOf('flutter build apk --release');
    expect(installInit, greaterThanOrEqualTo(0));
    expect(installInit, lessThan(build));
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
    expect(manifest, contains('MANAGE_EXTERNAL_STORAGE'));
    expect(activity, contains('scanMediaStore'));
    expect(activity, contains('scanSelectedDirectory'));
    expect(activity, contains('isExternalStorageManager'));
    expect(activity, contains('isIgnoringBatteryOptimizations'));
    expect(activity, contains('openBatteryOptimizationSettings'));
    expect(activity, contains('pendingImportedAudio'));
    expect(activity, contains('ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS'));
    expect(activity, contains('ACTION_OPEN_DOCUMENT_TREE'));
    expect(activity, contains('Intent.ACTION_VIEW'));
    expect(manifest, contains('android.intent.action.VIEW'));
    expect(manifest, contains('android:mimeType="audio/*"'));
    expect(manifest, contains('android:scheme="content"'));
    expect(manifest, contains('android:foregroundServiceType="mediaPlayback"'));
    expect(manifest, contains('android:stopWithTask="false"'));
    expect(manifest, contains('android:allowBackup="false"'));
    expect(
      manifest,
      contains('android:dataExtractionRules="@xml/data_extraction_rules"'),
    );
    expect(manifest, contains('android:fullBackupContent="@xml/backup_rules"'));
    expect(activity, contains('AudioServiceActivity'));
    final localMusic = File(
      'lib/features/local_music/presentation/local_music_screen.dart',
    ).readAsStringSync();
    expect(localMusic, contains('writeTags'));
    expect(
      File('lib/l10n/app_zh.arb').readAsStringSync(),
      contains('注入tag（实验性）'),
    );
    final main = File('lib/main.dart').readAsStringSync();
    expect(main, contains('Permission.notification.request()'));
    expect(main, contains('androidStopForegroundOnPause: false'));
    expect(main, contains('androidNotificationOngoing: false'));
    final iosInfo = File('ios/Runner/Info.plist').readAsStringSync();
    expect(iosInfo, contains('<key>UIBackgroundModes</key>'));
    expect(iosInfo, contains('<string>audio</string>'));
    expect(iosInfo, contains('<string>fetch</string>'));
  });

  test('iOS host exposes Background App Refresh via fetch', () {
    final iosInfo = File('ios/Runner/Info.plist').readAsStringSync();
    // Windows CI checks out Swift as CRLF; normalize before multiline contains().
    final appDelegate = File(
      'ios/Runner/AppDelegate.swift',
    ).readAsStringSync().replaceAll('\r\n', '\n');

    expect(iosInfo, contains('<string>fetch</string>'));
    expect(appDelegate, contains('setMinimumBackgroundFetchInterval'));
    expect(appDelegate, contains('performFetchWithCompletionHandler'));
    expect(
      appDelegate,
      contains(
        'override func application(\n'
        '    _ application: UIApplication,\n'
        '    performFetchWithCompletionHandler',
      ),
    );
    expect(appDelegate, isNot(contains('@objc func application(')));
    expect(
      appDelegate,
      contains('#selector(application(_:performFetchWithCompletionHandler:))'),
    );
    expect(appDelegate, contains('completionHandler(.noData)'));
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

  test('Android release enables R8 with Flutter plugin keep rules', () {
    final build = File('android/app/build.gradle.kts').readAsStringSync();
    final rules = File('android/app/proguard-rules.pro').readAsStringSync();

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
    expect(build, contains('isMinifyEnabled = true'));
    expect(build, contains('isShrinkResources = true'));
    expect(build, contains('proguardFiles('));
    expect(build, contains('"proguard-rules.pro"'));
    expect(rules, contains('GeneratedPluginRegistrant'));
    expect(
      rules,
      contains('io.flutter.embedding.engine.plugins.FlutterPlugin'),
    );
    expect(rules, contains('com.ryanheise.audioservice'));
    expect(rules, contains('io.abner.flutter_js'));
    expect(rules, contains('com.koyze.app'));
    expect(rules, contains('com.google.android.play.core.splitinstall'));
    expect(rules, contains('-dontwarn com.google.android.play.core.tasks.**'));
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

  test('launcher source icon is not shipped as a Flutter asset', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    // Windows CI checks out YAML as CRLF; the flutter: section split must
    // not fall through to flutter_launcher_icons image_path.
    final normalized = pubspec.replaceAll('\r\n', '\n');
    for (final text in [normalized, normalized.replaceAll('\n', '\r\n')]) {
      final flutterSection = text
          .replaceAll('\r\n', '\n')
          .split(RegExp(r'\nflutter:\n'))
          .last;

      expect(flutterSection, contains('uses-material-design: true'));
      expect(flutterSection, isNot(contains('assets:')));
      expect(flutterSection, isNot(contains('app_icon.png')));
    }
  });

  test('鸿蒙 pubspec 拷贝不会丢主 pubspec 的 flutter: 段开关', () {
    // build-harmonyos-online.yml 第 149 行把 pubspec_ohos.yaml **整个复制**
    // 成 pubspec.yaml 再 pub get / build hap，所以这份拷贝里少一个开关，
    // 就等于鸿蒙线上少一个开关，而且其余五个平台的 CI 完全看不见。
    //
    // 真实事故：i18n 迁移（ADR 0007）只在 pubspec.yaml 加了 `generate: true`，
    // 鸿蒙 CI 的 gen_localizations 目标随即抛
    //   Target gen_localizations failed: Attempted to generate localizations
    //   code without having the flutter: generate flag turned on.
    // 两个架构的 HAP 全部构建失败。
    Map<String, String> flutterFlags(String path) {
      final lines = File(path).readAsStringSync().replaceAll('\r\n', '\n').split('\n');
      // 必须是列 0 的顶级 flutter:，否则会先匹配到 dependencies 里的
      // `  flutter:`（后跟 `sdk: flutter`）。
      final start = lines.indexWhere((line) => line == 'flutter:');
      expect(start, greaterThanOrEqualTo(0), reason: '$path 缺少 flutter: 段');

      final flags = <String, String>{};
      for (final line in lines.skip(start + 1)) {
        final trimmed = line.trim();
        if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
        // 缩进归零说明已经进入下一个顶级键，flutter: 段到此为止。
        if (!line.startsWith(' ')) break;
        final match = RegExp(r'^  ([\w-]+):\s*(.*)$').firstMatch(line);
        if (match != null) {
          flags[match.group(1)!] = match.group(2)!.trim();
        }
      }
      return flags;
    }

    final main = flutterFlags('pubspec.yaml');
    final ohos = flutterFlags('pubspec_ohos.yaml');

    expect(main['generate'], 'true', reason: 'pubspec.yaml 缺少 flutter: generate: true');
    expect(
      ohos,
      equals(main),
      reason: 'pubspec_ohos.yaml 会被复制成 pubspec.yaml，flutter: 段必须与主 '
          'pubspec 完全一致；缺失的键：'
          '${main.keys.where((key) => !ohos.containsKey(key)).toList()}',
    );
  });

  test('鸿蒙 pubspec 拷贝不会丢主 pubspec 的依赖项', () {
    // 和上面那个 flutter: 段的用例同源：鸿蒙 CI 用 pubspec_ohos.yaml 覆盖
    // pubspec.yaml 后再 pub get，lib/ 仍然整份编译。主清单里多一个依赖而拷贝里
    // 没有，就等于鸿蒙侧 import 不存在的包，两个架构的 HAP 全部编译失败。
    //
    // 反向不查：拷贝里多出来的（just_audio_ohos 这类鸿蒙独占包）是正常的。
    Set<String> depKeys(String path, String section) {
      final lines = File(path).readAsStringSync().replaceAll('\r\n', '\n').split('\n');
      final start = lines.indexWhere((line) => line == section);
      expect(start, greaterThanOrEqualTo(0), reason: '$path 缺少 $section 段');

      final keys = <String>{};
      for (final line in lines.skip(start + 1)) {
        if (line.trim().isEmpty || line.trim().startsWith('#')) continue;
        // 缩进归零说明已经进入下一个顶级键。
        if (!line.startsWith(' ')) break;
        final match = RegExp(r'^  ([\w-]+):').firstMatch(line);
        if (match != null) keys.add(match.group(1)!);
      }
      return keys;
    }

    for (final section in ['dependencies:', 'dev_dependencies:']) {
      final main = depKeys('pubspec.yaml', section);
      final ohos = depKeys('pubspec_ohos.yaml', section);
      expect(main, isNotEmpty, reason: '$section 解析为空，用例本身失效');

      final missing = main.difference(ohos).toList()..sort();
      expect(
        missing,
        isEmpty,
        reason: 'pubspec_ohos.yaml 的 $section 缺少：$missing。'
            '鸿蒙构建会把它覆盖成 pubspec.yaml，缺项即编译失败。',
      );
    }
  });

  test('launcher source icon stays a compact 1024 PNG', () {
    final icon = File('assets/icon/app_icon.png');
    final bytes = icon.readAsBytesSync();

    expect(bytes[0], 0x89);
    expect(bytes.sublist(1, 4), [0x50, 0x4e, 0x47]);
    expect(
      (bytes[16] << 24) | (bytes[17] << 16) | (bytes[18] << 8) | bytes[19],
      1024,
    );
    expect(
      (bytes[20] << 24) | (bytes[21] << 16) | (bytes[22] << 8) | bytes[23],
      1024,
    );
    // Source is launcher input only (not a Flutter asset). Do not recompress
    // artwork; still reject the previous uncompressed 860KB blow-up.
    expect(bytes.length, lessThan(256 * 1024));
  });

  test('macOS and Linux launcher icons use the mobile artwork', () {
    final source = File('assets/icon/app_icon.png').readAsBytesSync();
    expect(
      File(
        'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_1024.png',
      ).readAsBytesSync(),
      source,
    );
    expect(
      File('linux/runner/resources/app_icon.png').readAsBytesSync(),
      source,
    );

    const macosSizes = {16, 32, 64, 128, 256, 512, 1024};
    for (final size in macosSizes) {
      final bytes = File(
        'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_$size.png',
      ).readAsBytesSync();
      expect(bytes[0], 0x89);
      expect(bytes.sublist(1, 4), [0x50, 0x4e, 0x47]);
      expect(
        (bytes[16] << 24) | (bytes[17] << 16) | (bytes[18] << 8) | bytes[19],
        size,
      );
      expect(
        (bytes[20] << 24) | (bytes[21] << 16) | (bytes[22] << 8) | bytes[23],
        size,
      );
    }

    final linuxRunner = File(
      'linux/runner/my_application.cc',
    ).readAsStringSync();
    expect(linuxRunner, contains('set_application_icon(window)'));
    expect(linuxRunner, contains('gtk_window_set_icon_from_file'));
    expect(linuxRunner, contains('data", "app_icon.png"'));

    final cmake = File('linux/CMakeLists.txt').readAsStringSync();
    expect(cmake, contains('runner/resources/app_icon.png'));
    expect(cmake, contains('INSTALL_BUNDLE_DATA_DIR'));
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

  test('build workflows gate a release tag on the pubspec version', () {
    final guard = RegExp(
      r"name: Verify release tag matches pubspec version\n"
      r"\s+if: startsWith\(github\.ref, 'refs/tags/v'\)\n"
      r"\s+shell: bash\n"
      r"\s+run: \|",
    );
    for (final platform in ['android', 'ios', 'linux', 'macos', 'windows']) {
      // Windows CI checks out the workflow as CRLF; normalize before matching.
      final workflow = File(
        '.github/workflows/build-$platform.yml',
      ).readAsStringSync().replaceAll('\r\n', '\n');

      expect(guard.hasMatch(workflow), isTrue, reason: platform);

      final checkout = workflow.indexOf('name: Check out repository');
      final verify = workflow.indexOf(
        'name: Verify release tag matches pubspec version',
      );
      final flutter = workflow.indexOf('uses: subosito/flutter-action@v2');

      expect(checkout, greaterThanOrEqualTo(0), reason: platform);
      expect(verify, greaterThan(checkout), reason: platform);
      expect(flutter, greaterThan(verify), reason: platform);
    }
  });

  test('HarmonyOS audio plugin never throws while reporting an error', () {
    // `err.getMessage()` 是 Java 风格 API，ArkTS 的 Error 没有这个方法。
    // 在 catch 里二次抛错会跳过 result.error，method channel 永不回包，
    // Dart 侧只能等满 sourceLoadTimeout（20s）。这个 bug 曾让鸿蒙每次
    // 手动切歌都卡 20 秒才出声。
    final pluginDir = Directory(
      'third_party/just_audio/ohos/ohos/src/main/ets/components/plugin',
    );
    expect(pluginDir.existsSync(), isTrue);

    final sources = pluginDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.ets'))
        .toList();
    expect(sources, isNotEmpty);
    for (final source in sources) {
      expect(
        source.readAsStringSync(),
        isNot(contains('.getMessage(')),
        reason: '${source.path} 调用了 ArkTS 不存在的 Error.getMessage()',
      );
    }

    final audioPlayer = File(
      'third_party/just_audio/ohos/ohos/src/main/ets/components/plugin/'
      'AudioPlayer.ets',
    ).readAsStringSync();
    expect(audioPlayer, contains('describeError'));
    expect(audioPlayer, contains('prepareResult = null'));
  });

  test('鸿蒙导出下载目录走 DOWNLOAD 模式，而不是自己拼公共路径', () {
    // 手机端第三方应用没有公共目录的写权限
    // （`READ_WRITE_DOWNLOAD_DIRECTORY` 只支持 PC / 2in1 / 平板），所以
    // `Download/<包名>` 只能由系统 picker 授权一次，之后按 URI 写。这里钉住
    // 三件事：走 DOWNLOAD 模式、缓存授权（否则每首歌弹一次窗）、方法名与
    // Dart 侧对得上。
    final bridge = File(
      'ohos/entry/src/main/ets/entryability/LocalFileSystemBridge.ets',
    ).readAsStringSync();

    expect(bridge, contains("case 'exportToPublicDownloads'"));
    expect(bridge, contains('picker.DocumentPickerMode.DOWNLOAD'));
    // 缓存：首次 save() 拿到 URI 存进 Preferences，之后复用。
    expect(bridge, contains('preferences.getPreferences'));
    expect(bridge, contains('DOWNLOAD_URI_KEY'));
    // 授权失效（用户删目录 / 撤销授权）时要能重新申请。
    expect(bridge, contains('clearCachedDownloadUri'));
    // 关键：picker 返回的 `file://docs/...` 只是授权凭据，不能直接当路径
    // 递给 fs.open / fs.copy —— 实测模拟器上分别报 ENOENT 和 401。必须先用
    // fileUri.FileUri(...).path 映射成真实路径，官方示例也是这么写的。
    expect(
      bridge,
      contains('new fileUri.FileUri('),
      reason: 'docs URI 要经 FileUri 转成路径才能 open',
    );
    expect(bridge, contains('pathForms'));
    // 别退回到「自己拼公共目录路径」——那条路在手机上没有权限。
    expect(
      bridge,
      isNot(contains('getUserDownloadDir')),
      reason: '手机端没有公共下载目录的路径级权限，只能走 picker 授权',
    );
  });

  test('iOS 导出走文档选择器 + 书签，不打开 UIFileSharingEnabled', () {
    // iOS 没有公共「下载」文件夹，唯一出口是让用户在「文件」App 里挑一个
    // 目录。这里钉住四件事：
    //
    // 1. 方法名与 Dart 侧对得上，且参数名是 `source`；
    // 2. 走 `UIDocumentPickerViewController` 的**文件夹**模式；
    // 3. 记住用户选的目录（security-scoped bookmark），否则导 N 首歌会
    //    弹 N 次窗，用户会直接放弃；
    // 4. **不**打开 `UIFileSharingEnabled` / `LSSupportsOpeningDocumentsInPlace`
    //    ——那两个键会把整个 Documents 摊在「文件」App 里，而
    //    `playlists.v1.json` 和 `local_artwork/` 就在那，用户删一个文件
    //    就是全部歌单丢失。
    final delegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();

    expect(delegate, contains('case "exportToPublicDownloads"'));
    expect(
      delegate,
      contains('UIDocumentPickerViewController'),
      reason: 'iOS 只能由用户挑目录，不能自己拼公共路径',
    );
    expect(delegate, contains('forOpeningContentTypes: [.folder]'));
    expect(
      delegate,
      contains('bookmarkData'),
      reason: '选一次就要记住，否则每首歌弹一次窗',
    );
    expect(delegate, contains('documentPickerWasCancelled'));
    expect(
      delegate,
      contains('startAccessingSecurityScopedResource'),
      reason: '用户选的目录必须 startAccessing 才写得进去',
    );

    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    expect(
      plist,
      isNot(contains('UIFileSharingEnabled')),
      reason: '打开它会把 playlists.v1.json 暴露给用户在「文件」App 里误删',
    );
    expect(
      plist,
      isNot(contains('LSSupportsOpeningDocumentsInPlace')),
      reason: '同上：Documents 目录不该整体摊开',
    );
  });

  test('Android 导出走 MediaStore，而不是靠 MANAGE_EXTERNAL_STORAGE', () {
    // Android 10+ 的 MediaStore 免权限写「下载」；MANAGE_EXTERNAL_STORAGE
    // 只在扫描本地音乐时兜底，普通用户不会主动去授权，拿它当导出的前提
    // 等于导出功能默认不可用。
    final exporter = File(
      'android/app/src/main/kotlin/com/koyze/app/DownloadsExporter.kt',
    );
    expect(exporter.existsSync(), isTrue);
    final source = exporter.readAsStringSync();

    expect(source, contains('MediaStore.Downloads'));
    expect(source, contains('RELATIVE_PATH'));
    expect(source, contains('IS_PENDING'));
    expect(
      source,
      contains('Build.VERSION_CODES.Q'),
      reason: 'API 28 及以下没有 MediaStore.Downloads，必须有分支',
    );
    // 目录名必须和桌面端一致，否则「统一到 下载/Koyze」这句话就不成立。
    expect(source, contains('FOLDER_NAME = "Koyze"'));
    // 覆盖式：重复导出同一首歌不该堆出「xxx (1).m4a」。
    expect(source, contains('deleteExisting'));
    // 导出不能以 MANAGE_EXTERNAL_STORAGE 为前提（注释里解释这件事不算，
    // 这里只看有没有真的去读权限状态：`Environment.isExternalStorageManager`
    // 才是拿到那个权限的判据）。
    expect(
      source,
      isNot(contains('isExternalStorageManager')),
      reason: '导出要在普通授权下就能用，不能依赖「所有文件访问」权限',
    );

    final activity = File(
      'android/app/src/main/kotlin/com/koyze/app/MainActivity.kt',
    ).readAsStringSync();
    expect(activity, contains('"exportToPublicDownloads"'));
    expect(activity, contains('DownloadsExporter'));
  });

  test('桌面默认下载目录是系统「下载/Koyze」，并兼容旧目录', () {
    // 以前默认落在 getApplicationDocumentsDirectory()/downloads，Windows 上
    // 就是「文档\downloads」——用户下完歌去「下载」文件夹找不到东西。
    final service = File(
      'lib/features/download/domain/download_service.dart',
    ).readAsStringSync();

    expect(service, contains('getDownloadsDirectory()'));
    expect(service, contains("publicDownloadsFolderName = 'Koyze'"));
    // 换掉默认落点后，老用户下载记录里的旧路径必须仍被认作归属根，
    // 否则升级重启时会被当成越权路径整个隔离掉（下载列表凭空清空）。
    expect(
      service,
      contains('_adoptLegacyDefaultDirectory'),
      reason: '不登记旧默认目录的话，升级后老用户的下载记录会被隔离',
    );

    // macOS 沙盒写 ~/Downloads 必须有这个 entitlement，缺了就是创建目录
    // 直接失败、整个下载功能不可用。
    for (final entitlements in [
      'macos/Runner/DebugProfile.entitlements',
      'macos/Runner/Release.entitlements',
    ]) {
      expect(
        File(entitlements).readAsStringSync(),
        contains('com.apple.security.files.downloads.read-write'),
        reason: '$entitlements 缺 Downloads 写权限，macOS 上会下载全失败',
      );
    }
  });

  test('runner CMake source lists reference files that exist', () {
    // 原生构建要等 Flutter 打包完成后才进 CMake。清单里写错文件名（例如把
    // .cc 写成 .cpp）时，CI 要跑十几分钟才失败，而且报错落在 CMake 的
    // configure 阶段，看不出是哪次改动引入的。这里用文件存在性提前钉住。
    final entry = RegExp(r'"([^"]+\.(?:cc|cpp|c|h|hh|hpp|rc|manifest))"');

    for (final platform in ['windows', 'linux']) {
      final cmake = File('$platform/runner/CMakeLists.txt');
      expect(cmake.existsSync(), isTrue, reason: platform);

      final checked = <String>[];
      for (final match in entry.allMatches(cmake.readAsStringSync())) {
        final name = match.group(1)!;
        // Flutter 生成目录里的文件由 `flutter pub get` 产出，仓库里没有。
        if (name.contains(r'${')) continue;
        checked.add(name);
        expect(
          File('$platform/runner/$name').existsSync(),
          isTrue,
          reason: '$platform/runner/CMakeLists.txt 引用了不存在的文件 $name',
        );
      }
      expect(checked, isNotEmpty, reason: '$platform 未解析到任何源文件');
    }
  });
}

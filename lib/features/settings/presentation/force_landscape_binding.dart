import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'settings_provider.dart';

const forceLandscapeOrientations = <DeviceOrientation>[
  DeviceOrientation.landscapeLeft,
  DeviceOrientation.landscapeRight,
];

const unlockedOrientations = <DeviceOrientation>[
  DeviceOrientation.portraitUp,
  DeviceOrientation.portraitDown,
  DeviceOrientation.landscapeLeft,
  DeviceOrientation.landscapeRight,
];

bool forceLandscapeLocksDevice({
  required TargetPlatform platform,
  required bool isWeb,
}) {
  return !isWeb &&
      (platform == TargetPlatform.android || platform == TargetPlatform.iOS);
}

Future<void> applyForceLandscape(
  bool enabled, {
  TargetPlatform? platform,
  bool? isWeb,
}) {
  final locks = forceLandscapeLocksDevice(
    platform: platform ?? defaultTargetPlatform,
    isWeb: isWeb ?? kIsWeb,
  );
  if (!locks) return Future<void>.value();
  return SystemChrome.setPreferredOrientations(
    enabled ? forceLandscapeOrientations : unlockedOrientations,
  );
}

class ForceLandscapeBinding extends ConsumerStatefulWidget {
  const ForceLandscapeBinding({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<ForceLandscapeBinding> createState() =>
      _ForceLandscapeBindingState();
}

class _ForceLandscapeBindingState extends ConsumerState<ForceLandscapeBinding> {
  @override
  void initState() {
    super.initState();
    ref.listenManual<bool>(forceLandscapeProvider, (_, next) {
      applyForceLandscape(next);
    }, fireImmediately: true);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

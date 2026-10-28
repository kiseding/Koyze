// Copyright 2024 Koyze Contributors
// Licensed under the Apache License, Version 2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/koyze_sheet.dart';
import '../../../l10n/app_strings.dart';
import '../domain/car_connection.dart';
import 'car_mode_provider.dart';

/// 设置页副标题：把连接状态直接写在入口上，省得点进去才知道车机连没连上。
String carModeStatusText(CarConnection connection, S s) {
  return switch (connection) {
    CarConnection.connected => s.carModeStatusConnected,
    CarConnection.disconnected => s.carModeStatusDisconnected,
    CarConnection.unsupported => s.carModeStatusUnsupported,
  };
}

void showCarModeSheet(BuildContext context, WidgetRef ref) {
  showKoyzeSheet(
    context: context,
    builder: (context) => Consumer(
      builder: (context, ref, _) {
        final s = S.of(context);
        final preference = ref.watch(carModePreferenceProvider);
        final connection = ref.watch(carConnectionProvider);
        void choose(CarModePreference value) {
          Navigator.pop(context);
          ref.read(carModePreferenceProvider.notifier).set(value);
        }

        return SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const KoyzeSheetGrabber(),
              KoyzeSheetTitle(
                title: s.carMode,
                subtitle: carModeStatusText(connection, s),
                onClose: () => Navigator.pop(context),
              ),
              KoyzeSheetAction(
                icon: Icons.directions_car_outlined,
                label: s.carModeAuto,
                subtitle: s.carModeAutoSubtitle,
                selected: preference == CarModePreference.auto,
                onTap: () => choose(CarModePreference.auto),
              ),
              KoyzeSheetAction(
                icon: Icons.stay_current_landscape_outlined,
                label: s.carModeAlways,
                subtitle: s.carModeAlwaysSubtitle,
                selected: preference == CarModePreference.always,
                onTap: () => choose(CarModePreference.always),
              ),
              KoyzeSheetAction(
                icon: Icons.block_outlined,
                label: s.carModeOff,
                selected: preference == CarModePreference.off,
                onTap: () => choose(CarModePreference.off),
              ),
            ],
          ),
        );
      },
    ),
  );
}

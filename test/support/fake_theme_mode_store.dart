import 'package:evt_ble_app/features/settings/application/theme_mode_controller.dart';
import 'package:flutter/material.dart';

class FakeThemeModeStore implements ThemeModeStore {
  ThemeMode? value;

  @override
  Future<void> clear() async => value = null;

  @override
  Future<ThemeMode?> read() async => value;

  @override
  Future<void> write(ThemeMode mode) async => value = mode;
}

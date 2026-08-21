import 'package:evt_ble_app/features/settings/application/theme_mode_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_theme_mode_store.dart';

void main() {
  test(
    'theme defaults to system until an explicit override is saved',
    () async {
      final controller = ThemeModeController(FakeThemeModeStore());

      expect(await controller.load(), ThemeMode.system);
      await controller.set(ThemeMode.dark);
      expect(await controller.load(), ThemeMode.dark);
    },
  );
}

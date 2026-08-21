import 'package:evt_ble_app/core/design_system/evt_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('light theme uses approved warm semantic tokens', () {
    final theme = EvtTheme.light();

    expect(theme.scaffoldBackgroundColor, const Color(0xFFF8F6F3));
    expect(theme.colorScheme.surface, const Color(0xFFFFFFFF));
    expect(theme.colorScheme.primary, const Color(0xFF19212B));
    expect(theme.dividerColor, const Color(0xFFE5E1DA));
  });

  test('dark theme uses a warm charcoal canvas rather than pure black', () {
    final theme = EvtTheme.dark();

    expect(theme.scaffoldBackgroundColor, const Color(0xFF11100E));
    expect(theme.scaffoldBackgroundColor, isNot(const Color(0xFF000000)));
  });
}

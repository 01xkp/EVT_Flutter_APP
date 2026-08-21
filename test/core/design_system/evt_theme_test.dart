import 'package:evt_ble_app/core/design_system/evt_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('light theme uses the approved cool-white canvas', () {
    final theme = EvtTheme.light();

    expect(theme.scaffoldBackgroundColor, const Color(0xFFF7F8FA));
    expect(theme.colorScheme.primary, const Color(0xFF17191C));
  });

  test('dark theme uses a graphite canvas rather than pure black', () {
    final theme = EvtTheme.dark();

    expect(theme.scaffoldBackgroundColor, const Color(0xFF121416));
    expect(theme.scaffoldBackgroundColor, isNot(const Color(0xFF000000)));
  });
}

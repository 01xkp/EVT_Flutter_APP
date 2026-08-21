import 'dart:async';

import 'package:evt_ble_app/app/app_shell.dart';
import 'package:evt_ble_app/core/design_system/evt_theme.dart';
import 'package:evt_ble_app/features/settings/application/theme_mode_controller.dart';
import 'package:flutter/material.dart';

class EvtApp extends StatefulWidget {
  const EvtApp({super.key});

  @override
  State<EvtApp> createState() => _EvtAppState();
}

class _EvtAppState extends State<EvtApp> {
  late final ThemeModeController _themeController;

  @override
  void initState() {
    super.initState();
    _themeController = ThemeModeController(SharedPreferencesThemeModeStore())
      ..addListener(_onThemeChanged);
    unawaited(_themeController.load());
  }

  @override
  void dispose() {
    _themeController
      ..removeListener(_onThemeChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: EvtTheme.light(),
      darkTheme: EvtTheme.dark(),
      themeMode: _themeController.mode,
      home: const AppShell(),
    );
  }

  void _onThemeChanged() {
    if (mounted) {
      setState(() {});
    }
  }
}

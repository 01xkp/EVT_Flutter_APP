import 'dart:async';

import 'package:aipin/app/branding/aipin_brand.dart';
import 'package:aipin/app/app_shell.dart';
import 'package:aipin/core/design_system/evt_theme.dart';
import 'package:aipin/features/settings/application/theme_mode_controller.dart';
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
      title: AipinBrand.displayName,
      debugShowCheckedModeBanner: false,
      theme: EvtTheme.light(),
      darkTheme: EvtTheme.dark(),
      themeMode: _themeController.mode,
      home: AppShell(themeController: _themeController),
    );
  }

  void _onThemeChanged() {
    if (mounted) {
      setState(() {});
    }
  }
}

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract interface class ThemeModeStore {
  Future<ThemeMode?> read();
  Future<void> write(ThemeMode mode);
  Future<void> clear();
}

class SharedPreferencesThemeModeStore implements ThemeModeStore {
  static const _key = 'theme_mode';

  Future<SharedPreferences> get _preferences => SharedPreferences.getInstance();

  @override
  Future<ThemeMode?> read() async {
    final value = (await _preferences).getString(_key);
    return switch (value) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => null,
    };
  }

  @override
  Future<void> write(ThemeMode mode) async {
    if (mode == ThemeMode.system) {
      await clear();
      return;
    }
    await (await _preferences).setString(_key, mode.name);
  }

  @override
  Future<void> clear() async {
    await (await _preferences).remove(_key);
  }
}

class ThemeModeController extends ChangeNotifier {
  ThemeModeController(this._store);

  final ThemeModeStore _store;
  ThemeMode _mode = ThemeMode.system;

  ThemeMode get mode => _mode;

  Future<ThemeMode> load() async {
    _mode = await _store.read() ?? ThemeMode.system;
    notifyListeners();
    return _mode;
  }

  Future<void> set(ThemeMode mode) async {
    _mode = mode;
    if (mode == ThemeMode.system) {
      await _store.clear();
    } else {
      await _store.write(mode);
    }
    notifyListeners();
  }
}

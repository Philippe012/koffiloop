import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeService extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system; // safe default until prefs load
  static const String _themeKey = 'theme_mode'; // now stores 'light'|'dark'|'system'

  ThemeMode get themeMode => _themeMode;
  bool get isDarkMode => _themeMode == ThemeMode.dark;

  ThemeService() {
    _loadThemeMode();
  }

  Future<void> _loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();

    final raw = prefs.getString(_themeKey) ?? 'system';

    _themeMode = ThemeMode.values.firstWhere(
      (m) => m.toString().split('.').last == raw,
      orElse: () => ThemeMode.system,
    );
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return; // no-op
    _themeMode = mode;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeKey, mode.toString().split('.').last);

    notifyListeners();
  }

  Future<void> toggleTheme() async {
    final next = switch (_themeMode) {
      ThemeMode.light  => ThemeMode.dark,
      ThemeMode.dark   => ThemeMode.system,
      ThemeMode.system => ThemeMode.light,
    };
    await setThemeMode(next);
  }
}
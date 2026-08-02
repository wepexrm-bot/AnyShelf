import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Drives the app-wide light/dark mode, mirroring the web uiMode toggler
/// (persisted locally under the same `cloudread_ui_mode` key).
class UiModeController extends ChangeNotifier {
  static const String storageKey = 'cloudread_ui_mode';

  ThemeMode _mode = ThemeMode.light;
  ThemeMode get mode => _mode;
  bool get isDark => _mode == ThemeMode.dark;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(storageKey);
    if (saved == 'dark') {
      _mode = ThemeMode.dark;
      notifyListeners();
    }
  }

  Future<void> setMode(ThemeMode mode) async {
    if (mode == _mode) return;
    _mode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(storageKey, mode == ThemeMode.dark ? 'dark' : 'light');
  }

  Future<void> toggle() =>
      setMode(isDark ? ThemeMode.light : ThemeMode.dark);
}
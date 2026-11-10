import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsProvider extends ChangeNotifier {
  static const _kThemeKey = 'settings_theme_mode';
  static const _kLangKey = 'settings_lang';

  ThemeMode _themeMode = ThemeMode.dark;
  String _languageCode = 'fa';

  ThemeMode get themeMode => _themeMode;
  String get languageCode => _languageCode;
  bool get isDark => _themeMode == ThemeMode.dark;
  bool get isRtl => _languageCode == 'fa' || _languageCode == 'ar' || _languageCode == 'ps';

  SettingsProvider() {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final theme = prefs.getString(_kThemeKey);
    _themeMode = theme == 'light' ? ThemeMode.light : ThemeMode.dark;
    _languageCode = prefs.getString(_kLangKey) ?? 'fa';
    notifyListeners();
  }

  Future<void> toggleDarkMode(bool dark) async {
    _themeMode = dark ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kThemeKey, dark ? 'dark' : 'light');
  }

  Future<void> setLanguage(String code) async {
    _languageCode = code;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLangKey, code);
  }
}

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Remembers the light/dark choice, even after the app is closed.
class ThemeController extends ChangeNotifier {
  ThemeController._();
  static final ThemeController instance = ThemeController._();

  static const _key = 'theme_mode';
  ThemeMode _mode = ThemeMode.system;
  ThemeMode get mode => _mode;

  /// Call once before runApp, so the first screen already has the saved theme.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _mode = switch (prefs.getString(_key)) {
        'dark' => ThemeMode.dark,
        'light' => ThemeMode.light,
        _ => ThemeMode.system,
      };
    } catch (_) {}
  }

  bool isDark(BuildContext context) =>
      _mode == ThemeMode.dark ||
      (_mode == ThemeMode.system &&
          MediaQuery.platformBrightnessOf(context) == Brightness.dark);

  Future<void> setMode(ThemeMode mode) async {
    if (mode == _mode) return;
    _mode = mode;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _key,
        mode == ThemeMode.dark
            ? 'dark'
            : mode == ThemeMode.light
            ? 'light'
            : 'system',
      );
    } catch (_) {}
  }

  Future<void> toggle(BuildContext context) =>
      setMode(isDark(context) ? ThemeMode.light : ThemeMode.dark);
}

/// A sun/moon button. Put it in any AppBar.
class ThemeModeButton extends StatelessWidget {
  const ThemeModeButton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeController.instance,
      builder: (context, _) {
        final dark = ThemeController.instance.isDark(context);
        return IconButton(
          tooltip: dark ? 'Switch to light mode' : 'Switch to dark mode',
          onPressed: () => ThemeController.instance.toggle(context),
          icon: Icon(
            dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
          ),
        );
      },
    );
  }
}

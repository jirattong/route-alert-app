import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Global Theme Settings Service for unified Dark / Night mode across all screens,
/// navigation bars, floating cards, overlays, and map views.
class ThemeSettingsService {
  static const String _keyNightMode = 'route_alert_night_mode_enabled';

  /// ValueNotifier for real-time reactivity across Main Navigation, Header, Maps, and Overlays
  static final ValueNotifier<bool> isNightMode = ValueNotifier<bool>(false);

  static bool _isLoaded = false;

  /// Loads saved night mode preference
  static Future<bool> loadSettings() async {
    if (_isLoaded) return isNightMode.value;
    try {
      final prefs = await SharedPreferences.getInstance();
      final bool value = prefs.getBool(_keyNightMode) ?? false;
      isNightMode.value = value;
      _isLoaded = true;
      return value;
    } catch (_) {
      return isNightMode.value;
    }
  }

  /// Sets night mode preference and persists to SharedPreferences
  static Future<void> setNightMode(bool enabled) async {
    isNightMode.value = enabled;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyNightMode, enabled);
    } catch (e) {
      debugPrint('Error saving theme settings: $e');
    }
  }

  /// Toggles the night mode
  static Future<bool> toggle() async {
    final next = !isNightMode.value;
    await setNightMode(next);
    return next;
  }
}

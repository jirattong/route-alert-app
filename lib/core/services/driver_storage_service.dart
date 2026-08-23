import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DriverStorageService {
  static const String _keyBackground = 'driver_bg_mode';
  static const String _keyVolume = 'driver_volume';
  static const String _keyOuterDistanceMeters = 'driver_outer_meters';
  static const String _keyInnerDistanceMeters = 'driver_inner_meters';
  static const String _keyYieldCount = 'driver_yield_count';

  static final ValueNotifier<Map<String, dynamic>> settingsNotifier =
      ValueNotifier<Map<String, dynamic>>({
    'background': true,
    'volume': 80.0,
    'outerMeters': 1500.0, // ค่าเริ่มต้น 1500 เมตร (1.5 กม.)
    'innerMeters': 400.0,  // ค่าเริ่มต้น 400 เมตร
  });

  static Future<void> saveSettings({
    required bool background,
    required double volume,
    required double outerMeters,
    required double innerMeters,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyBackground, background);
    await prefs.setDouble(_keyVolume, volume);
    await prefs.setDouble(_keyOuterDistanceMeters, outerMeters);
    await prefs.setDouble(_keyInnerDistanceMeters, innerMeters);

    settingsNotifier.value = {
      'background': background,
      'volume': volume,
      'outerMeters': outerMeters,
      'innerMeters': innerMeters,
    };
  }

  static Future<Map<String, dynamic>> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'background': prefs.getBool(_keyBackground) ?? true,
      'volume': prefs.getDouble(_keyVolume) ?? 80.0,
      'outerMeters': prefs.getDouble(_keyOuterDistanceMeters) ?? 1500.0,
      'innerMeters': prefs.getDouble(_keyInnerDistanceMeters) ?? 400.0,
    };
  }

  static Future<int> getYieldCount() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyYieldCount) ?? 67;
  }

  static Future<int> incrementYieldCount() async {
    final prefs = await SharedPreferences.getInstance();
    int current = prefs.getInt(_keyYieldCount) ?? 67;
    current += 1;
    await prefs.setInt(_keyYieldCount, current);
    return current;
  }
}
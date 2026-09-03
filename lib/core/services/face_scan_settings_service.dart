import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service managing settings for the Face Scan UI mode:
/// - AI Vision Cyber Scanner (Face Mesh dots & AI Tracking Data HUD)
/// - Original Minimal Portal Ring (circular Apple-like ring)
class FaceScanSettingsService {
  static const String _keyAiVisionMesh = 'face_scan_ai_vision_mesh_enabled';

  /// ValueNotifier for real-time reactivity across screens
  static final ValueNotifier<bool> isAiVisionMeshEnabled = ValueNotifier<bool>(true);

  static bool _isLoaded = false;

  /// Loads saved preference from SharedPreferences (defaults to true)
  static Future<bool> loadSettings() async {
    if (_isLoaded) return isAiVisionMeshEnabled.value;
    try {
      final prefs = await SharedPreferences.getInstance();
      final bool value = prefs.getBool(_keyAiVisionMesh) ?? true;
      isAiVisionMeshEnabled.value = value;
      _isLoaded = true;
      return value;
    } catch (_) {
      return isAiVisionMeshEnabled.value;
    }
  }

  /// Sets the preference and saves to SharedPreferences
  static Future<void> setAiVisionMeshEnabled(bool enabled) async {
    isAiVisionMeshEnabled.value = enabled;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyAiVisionMesh, enabled);
    } catch (e) {
      debugPrint('Error saving face scan settings: $e');
    }
  }

  /// Toggles the current state
  static Future<bool> toggle() async {
    final next = !isAiVisionMeshEnabled.value;
    await setAiVisionMeshEnabled(next);
    return next;
  }
}

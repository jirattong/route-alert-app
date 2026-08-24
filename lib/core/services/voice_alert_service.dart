import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

class VoiceAlertService {
  static final VoiceAlertService _instance = VoiceAlertService._internal();
  factory VoiceAlertService() => _instance;
  VoiceAlertService._internal();

  final FlutterTts _flutterTts = FlutterTts();
  bool _isInitialized = false;

  // Cooldown timestamps to avoid spamming the driver
  DateTime? _lastOuterAlertTime;
  DateTime? _lastRedAlertTime;
  static const int _alertCooldownSeconds = 15;

  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      if (Platform.isIOS) {
        await _flutterTts.setSharedInstance(true);
        await _flutterTts.setIosAudioCategory(
          IosTextToSpeechAudioCategory.playback,
          [
            IosTextToSpeechAudioCategoryOptions.defaultToSpeaker,
            IosTextToSpeechAudioCategoryOptions.allowBluetooth,
            IosTextToSpeechAudioCategoryOptions.allowBluetoothA2DP,
          ],
        );
      }

      await _flutterTts.setLanguage('th-TH');
      await _flutterTts.setSpeechRate(0.5); // Clear, readable speed
      await _flutterTts.setVolume(1.0);
      await _flutterTts.setPitch(1.0);

      _isInitialized = true;
    } catch (e) {
      debugPrint('VoiceAlertService init error: $e');
    }
  }

  /// Speaks outer geofence warning (1500 meters)
  Future<void> speakOuterRadarAlert() async {
    final now = DateTime.now();
    if (_lastOuterAlertTime != null &&
        now.difference(_lastOuterAlertTime!).inSeconds < _alertCooldownSeconds) {
      return;
    }
    _lastOuterAlertTime = now;

    await _speak('มีรถพยาบาลฉุกเฉินในรัศมี 1.5 กิโลเมตร โปรดระมัดระวัง');
  }

  /// Speaks critical red-zone alert (400 meters)
  Future<void> speakRedAlert() async {
    final now = DateTime.now();
    if (_lastRedAlertTime != null &&
        now.difference(_lastRedAlertTime!).inSeconds < 10) {
      return;
    }
    _lastRedAlertTime = now;

    await _speak('แจ้งเตือนฉุกเฉิน! รถพยาบาลกำลังเข้าใกล้ในระยะ 400 เมตร โปรดชะลอความเร็วและเปิดทาง');
  }

  /// Speaks thank-you message after yielding
  Future<void> speakYieldSuccess() async {
    await _speak('ขอบคุณที่เปิดทางให้รถพยาบาลฉุกเฉินครับ');
  }

  Future<void> _speak(String text) async {
    if (!_isInitialized) await initialize();
    try {
      await _flutterTts.stop();
      await _flutterTts.speak(text);
    } catch (e) {
      debugPrint('VoiceAlertService speak error: $e');
    }
  }

  Future<void> stop() async {
    try {
      await _flutterTts.stop();
    } catch (_) {}
  }
}

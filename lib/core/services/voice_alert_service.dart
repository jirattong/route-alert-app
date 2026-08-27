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
  DateTime? _lastPassedTime;
  static const int _alertCooldownSeconds = 12;

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
      await _flutterTts.setSpeechRate(0.52); // Clear, readable speed
      await _flutterTts.setVolume(1.0);
      await _flutterTts.setPitch(1.0);

      _isInitialized = true;
    } catch (e) {
      debugPrint('VoiceAlertService init error: $e');
    }
  }

  /// Speaks outer geofence warning (3 km / 1.5 km)
  Future<void> speakOuterRadarAlert() async {
    final now = DateTime.now();
    if (_lastOuterAlertTime != null &&
        now.difference(_lastOuterAlertTime!).inSeconds < _alertCooldownSeconds) {
      return;
    }
    _lastOuterAlertTime = now;

    await _speak('สัญญาณเรดาร์! ตรวจพบรถพยาบาลเปิดไซเรนกำลังมุ่งหน้ามาในเส้นทางของคุณ');
  }

  /// Speaks critical red-zone alert with dynamic distance
  Future<void> speakCriticalAlert(int meters) async {
    final now = DateTime.now();
    if (_lastRedAlertTime != null &&
        now.difference(_lastRedAlertTime!).inSeconds < 8) {
      return;
    }
    _lastRedAlertTime = now;

    String distText = meters < 100 ? 'ระยะกระชั้นชิด' : 'ระยะ $meters เมตร';
    await _speak('แจ้งเตือนฉุกเฉินระดับวิกฤต! รถพยาบาลกำลังตามหลังมาใน$distText กรุณาชะลอความเร็วและเบี่ยงทางทันที');
  }

  /// Speaks critical red-zone alert default
  Future<void> speakRedAlert() async {
    await speakCriticalAlert(400);
  }

  /// Speaks notification when ambulance has successfully passed / overtaken
  Future<void> speakAmbulancePassed() async {
    final now = DateTime.now();
    if (_lastPassedTime != null &&
        now.difference(_lastPassedTime!).inSeconds < 15) {
      return;
    }
    _lastPassedTime = now;

    await _speak('รถพยาบาลฉุกเฉินเคลื่อนที่ผ่านไปแล้ว ปลอดภัยแล้วครับ ขอบคุณที่ร่วมเปิดทาง');
  }

  /// Speaks thank-you message after user manually taps yield
  Future<void> speakYieldSuccess() async {
    await _speak('ขอบคุณที่ร่วมเปิดทางช่วยชีวิตผู้ป่วยฉุกเฉินครับ');
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

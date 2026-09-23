import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// โทนเสียงที่ปรับ pitch/ความเร็วพูดต่างกัน (ทำงานได้แน่นอนทุกเครื่อง ไม่ต้องพึ่ง
/// ว่าอุปกรณ์นั้นมีเสียง TTS ภาษาไทยให้เลือกหลายตัวหรือไม่ — ต่างจากการเลือก "เสียง"
/// ของระบบซึ่งบางเครื่อง/บาง OS อาจมีเสียงไทยให้เลือกแค่ตัวเดียวหรือไม่มีเลย)
enum VoiceTone { normal, calm, urgent }

extension VoiceToneLabel on VoiceTone {
  String get labelTH {
    switch (this) {
      case VoiceTone.normal:
        return 'ปกติ';
      case VoiceTone.calm:
        return 'นุ่มนวล';
      case VoiceTone.urgent:
        return 'กระชับเร่งด่วน';
    }
  }

  double get pitch {
    switch (this) {
      case VoiceTone.normal:
        return 1.0;
      case VoiceTone.calm:
        return 0.85;
      case VoiceTone.urgent:
        return 1.25;
    }
  }

  double get speechRate {
    switch (this) {
      case VoiceTone.normal:
        return 0.52;
      case VoiceTone.calm:
        return 0.45;
      case VoiceTone.urgent:
        return 0.62;
    }
  }
}

class VoiceAlertService {
  static final VoiceAlertService _instance = VoiceAlertService._internal();
  factory VoiceAlertService() => _instance;
  VoiceAlertService._internal();

  static const String _keyVoiceName = 'voice_alert_selected_voice_name';
  static const String _keyVoiceLocale = 'voice_alert_selected_voice_locale';
  static const String _keyTone = 'voice_alert_tone';

  final FlutterTts _flutterTts = FlutterTts();
  bool _isInitialized = false;
  // กัน race condition เวลามีคนเรียก initialize() ซ้อนกันพร้อมกัน (เช่น alert
  // ยิง _speak() ในจังหวะเดียวกับที่หน้าตั้งค่าเรียก initialize() ตรงๆ) — ถ้าไม่กัน
  // ไว้ ทั้งสอง call จะรัน _doInitialize() พร้อมกันทั้งคู่ เคสร้ายสุดคือ
  // setSelectedVoice()/setTone() ที่เพิ่งอัปเดต ValueNotifier ไป ถูก initialize()
  // อีกตัวที่กำลังรันค้างอยู่เรียก _loadSavedPreferences() ทับกลับเป็นค่าเก่าที่
  // เคยบันทึกไว้ก่อนหน้า
  Future<void>? _initFuture;

  // Cooldown timestamps to avoid spamming the driver
  DateTime? _lastOuterAlertTime;
  DateTime? _lastRedAlertTime;
  DateTime? _lastPassedTime;
  static const int _alertCooldownSeconds = 12;

  /// เสียง TTS ของระบบที่ผู้ใช้เลือกไว้ล่าสุด (null = ใช้ค่า default ของเครื่อง)
  final ValueNotifier<Map<String, String>?> selectedVoiceNotifier =
      ValueNotifier<Map<String, String>?>(null);

  /// โทนเสียงที่เลือกไว้ล่าสุด (ปรับ pitch/ความเร็วพูด)
  final ValueNotifier<VoiceTone> toneNotifier =
      ValueNotifier<VoiceTone>(VoiceTone.normal);

  Future<void> initialize() async {
    if (_isInitialized) return;
    // มี initialize() กำลังทำงานอยู่แล้ว (call ซ้อน) — เข้าคิวรอตัวเดิมแทนที่จะเริ่ม
    // ใหม่ซ้ำ ป้องกันการรันซ้ำซ้อนแย่งกันตั้งค่า/โหลด preferences
    if (_initFuture != null) return _initFuture!;

    final future = _doInitialize();
    _initFuture = future;
    try {
      await future;
    } finally {
      _initFuture = null;
    }
  }

  Future<void> _doInitialize() async {
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
      await _flutterTts.setVolume(1.0);

      // โหลดโทนเสียง + เสียงที่ผู้ใช้เคยเลือกไว้ก่อนหน้า (ถ้ามี) แล้วค่อยตั้งค่า
      // pitch/rate ตามโทนที่โหลดมา แทนค่าคงที่ตายตัวเดิม
      await _loadSavedPreferences();
      await _flutterTts.setPitch(toneNotifier.value.pitch);
      await _flutterTts.setSpeechRate(toneNotifier.value.speechRate);
      final savedVoice = selectedVoiceNotifier.value;
      if (savedVoice != null) {
        try {
          await _flutterTts.setVoice(savedVoice);
        } catch (e) {
          debugPrint('VoiceAlertService: saved voice unavailable, using default: $e');
        }
      }

      _isInitialized = true;
    } catch (e) {
      debugPrint('VoiceAlertService init error: $e');
    }
  }

  Future<void> _loadSavedPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final toneKey = prefs.getString(_keyTone);
    if (toneKey != null) {
      toneNotifier.value = VoiceTone.values.firstWhere(
        (t) => t.name == toneKey,
        orElse: () => VoiceTone.normal,
      );
    }
    final voiceName = prefs.getString(_keyVoiceName);
    final voiceLocale = prefs.getString(_keyVoiceLocale);
    if (voiceName != null && voiceLocale != null) {
      selectedVoiceNotifier.value = {'name': voiceName, 'locale': voiceLocale};
    }
  }

  /// ดึงรายชื่อเสียง TTS ของระบบที่รองรับภาษาไทย (th-TH) — ถ้าเครื่องไม่มีเสียง
  /// ไทยเลย จะคืนรายการเสียงทั้งหมดที่เครื่องมีแทน (ดีกว่าไม่มีตัวเลือกให้เลยเสียเลย)
  Future<List<Map<String, String>>> getAvailableVoices() async {
    try {
      final dynamic raw = await _flutterTts.getVoices;
      final List<Map<String, String>> all = [];
      if (raw is List) {
        for (final v in raw) {
          if (v is Map) {
            final name = v['name']?.toString();
            final locale = v['locale']?.toString();
            if (name != null && locale != null) {
              all.add({'name': name, 'locale': locale});
            }
          }
        }
      }
      final thaiVoices =
          all.where((v) => v['locale']!.toLowerCase().startsWith('th')).toList();
      return thaiVoices.isNotEmpty ? thaiVoices : all;
    } catch (e) {
      debugPrint('VoiceAlertService.getAvailableVoices error: $e');
      return [];
    }
  }

  /// เลือกเสียง TTS ของระบบ แล้วบันทึกถาวร (null = กลับไปใช้ค่า default ของเครื่อง)
  Future<void> setSelectedVoice(Map<String, String>? voice) async {
    if (!_isInitialized) await initialize();
    selectedVoiceNotifier.value = voice;
    final prefs = await SharedPreferences.getInstance();
    if (voice == null) {
      await prefs.remove(_keyVoiceName);
      await prefs.remove(_keyVoiceLocale);
    } else {
      await prefs.setString(_keyVoiceName, voice['name']!);
      await prefs.setString(_keyVoiceLocale, voice['locale']!);
      try {
        await _flutterTts.setVoice(voice);
      } catch (e) {
        debugPrint('VoiceAlertService.setSelectedVoice error: $e');
      }
    }
    await _speak('นี่คือตัวอย่างเสียงแจ้งเตือนที่เลือกไว้');
  }

  /// เลือกโทนเสียง (ปกติ/นุ่มนวล/กระชับเร่งด่วน) แล้วบันทึกถาวร
  Future<void> setTone(VoiceTone tone) async {
    if (!_isInitialized) await initialize();
    toneNotifier.value = tone;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyTone, tone.name);
    try {
      await _flutterTts.setPitch(tone.pitch);
      await _flutterTts.setSpeechRate(tone.speechRate);
    } catch (e) {
      debugPrint('VoiceAlertService.setTone error: $e');
    }
    await _speak('นี่คือตัวอย่างโทนเสียง${tone.labelTH}');
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

  // Cooldown แยกของฝั่ง Agency (เคสใหม่จาก Driver SOS) — กันสแปมเสียงถ้ามีหลาย
  // เคสโผล่มาพร้อมกันรัวๆ ในเวลาไล่เลี่ยกัน
  DateTime? _lastNewIncidentAlertTime;

  /// Speaks a notification when a new pending incident report arrives
  /// (Agency role — ยังไม่มีใครเรียกใช้เมธอดนี้มาก่อน เพิ่งเชื่อมกับการตั้งค่า
  /// "เสียงแจ้งเตือน" ของ agency ที่เดิมบันทึกค่าได้แต่ไม่มีผลอะไรเลย)
  Future<void> speakNewIncidentAlert() async {
    final now = DateTime.now();
    if (_lastNewIncidentAlertTime != null &&
        now.difference(_lastNewIncidentAlertTime!).inSeconds < 5) {
      return;
    }
    _lastNewIncidentAlertTime = now;

    await _speak('มีเคสฉุกเฉินใหม่แจ้งเข้ามา กรุณาตรวจสอบและมอบหมายรถพยาบาล');
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

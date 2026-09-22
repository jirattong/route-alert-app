import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../core/ml/siren_detection_service.dart';
import '../../../core/services/app_language_service.dart';
import '../../../core/services/driver_storage_service.dart';
import '../../../core/services/theme_settings_service.dart';
import '../../../core/services/voice_alert_service.dart';
import '../../onboarding/presentation/onboarding_screen.dart';

class DriverSettingsScreen extends StatefulWidget {
  /// เรียกเมื่อกด "สอนการใช้งานปุ่มต่างๆ" — ให้ DriverMainScreen สลับไปแท็บแผนที่
  /// แล้วเปิด Coach Mark ชี้ปุ่มจริงให้ (Coach Mark ผูกอยู่กับ DriverHomeScreen
  /// คนละหน้ากับหน้านี้ เลยต้องส่งผ่าน callback ขึ้นไปให้ตัว MainScreen จัดการ)
  final VoidCallback? onShowCoachMark;

  const DriverSettingsScreen({super.key, this.onShowCoachMark});

  @override
  State<DriverSettingsScreen> createState() => _DriverSettingsScreenState();
}

class _DriverSettingsScreenState extends State<DriverSettingsScreen> {
  bool _isBackgroundMode = true;
  double _volume = 80.0;
  double _outerMeters = 1500.0; // 500 - 3000 เมตร
  double _innerMeters = 400.0;  // 100 - 800 เมตร
  bool _isEnglish = false;
  bool _isNightMode = false;
  bool _isSirenDetectionEnabled = false;
  bool _isSirenModelLoaded = false;
  bool _isBackgroundAlertEnabled = false;
  bool _isRequestingBackgroundPermission = false;

  // เสียงพูดแจ้งเตือน (Voice Alert) — เลือกโทนเสียง (ปกติ/นุ่มนวล/กระชับเร่งด่วน)
  // และเสียง TTS ของระบบ (ถ้าเครื่องมีให้เลือกหลายตัว) เดิมไม่มีการตั้งค่านี้เลย
  // ใช้ค่า default ตายตัวเสมอ
  List<Map<String, String>> _availableVoices = [];
  Map<String, String>? _selectedVoice;
  VoiceTone _selectedTone = VoiceTone.normal;
  bool _isLoadingVoices = true;

  @override
  void initState() {
    super.initState();
    _loadCurrentSettings();
    _initVoiceSettings();
    AppLanguageService.loadSettings().then((value) {
      if (mounted) setState(() => _isEnglish = value);
    });
    _isNightMode = ThemeSettingsService.isNightMode.value;
    ThemeSettingsService.isNightMode.addListener(_onNightModeChanged);

    DriverStorageService.getSirenDetectionEnabled().then((value) {
      if (mounted) setState(() => _isSirenDetectionEnabled = value);
    });
    DriverStorageService.getBackgroundAlertEnabled().then((value) {
      if (mounted) setState(() => _isBackgroundAlertEnabled = value);
    });
    // เช็คว่ามีไฟล์โมเดล AI จริงหรือยัง (ยังไม่มี → toggle จะเปิดได้แต่ต้องรอโมเดล)
    SirenDetectionService().initialize().then((_) {
      if (mounted) {
        setState(() => _isSirenModelLoaded = SirenDetectionService().isModelLoaded);
      }
    });
  }

  @override
  void dispose() {
    ThemeSettingsService.isNightMode.removeListener(_onNightModeChanged);
    super.dispose();
  }

  void _onNightModeChanged() {
    if (mounted) setState(() => _isNightMode = ThemeSettingsService.isNightMode.value);
  }

  Future<void> _initVoiceSettings() async {
    await VoiceAlertService().initialize();
    final voices = await VoiceAlertService().getAvailableVoices();
    if (!mounted) return;
    setState(() {
      _availableVoices = voices;
      _selectedVoice = VoiceAlertService().selectedVoiceNotifier.value;
      _selectedTone = VoiceAlertService().toneNotifier.value;
      _isLoadingVoices = false;
    });
  }

  Future<void> _loadCurrentSettings() async {
    final settings = await DriverStorageService.loadSettings();
    if (mounted) {
      setState(() {
        _isBackgroundMode = settings['background'];
        _volume = settings['volume'];
        _outerMeters = settings['outerMeters'];
        _innerMeters = settings['innerMeters'];
      });
    }
  }

  void _persistSettings() {
    DriverStorageService.saveSettings(
      background: _isBackgroundMode,
      volume: _volume,
      outerMeters: _outerMeters,
      innerMeters: _innerMeters,
    );
  }

  // แจ้งเตือนพื้นหลัง (แจ้งเตือนแม้ล็อกหน้าจอ/สลับแอป) — ตอนเปิด ต้องขอสิทธิ์ตำแหน่ง
  // แบบ "ตลอดเวลา" (locationAlways) ก่อน เพราะไม่มีสิทธิ์นี้ ระบบปฏิบัติการจะไม่ยอมให้
  // แอปอัปเดตตำแหน่งต่อเนื่องเบื้องหลังเลย จึงต้องอธิบายเหตุผลให้ผู้ใช้เข้าใจก่อนเสมอ
  // (ไม่ยิง permission dialog ลอยๆ โดยไม่บอกเหตุผล) และถ้าถูกปฏิเสธ ต้องคืนสวิตช์
  // กลับไปเป็นปิดจริง ไม่ปล่อยให้ค้างเป็น "เปิด" ทั้งที่สิทธิ์ไม่ได้ให้จริง
  Future<void> _onBackgroundAlertToggle(bool val) async {
    if (!val) {
      setState(() => _isBackgroundAlertEnabled = false);
      await DriverStorageService.setBackgroundAlertEnabled(false);
      return;
    }

    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) {
      // แพลตฟอร์มอื่น (Windows/Linux/Web) ไม่รองรับ background location จริง
      // ไม่ต้องขอสิทธิ์ แต่ก็ไม่มีผลอะไรจริงบนแพลตฟอร์มนี้เช่นกัน
      setState(() => _isBackgroundAlertEnabled = true);
      await DriverStorageService.setBackgroundAlertEnabled(true);
      return;
    }

    final confirmed = await _showBackgroundAlertRationaleDialog();
    if (confirmed != true) return;

    setState(() => _isRequestingBackgroundPermission = true);
    PermissionStatus status;
    try {
      status = await Permission.locationAlways.request();
    } catch (_) {
      status = PermissionStatus.denied;
    }
    if (!mounted) return;
    setState(() => _isRequestingBackgroundPermission = false);

    if (status.isGranted) {
      setState(() => _isBackgroundAlertEnabled = true);
      await DriverStorageService.setBackgroundAlertEnabled(true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ เปิดแจ้งเตือนพื้นหลังแล้ว'),
            backgroundColor: Color(0xFF10B981),
          ),
        );
      }
    } else {
      // ถูกปฏิเสธ (หรือปฏิเสธถาวร) — คืนสวิตช์กลับไปปิดจริง ไม่ปล่อยให้ค้างว่าเปิด
      // ทั้งที่ไม่มีสิทธิ์จริง (ผิดหลักความซื่อสัตย์ต่อผู้ใช้ของโปรเจกต์นี้)
      setState(() => _isBackgroundAlertEnabled = false);
      await DriverStorageService.setBackgroundAlertEnabled(false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              status.isPermanentlyDenied
                  ? '❌ ไม่ได้รับสิทธิ์ตำแหน่ง "ตลอดเวลา" — กรุณาเปิดเองในตั้งค่าระบบ'
                  : '❌ ไม่ได้รับสิทธิ์ตำแหน่งพื้นหลัง แจ้งเตือนพื้นหลังจึงยังปิดอยู่',
            ),
            backgroundColor: const Color(0xFFEF4444),
            action: status.isPermanentlyDenied
                ? const SnackBarAction(
                    label: 'เปิดตั้งค่า',
                    textColor: Colors.white,
                    onPressed: openAppSettings,
                  )
                : null,
          ),
        );
      }
    }
  }

  Future<bool?> _showBackgroundAlertRationaleDialog() {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('เปิดแจ้งเตือนพื้นหลัง?'),
        content: const Text(
          'ฟีเจอร์นี้ต้องใช้สิทธิ์เข้าถึงตำแหน่งแบบ "ตลอดเวลา" (Always) เพื่อให้แอป '
          'ยังตรวจสอบระยะรถพยาบาลฉุกเฉินและแจ้งเตือนคุณได้ แม้จะสลับไปแอปอื่นหรือ '
          'ล็อกหน้าจอไว้ ระบบจะขอสิทธิ์นี้จากคุณในขั้นตอนถัดไป (บน Android 11 ขึ้นไป '
          'อาจพาไปหน้าตั้งค่าของระบบโดยตรงแทนที่จะเป็นกล่องขอสิทธิ์ในแอป)',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('ยกเลิก'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('ดำเนินการต่อ'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = _isNightMode ? const Color(0xFF121212) : Colors.white;
    final primaryTextColor = _isNightMode ? Colors.white : Colors.black87;
    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                children: [
                  _buildCard(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'ทำงานเบื้องหลัง',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: primaryTextColor,
                              ),
                            ),
                            const Text(
                              '(Background)',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF5B9EE1),
                              ),
                            ),
                          ],
                        ),
                        Switch(
                          value: _isBackgroundMode,
                          activeThumbColor: Colors.white,
                          activeTrackColor: const Color(0xFF5B9EE1),
                          onChanged: (val) {
                            setState(() => _isBackgroundMode = val);
                            _persistSettings();
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // ภาษา / Language — สลับหน้าจอแจ้งเหตุ SOS เป็นภาษาอังกฤษ
                  // (ปัจจุบันครอบคลุมเฉพาะหน้าจอแจ้งเหตุ SOS หน้าจออื่นยังเป็นไทย)
                  _buildCard(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'ภาษา (หน้าแจ้งเหตุ SOS)',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: primaryTextColor,
                              ),
                            ),
                            const Text(
                              'Language (SOS Report screen)',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF5B9EE1),
                              ),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            Text(_isEnglish ? 'EN' : 'ไทย',
                                style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF5B9EE1))),
                            const SizedBox(width: 8),
                            Switch(
                              value: _isEnglish,
                              activeThumbColor: Colors.white,
                              activeTrackColor: const Color(0xFF5B9EE1),
                              onChanged: (val) async {
                                await AppLanguageService.setEnglish(val);
                                if (mounted) setState(() => _isEnglish = val);
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  _buildCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'ระดับเสียง',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: primaryTextColor),
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'Volume',
                              style: TextStyle(fontSize: 12, color: Color(0xFF5B9EE1), fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(Icons.volume_up_rounded, color: primaryTextColor),
                            Expanded(
                              child: Slider(
                                value: _volume,
                                min: 0,
                                max: 100,
                                activeColor: const Color(0xFF5B9EE1),
                                inactiveColor: const Color(0xFFD6E9FF),
                                onChanged: (val) => setState(() => _volume = val),
                                onChangeEnd: (_) => _persistSettings(),
                              ),
                            ),
                            Text(
                              '${_volume.round()}',
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF5B9EE1)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // ระยะตรวจจับเรดาร์ (วงนอกสีฟ้า)
                  _buildCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'ระยะตรวจจับเรดาร์',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: primaryTextColor),
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              '(วงนอกสีฟ้า)',
                              style: TextStyle(fontSize: 12, color: Color(0xFF5B9EE1), fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(Icons.radar_rounded, color: Color(0xFF5B9EE1)),
                            Expanded(
                              child: Slider(
                                value: _outerMeters,
                                min: 20,
                                max: 3000,
                                divisions: 41,
                                activeColor: const Color(0xFF5B9EE1),
                                inactiveColor: const Color(0xFFD6E9FF),
                                onChanged: (val) {
                                  setState(() {
                                    _outerMeters = val;
                                    if (_innerMeters >= _outerMeters) {
                                      _innerMeters = (_outerMeters - 10).clamp(5.0, _outerMeters);
                                    }
                                  });
                                },
                                onChangeEnd: (_) => _persistSettings(),
                              ),
                            ),
                            Text(
                              _outerMeters >= 1000
                                  ? '${(_outerMeters / 1000).toStringAsFixed(1)} KM'
                                  : '${_outerMeters.round()} M',
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF5B9EE1)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // ระยะแจ้งเตือนวิกฤต (วงในสีแดง)
                  _buildCard(
                    borderColor: const Color(0xFFEB5757),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'ระยะแจ้งเตือนวิกฤต',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: primaryTextColor),
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              '(วงในสีแดง)',
                              style: TextStyle(fontSize: 12, color: Color(0xFFEB5757), fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(Icons.warning_amber_rounded, color: Color(0xFFEB5757)),
                            Expanded(
                              child: Slider(
                                value: _innerMeters,
                                min: 5,
                                max: 1200,
                                divisions: 239,
                                activeColor: const Color(0xFFEB5757),
                                inactiveColor: const Color(0xFFFFD6D6),
                                onChanged: (val) {
                                  setState(() {
                                    _innerMeters = val;
                                    if (_innerMeters >= _outerMeters) {
                                      _outerMeters = _innerMeters + 10;
                                    }
                                  });
                                },
                                onChangeEnd: (_) => _persistSettings(),
                              ),
                            ),
                            Text(
                              '${_innerMeters.round()} M',
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFFEB5757)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // ตรวจจับเสียงไซเรนจากไมโครโฟน (Experimental) — สัญญาณเสริมจากเสียง
                  // แยกจากระบบ GPS/MQTT หลัก ต้องใช้ไมโครโฟนตลอดที่เปิดหน้าแผนที่
                  // จึง default ปิดไว้เสมอ และบอกตรงๆ ถ้ายังไม่มีโมเดล AI ให้ใช้งานจริง
                  _buildCard(
                    borderColor: const Color(0xFF06B6D4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'ตรวจจับเสียงไซเรน (ทดลอง)',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: primaryTextColor,
                                    ),
                                  ),
                                  const Text(
                                    'Siren Audio Detection — ใช้ไมโครโฟน',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF06B6D4),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Switch(
                              value: _isSirenDetectionEnabled,
                              activeThumbColor: Colors.white,
                              activeTrackColor: const Color(0xFF06B6D4),
                              onChanged: (val) async {
                                setState(() => _isSirenDetectionEnabled = val);
                                await DriverStorageService.setSirenDetectionEnabled(val);
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _isSirenModelLoaded
                              ? 'ใช้ไมโครโฟนฟังเสียงไซเรนเป็นสัญญาณเสริมจาก GPS '
                                  '(ประมวลผลในเครื่องทั้งหมด ไม่ส่งเสียงออกไปที่ไหน) '
                                  'อาจกินแบตเตอรี่เพิ่มขึ้นเล็กน้อย'
                              : 'ยังไม่มีโมเดล AI สำหรับฟีเจอร์นี้ในเครื่อง '
                                  '(ต้องเทรนโมเดลและวางไฟล์ assets/models/siren_detector.tflite ก่อน) '
                                  'เปิดสวิตช์ไว้ได้ แต่จะยังไม่มีผลอะไรจนกว่าจะมีโมเดลจริง',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: _isSirenModelLoaded
                                ? (_isNightMode ? Colors.white60 : Colors.black54)
                                : const Color(0xFFEA580C),
                            fontWeight: _isSirenModelLoaded ? FontWeight.normal : FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // เสียงพูดแจ้งเตือน (Voice Alert) — เลือกโทนเสียง + เสียง TTS
                  // ของระบบ (ถ้าเครื่องมีให้เลือกหลายตัว)
                  _buildCard(
                    borderColor: const Color(0xFF8B5CF6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'เสียงพูดแจ้งเตือน',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: primaryTextColor,
                          ),
                        ),
                        const Text(
                          'Voice Alert — โทนเสียงและเสียงพูด',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF8B5CF6),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'โทนเสียง',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: primaryTextColor,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: VoiceTone.values.map((tone) {
                            final selected = _selectedTone == tone;
                            return ChoiceChip(
                              label: Text(tone.labelTH),
                              selected: selected,
                              onSelected: (_) async {
                                setState(() => _selectedTone = tone);
                                await VoiceAlertService().setTone(tone);
                              },
                              selectedColor: const Color(0xFF8B5CF6),
                              labelStyle: TextStyle(
                                color: selected ? Colors.white : primaryTextColor,
                                fontWeight: FontWeight.w600,
                              ),
                              backgroundColor: _isNightMode
                                  ? const Color(0xFF1E293B)
                                  : const Color(0xFFF3F4F6),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          'เสียงพูด',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: primaryTextColor,
                          ),
                        ),
                        const SizedBox(height: 6),
                        if (_isLoadingVoices)
                          Text(
                            'กำลังโหลดรายชื่อเสียง...',
                            style: TextStyle(
                                fontSize: 12,
                                color: _isNightMode ? Colors.white60 : Colors.black54),
                          )
                        else if (_availableVoices.isEmpty)
                          Text(
                            'เครื่องนี้ไม่มีเสียง TTS ให้เลือกหลายตัว ใช้เสียง default ของระบบ',
                            style: TextStyle(
                                fontSize: 12,
                                color: _isNightMode ? Colors.white60 : Colors.black54),
                          )
                        else
                          DropdownButton<String>(
                            isExpanded: true,
                            dropdownColor:
                                _isNightMode ? const Color(0xFF1E293B) : Colors.white,
                            value: _selectedVoice != null
                                ? '${_selectedVoice!['name']}|${_selectedVoice!['locale']}'
                                : null,
                            hint: Text(
                              'ใช้เสียง default ของเครื่อง',
                              style: TextStyle(color: primaryTextColor),
                            ),
                            items: _availableVoices.map((v) {
                              final key = '${v['name']}|${v['locale']}';
                              return DropdownMenuItem(
                                value: key,
                                child: Text(
                                  '${v['name']} (${v['locale']})',
                                  style: TextStyle(color: primaryTextColor),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              );
                            }).toList(),
                            onChanged: (key) async {
                              if (key == null) return;
                              final parts = key.split('|');
                              final voice = {
                                'name': parts[0],
                                'locale': parts.sublist(1).join('|'),
                              };
                              setState(() => _selectedVoice = voice);
                              await VoiceAlertService().setSelectedVoice(voice);
                            },
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // แจ้งเตือนพื้นหลัง — ให้ยังได้รับแจ้งเตือนแม้พับแอป/ล็อกหน้าจอ
                  // (ต่างจากสวิตช์ "ทำงานเบื้องหลัง" ด้านบนสุด ซึ่งควบคุมแค่ว่าจะยิง
                  // OS notification หรือไม่ตอนแอปยังเปิดอยู่ — อันนี้ควบคุมว่า GPS/การ
                  // ตรวจสอบระยะจะยังทำงานต่อหรือไม่เมื่อแอปไม่ได้อยู่หน้าจอแล้ว)
                  // default ปิดเสมอเพราะมีต้นทุนแบตเตอรี่และต้องขอสิทธิ์ตำแหน่งเพิ่ม
                  _buildCard(
                    borderColor: const Color(0xFF7C3AED),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'แจ้งเตือนพื้นหลัง',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: primaryTextColor,
                                    ),
                                  ),
                                  const Text(
                                    'แจ้งเตือนแม้ล็อกหน้าจอ/สลับแอป',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF7C3AED),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            _isRequestingBackgroundPermission
                                ? const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(strokeWidth: 2.5),
                                  )
                                : Switch(
                                    value: _isBackgroundAlertEnabled,
                                    activeThumbColor: Colors.white,
                                    activeTrackColor: const Color(0xFF7C3AED),
                                    onChanged: _onBackgroundAlertToggle,
                                  ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'เปิดแล้วแอปจะแสดงการแจ้งเตือนค้างไว้ (Android) และขอสิทธิ์ตำแหน่ง'
                          'แบบ "ตลอดเวลา" — บน iOS ระบบปฏิบัติการอาจจำกัดการทำงานเบื้องหลัง'
                          'เป็นบางครั้งตามข้อจำกัดของ Apple เอง',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: _isNightMode ? Colors.white60 : Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // ดูคำแนะนำการใช้งานแบบละเอียด (Onboarding) ซ้ำอีกครั้ง — เดิมโชว์
                  // แค่ครั้งเดียวตอนเข้าหน้านี้ครั้งแรกหลังล็อกอิน
                  _buildCard(
                    borderColor: const Color(0xFF00A896),
                    child: InkWell(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const OnboardingScreen(
                                role: 'driver', isReplay: true),
                          ),
                        );
                      },
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline_rounded,
                              color: Color(0xFF00A896)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'ดูคำแนะนำการใช้งานอีกครั้ง',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: primaryTextColor,
                              ),
                            ),
                          ),
                          Icon(Icons.chevron_right_rounded,
                              color: _isNightMode
                                  ? Colors.white38
                                  : Colors.black38),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // สอนการใช้งานปุ่มต่างๆ (Coach Mark) — ชี้ตำแหน่งปุ่มจริงบนแผนที่
                  // พร้อมคำอธิบาย เดิมโชว์อัตโนมัติครั้งแรก เปลี่ยนเป็นกดดูเองได้ตาม
                  // ใจที่นี่แทน (ผู้ใช้ขอให้ย้ายมาไว้ในหน้าตั้งค่าแทนการโชว์อัตโนมัติ)
                  _buildCard(
                    borderColor: const Color(0xFF2563EB),
                    child: InkWell(
                      onTap: widget.onShowCoachMark,
                      child: Row(
                        children: [
                          const Icon(Icons.touch_app_rounded,
                              color: Color(0xFF2563EB)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'สอนการใช้งานปุ่มต่างๆ',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: primaryTextColor,
                              ),
                            ),
                          ),
                          Icon(Icons.chevron_right_rounded,
                              color: _isNightMode
                                  ? Colors.white38
                                  : Colors.black38),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard({required Widget child, Color borderColor = const Color(0xFF5B9EE1)}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: _isNightMode ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: borderColor.withValues(alpha: 0.12),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: _isNightMode ? const Color(0xFF1E1E1E) : Colors.white,
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4, offset: const Offset(0, 2)),
        ],
      ),
      child: Center(
        child: Text(
          'RouteAlert',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: _isNightMode ? Colors.white : Colors.black87,
          ),
        ),
      ),
    );
  }
}
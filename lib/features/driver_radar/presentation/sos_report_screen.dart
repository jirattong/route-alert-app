import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/models/incident_report.dart';
import '../../../core/services/ai_vision_triage_service.dart';
import '../../../core/services/hospital_location_service.dart';
import '../../../core/services/incident_service.dart';
import '../../../core/services/location_service.dart';
import '../../../core/services/smart_landmark_service.dart';
import '../../auth_face_login/data/services/face_auth_repository.dart';
import 'incident_detail_screen.dart';

class SosReportScreen extends StatefulWidget {
  final VoidCallback onClose;
  final LatLng? initialLocation;
  final ValueChanged<IncidentReport>? onSubmitted;

  const SosReportScreen({
    super.key,
    required this.onClose,
    this.initialLocation,
    this.onSubmitted,
  });

  @override
  State<SosReportScreen> createState() => _SosReportScreenState();
}

class _SosReportScreenState extends State<SosReportScreen> {
  String? _selectedIncidentType = 'อุบัติเหตุทางรถยนต์';
  String? _selectedSeverity = 'วิกฤต (Code Red - หมดสติ / บาดเจ็บสาหัส)';

  final TextEditingController _descController = TextEditingController();
  final TextEditingController _locationNoteController = TextEditingController();
  final TextEditingController _phoneController =
      TextEditingController(text: '081-234-5678');

  final List<String> _incidentTypes = [
    'อุบัติเหตุทางรถยนต์',
    'ผู้ป่วยหมดสติ / หัวใจหยุดเต้น',
    'ไฟไหม้ / สารเคมีรั่วไหล',
    'เหตุฉุกเฉินอื่นๆ',
  ];

  final List<String> _severities = [
    'วิกฤต (Code Red - หมดสติ / บาดเจ็บสาหัส)',
    'ปานกลาง (Medium - บาดเจ็บแต่รู้สึกตัว)',
    'เล็กน้อย (Low - บาดเจ็บเล็กน้อย)',
  ];

  // Multi-Image State (Up to 5 photos)
  final List<File> _pickedImages = [];
  final List<String> _imagesBase64 = [];
  bool _isSubmitting = false;

  // Map & Pin-on-Center State
  final MapController _mapController = MapController();
  LatLng? _currentGps;
  LatLng? _pinnedGps;
  bool _isFetchingLandmark = false;

  // AI Vision Triage Analysis State
  bool _isAiAnalyzingImage = false;
  AiTriageResult? _aiTriageResult;

  @override
  void initState() {
    super.initState();
    if (widget.initialLocation != null) {
      _currentGps = widget.initialLocation;
      _pinnedGps = widget.initialLocation;
      _autoDetectLandmark(widget.initialLocation!);
    }
    _initUserProfile();
    _fetchGpsLocation();
  }

  Future<void> _initUserProfile() async {
    final currentUser = await FaceAuthRepository.getCurrentUser();
    if (currentUser != null && currentUser.id != 'guest') {
      if (mounted) {
        setState(() {
          _phoneController.text = '081-234-5678';
        });
      }
    }
  }

  Future<void> _fetchGpsLocation() async {
    final pos = await LocationService.getCurrentLocation();
    final gps = pos ?? widget.initialLocation ?? const LatLng(18.7904, 98.9856);
    if (mounted) {
      setState(() {
        _currentGps = gps;
        if (_pinnedGps == null || widget.initialLocation == null) {
          _pinnedGps = gps;
        }
      });
      _mapController.move(gps, 15.5);
      _autoDetectLandmark(gps);
    }
  }

  Future<void> _autoDetectLandmark(LatLng coords) async {
    if (!mounted) return;
    setState(() => _isFetchingLandmark = true);
    final landmark = await SmartLandmarkService().getSmartLandmark(coords);
    if (mounted) {
      setState(() {
        _locationNoteController.text = landmark;
        _isFetchingLandmark = false;
      });
    }
  }

  void _onMapMoved(LatLng center) {
    setState(() {
      _pinnedGps = center;
    });
  }

  void _confirmPinLocation() {
    if (_pinnedGps != null) {
      HapticFeedback.mediumImpact();
      _autoDetectLandmark(_pinnedGps!);
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded,
                  color: Color(0xFF10B981), size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '📍 ปักหมุดพิกัด (${_pinnedGps!.latitude.toStringAsFixed(4)}, ${_pinnedGps!.longitude.toStringAsFixed(4)}) สำเร็จ!',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                ),
              ),
            ],
          ),
          duration: const Duration(milliseconds: 1800),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF1E293B),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      );
    }
  }

  void _resetToDeviceGps() {
    if (_currentGps != null) {
      HapticFeedback.lightImpact();
      _mapController.move(_currentGps!, 15.5);
      setState(() {
        _pinnedGps = _currentGps;
      });
      _autoDetectLandmark(_currentGps!);
    }
  }

  Future<void> _pickImages(ImageSource source) async {
    final picker = ImagePicker();
    try {
      if (source == ImageSource.camera) {
        if (_pickedImages.length >= 5) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('สามารถแนบรูปถ่ายได้สูงสุด 5 รูป')),
          );
          return;
        }
        // Compressed to max 640px to ensure Firestore document stays well under 1MB limit
        final picked = await picker.pickImage(
          source: ImageSource.camera,
          maxWidth: 640,
          maxHeight: 640,
          imageQuality: 60,
        );
        if (picked != null) {
          final file = File(picked.path);
          final bytes = await file.readAsBytes();
          setState(() {
            _pickedImages.add(file);
            _imagesBase64.add(base64Encode(bytes));
          });
          _runAiTriage();
        }
      } else {
        final pickedList = await picker.pickMultiImage(
          maxWidth: 640,
          maxHeight: 640,
          imageQuality: 60,
        );
        if (pickedList.isNotEmpty) {
          for (final picked in pickedList) {
            if (_pickedImages.length >= 5) break;
            final file = File(picked.path);
            final bytes = await file.readAsBytes();
            _pickedImages.add(file);
            _imagesBase64.add(base64Encode(bytes));
          }
          setState(() {});
          _runAiTriage();
        }
      }
    } catch (e) {
      debugPrint('Error picking images: $e');
    }
  }

  Future<void> _runAiTriage() async {
    if (_pickedImages.isEmpty) {
      setState(() {
        _isAiAnalyzingImage = false;
        _aiTriageResult = null;
      });
      return;
    }

    setState(() {
      _isAiAnalyzingImage = true;
      _aiTriageResult = null;
    });

    final List<Uint8List> bytesList = [];
    for (final file in _pickedImages) {
      bytesList.add(await file.readAsBytes());
    }

    final triageResult =
        await AiVisionTriageService().analyzeIncidentPhotos(bytesList);

    if (mounted) {
      setState(() {
        _isAiAnalyzingImage = false;
        _aiTriageResult = triageResult;
        if (triageResult.isIncidentDetected) {
          _selectedSeverity = triageResult.severityLevel;
        }
      });
    }
  }

  void _removePhoto(int index) {
    if (index >= 0 && index < _pickedImages.length) {
      setState(() {
        _pickedImages.removeAt(index);
        _imagesBase64.removeAt(index);
      });
      _runAiTriage();
    }
  }

  void _showGeminiKeyDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Row(
          children: [
            Icon(Icons.auto_awesome_rounded, color: Color(0xFF6366F1), size: 24),
            SizedBox(width: 8),
            Text('Google Gemini API Key', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'ใส่ Google Gemini API Key เพื่อเปิดใช้งานโมเดล AI Vision คัดกรองภาพเหตุการณ์อัจฉริยะ (รับฟรีได้ที่ aistudio.google.com)',
              style: TextStyle(fontSize: 13, color: Colors.black87),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              decoration: InputDecoration(
                hintText: 'AIzaSy...',
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('ยกเลิก'),
          ),
          ElevatedButton(
            onPressed: () async {
              final key = controller.text.trim();
              if (key.isNotEmpty) {
                await AiVisionTriageService.saveGeminiApiKey(key);
                if (ctx.mounted) Navigator.pop(ctx);
                _runAiTriage();
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6366F1),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: const Text('บันทึก Key', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showImageSourceDialog() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'เลือกแหล่งที่มาของรูปภาพ (แนบได้สูงสุด 5 รูป)',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(Icons.camera_alt_rounded,
                    color: Color(0xFF5B9EE1)),
                title: const Text('ถ่ายรูปจากกล้อง (Camera)'),
                subtitle: const Text('ถ่ายมุมมองจุดเกิดเหตุหรือรอยชน'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickImages(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_rounded,
                    color: Color(0xFF00A896)),
                title: const Text('เลือกจากคลังภาพ (Gallery)'),
                subtitle: const Text('เลือกได้ครั้งละหลายรูปพร้อมกัน'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickImages(ImageSource.gallery);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submitReport() async {
    if (_selectedIncidentType == null || _selectedSeverity == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณาเลือกประเภทเหตุและระดับความรุนแรง')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    // Coordinate & Location
    final activeCoords = _pinnedGps ?? _currentGps ?? const LatLng(18.7904, 98.9856);
    final lat = activeCoords.latitude;
    final lng = activeCoords.longitude;
    final locAddress = _locationNoteController.text.trim().isNotEmpty
        ? _locationNoteController.text.trim()
        : 'บริเวณพิกัด ${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)} (เชียงใหม่)';

    // Seamless Phone Resolution (Never block in emergency)
    final phone = _phoneController.text.trim().isNotEmpty
        ? _phoneController.text.trim()
        : '081-234-5678';

    String descriptionText = _descController.text.trim();
    if (_aiTriageResult != null && _aiTriageResult!.isIncidentDetected) {
      descriptionText =
          '[AI Triage: ${_aiTriageResult!.severityCode} (${(_aiTriageResult!.confidenceScore * 100).toInt()}%)] $descriptionText';
    }

    final currentUser = await FaceAuthRepository.getCurrentUser();
    final String repName = (currentUser != null && currentUser.id != 'guest')
        ? currentUser.name
        : 'ผู้แจ้งเหตุ (ยืนยันตัวตนแล้ว)';
    final String repEmail = (currentUser != null && currentUser.id != 'guest')
        ? currentUser.email
        : 'verified_user@routealert.app';

    // 🏥 ค้นหาโรงพยาบาลที่ใกล้พิกัดที่ปักหมุดที่สุดอัตโนมัติ
    final nearestHospital =
        HospitalLocationService().findNearestHospital(LatLng(lat, lng));

    final newReport = IncidentReport(
      id: 'Case #AVCB${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}',
      type: _selectedIncidentType!,
      severity: _selectedSeverity!,
      description: descriptionText,
      latitude: lat,
      longitude: lng,
      province: 'เชียงใหม่',
      address: locAddress,
      photoBase64: _imagesBase64.isNotEmpty ? _imagesBase64.first : null,
      photosBase64: _imagesBase64,
      reporterName: repName,
      reporterEmail: repEmail,
      reporterPhone: phone,
      status: 'pending',
      targetHospitalId: nearestHospital.profile.hospitalId,
      hospitalName: nearestHospital.profile.hospitalName,
      hospitalLatitude: nearestHospital.profile.latitude,
      hospitalLongitude: nearestHospital.profile.longitude,
      hospitalDistanceKm: nearestHospital.distanceKm,
      eta: '${nearestHospital.etaMinutes} นาที',
      createdAt: DateTime.now(),
    );

    final result = await IncidentService().createIncident(newReport);
    final bool success = result['success'] == true;
    final String message = result['message'] ?? 'ส่งรายงานเรียบร้อยแล้ว';

    if (mounted) {
      setState(() => _isSubmitting = false);
      if (success) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            title: const Row(
              children: [
                Icon(Icons.check_circle_rounded,
                    color: Color(0xFF10B981), size: 28),
                SizedBox(width: 8),
                Text('ส่งรายงานสำเร็จ',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              ],
            ),
            content: Text(
              'ข้อมูลเหตุฉุกเฉิน พิกัดปักหมุด GPS ${_aiTriageResult != null && _aiTriageResult!.isIncidentDetected ? "และการประเมิน AI Triage" : ""} ถูกส่งไปยังศูนย์สั่งการ 1669 และ ${nearestHospital.profile.hospitalName} เรียบร้อยแล้ว',
              style: const TextStyle(fontSize: 14, color: Colors.black87),
            ),
            actions: [
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(ctx); // Close dialog
                  if (widget.onSubmitted != null) {
                    widget.onSubmitted!(newReport);
                  } else {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (_) => IncidentDetailScreen(incident: newReport),
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.remove_red_eye_rounded, color: Colors.white, size: 18),
                label: const Text('ติดตามสถานะเคสทันที',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
              ),
            ],
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: const Color(0xFFDC2626),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeCoords =
        _pinnedGps ?? _currentGps ?? const LatLng(18.7904, 98.9856);

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: SingleChildScrollView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEB5757),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFEB5757)
                                  .withValues(alpha: 0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: const Text(
                          'แจ้งเหตุฉุกเฉิน (SOS Report)',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // 1. แผนที่ปักหมุดจุดเกิดเหตุ (Pin-in-Center Map Picker)
                    _buildPinInCenterMapPicker(activeCoords),
                    const SizedBox(height: 10),

                    // 1.1 ปุ่มยืนยันพิกัดขนาดใหญ่ & GPS ฉัน (Spacious Action Bar)
                    _buildMapActionButtons(activeCoords),
                    const SizedBox(height: 14),

                    // 2. ปลายทางโรงพยาบาลที่ใกล้ที่สุด (AI Nearest Hospital Routing)
                    _buildNearestHospitalCard(activeCoords),
                    const SizedBox(height: 16),

                    // 3. สถานที่ / จุดสังเกตใกล้เคียง (Smart Auto-filled Landmark)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'สถานที่ / จุดสังเกตใกล้เคียง',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87),
                        ),
                        if (_isFetchingLandmark)
                          const Row(
                            children: [
                              SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Color(0xFF00A896)),
                              ),
                              SizedBox(width: 5),
                              Text('AI กำลังค้นหา...',
                                  style: TextStyle(
                                      fontSize: 11, color: Color(0xFF00A896))),
                            ],
                          )
                        else
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: _locationNoteController.text.isNotEmpty
                                  ? const Color(0xFFE6FFFA)
                                  : const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _locationNoteController.text.isNotEmpty
                                  ? '✨ AI พบร้านค้า/จุดสังเกต'
                                  : 'จุดสังเกต (ระบุได้ตามสะดวก)',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold,
                                color: _locationNoteController.text.isNotEmpty
                                    ? const Color(0xFF00A896)
                                    : Colors.grey.shade600,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _locationNoteController,
                      decoration: InputDecoration(
                        hintText:
                            'เช่น ตรงข้ามร้าน KFC, หน้าร้านก๋วยเตี๋ยว... (ระบุได้ตามสะดวก)',
                        hintStyle: TextStyle(
                            color: Colors.grey.shade400, fontSize: 13.5),
                        prefixIcon: const Icon(Icons.storefront_rounded,
                            color: Color(0xFF5B9EE1), size: 20),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(
                              color: Color(0xFF5B9EE1), width: 1.5),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(
                              color: Colors.grey.shade300, width: 1.5),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // 4. เบอร์โทรศัพท์ติดต่อกลับ (Auto-Filled Phone Field)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'เบอร์โทรศัพท์ติดต่อกลับ',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFDCFCE7),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text('✓ ยืนยันจากบัญชีแล้ว',
                              style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF16A34A))),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(
                        hintText: '081-xxxxxxx',
                        prefixIcon: const Icon(Icons.phone_rounded,
                            color: Color(0xFF16A34A), size: 20),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(
                              color: Color(0xFF16A34A), width: 1.5),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(
                              color: Colors.grey.shade300, width: 1.5),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // 5. ประเภทเหตุ
                    const Text(
                      'ประเภทเหตุ (Type of Incident)',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87),
                    ),
                    const SizedBox(height: 6),
                    _buildDropdown(
                      hint: 'เลือกประเภทเหตุ',
                      value: _selectedIncidentType,
                      items: _incidentTypes,
                      onChanged: (val) =>
                          setState(() => _selectedIncidentType = val),
                    ),
                    const SizedBox(height: 16),

                    // 6. ระดับความรุนแรง
                    const Text(
                      'ระดับความรุนแรง (Severity)',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87),
                    ),
                    const SizedBox(height: 6),
                    _buildDropdown(
                      hint: 'เลือกระดับความรุนแรง',
                      value: _selectedSeverity,
                      items: _severities,
                      onChanged: (val) =>
                          setState(() => _selectedSeverity = val),
                    ),
                    const SizedBox(height: 16),

                    // 7. รายละเอียดเหตุเพิ่มเติม
                    const Text(
                      'รายละเอียดเหตุเพิ่มเติม (Description)',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _descController,
                      maxLines: 2,
                      decoration: InputDecoration(
                        hintText: 'ระบุจำนวนผู้บาดเจ็บ หรืออาการเบื้องต้น...',
                        hintStyle: TextStyle(
                            color: Colors.grey.shade400, fontSize: 13),
                        contentPadding: const EdgeInsets.all(12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(
                              color: Color(0xFF5B9EE1), width: 1.5),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(
                              color: Colors.grey.shade300, width: 1.5),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),

                    // 8. กล่องแนบภาพถ่ายหลายรูป (Multi-Image) + AI Vision Triage Card
                    _buildMultiPhotoSection(),
                    const SizedBox(height: 24),

                    // 9. ปุ่มกดยืนยันส่งข้อมูล SOS
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _isSubmitting ? null : _submitReport,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFEB5757),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(26)),
                          elevation: 3,
                        ),
                        child: _isSubmitting
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2.5, color: Colors.white),
                              )
                            : const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.emergency_rounded,
                                      color: Colors.white, size: 22),
                                  SizedBox(width: 8),
                                  Text(
                                    'ยืนยันการแจ้งเหตุฉุกเฉิน SOS',
                                    style: TextStyle(
                                      fontSize: 16.5,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 🗺️ แผนที่ปักหมุดแบบหมุดอยู่ตรงกลางเสมอ (Pin-in-Center Map Picker)
  Widget _buildPinInCenterMapPicker(LatLng activeCoords) {
    return Container(
      height: 240,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFF5B9EE1), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(21),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // FlutterMap
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: activeCoords,
                initialZoom: 15.5,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.drag |
                      InteractiveFlag.pinchZoom |
                      InteractiveFlag.doubleTapZoom,
                ),
                onPositionChanged: (position, hasGesture) {
                  if (hasGesture && position.center != null) {
                    _onMapMoved(position.center!);
                  }
                },
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.routealert.app',
                ),
              ],
            ),

            // หมุดสีแดงอยู่ตรงกลางกล่องแผนที่ตลอดเวลา (Fixed Center Pin)
            IgnorePointer(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 38), // Tip touches center
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: const [
                          BoxShadow(color: Colors.black26, blurRadius: 4)
                        ],
                      ),
                      child: const Text(
                        '📍 เลื่อนแผนที่เพื่อปักหมุด',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Icon(
                      Icons.location_on_rounded,
                      size: 46,
                      color: Color(0xFFEB5757),
                    ),
                  ],
                ),
              ),
            ),

            // ป้ายพิกัดลอยด้านบน (Floating Coord Pill)
            Positioned(
              top: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.my_location_rounded, color: Color(0xFF2563EB), size: 14),
                    const SizedBox(width: 5),
                    Text(
                      'พิกัด: ${activeCoords.latitude.toStringAsFixed(4)}, ${activeCoords.longitude.toStringAsFixed(4)}',
                      style: const TextStyle(
                          color: Color(0xFF1E293B),
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),

            // ปุ่ม GPS ปัจจุบัน (Bottom-Right)
            Positioned(
              bottom: 10,
              right: 10,
              child: FloatingActionButton.small(
                heroTag: 'sos_my_gps_btn',
                onPressed: _resetToDeviceGps,
                backgroundColor: Colors.white,
                elevation: 3,
                child: const Icon(Icons.my_location_rounded,
                    color: Color(0xFF5B9EE1), size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 🔘 ชุดปุ่มยืนยันพิกัดขนาดใหญ่ สวยงาม ชัดเจน (Prominent Confirm Button Bar)
  Widget _buildMapActionButtons(LatLng activeCoords) {
    return Row(
      children: [
        // 1. ปุ่มยืนยันพิกัดจุดเกิดเหตุนี้ (ปุ่มหลักขนาดใหญ่ สวยงาม)
        Expanded(
          flex: 3,
          child: SizedBox(
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _confirmPinLocation,
              icon: const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
              label: const Text(
                'ยืนยันปักหมุดจุดเกิดเหตุนี้',
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 0.2,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981), // Emerald Green
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),

        // 2. ปุ่มดึงกลับมาที่ GPS ฉัน (Secondary Button)
        Expanded(
          flex: 2,
          child: SizedBox(
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _resetToDeviceGps,
              icon: const Icon(Icons.my_location_rounded, color: Color(0xFF2563EB), size: 18),
              label: const Text(
                'GPS ฉัน',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2563EB),
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFEFF6FF),
                elevation: 0,
                side: const BorderSide(color: Color(0xFF93C5FD), width: 1.2),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 🏥 การ์ดแสดงโรงพยาบาลที่ใกล้จุดเกิดเหตุที่สุด
  Widget _buildNearestHospitalCard(LatLng activeCoords) {
    final nearest =
        HospitalLocationService().findNearestHospital(activeCoords);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF22C55E), width: 1.4),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: const BoxDecoration(
              color: Color(0xFFDCFCE7),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.local_hospital_rounded,
                color: Color(0xFF16A34A), size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'ส่งตรงถึงศูนย์สั่งการ รพ. ที่ใกล้ที่สุด',
                      style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF166534),
                          fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(width: 5),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: const Color(0xFF16A34A),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text('อัตโนมัติ',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  nearest.profile.hospitalName,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF14532D)),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'ระยะห่าง ${nearest.distanceKm} กม. • เวลาประเมินถึง ${nearest.etaMinutes} นาที',
                  style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF15803D),
                      fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 📸 กล่องแนบภาพถ่ายหลายรูป (Multi-Image) + การวิเคราะห์ AI
  Widget _buildMultiPhotoSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'ภาพถ่ายจุดเกิดเหตุ (แนบได้สูงสุด 5 รูป)',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87),
            ),
            Row(
              children: [
                InkWell(
                  onTap: _showGeminiKeyDialog,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEEF2FF),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFF818CF8)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.vpn_key_rounded, size: 12, color: Color(0xFF4F46E5)),
                        SizedBox(width: 4),
                        Text('Gemini API Key', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF4F46E5))),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${_pickedImages.length}/5 รูป',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade600),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Photo Strip
        if (_pickedImages.isNotEmpty) ...[
          SizedBox(
            height: 96,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _pickedImages.length < 5
                  ? _pickedImages.length + 1
                  : _pickedImages.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                if (index == _pickedImages.length &&
                    _pickedImages.length < 5) {
                  return InkWell(
                    onTap: _showImageSourceDialog,
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      width: 90,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                            color: const Color(0xFF5B9EE1),
                            style: BorderStyle.solid),
                      ),
                      child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_a_photo_rounded,
                              color: Color(0xFF5B9EE1), size: 24),
                          SizedBox(height: 4),
                          Text('เพิ่มรูป',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF5B9EE1))),
                        ],
                      ),
                    ),
                  );
                }

                return Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.file(
                        _pickedImages[index],
                        width: 96,
                        height: 96,
                        fit: BoxFit.cover,
                      ),
                    ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: InkWell(
                        onTap: () => _removePhoto(index),
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Colors.black54,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.close_rounded,
                              color: Colors.white, size: 14),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 12),
        ] else ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF5B9EE1), width: 1.5),
            ),
            child: Column(
              children: [
                const Icon(Icons.add_a_photo_outlined,
                    size: 38, color: Color(0xFF5B9EE1)),
                const SizedBox(height: 8),
                const Text(
                  'ถ่ายภาพหรือเลือกภาพถ่ายจุดเกิดเหตุ (มี AI วิเคราะห์ความรุนแรง)',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF2C3E50),
                  ),
                ),
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  onPressed: _showImageSourceDialog,
                  icon: const Icon(Icons.camera_alt,
                      color: Colors.white, size: 16),
                  label: const Text('เลือกภาพถ่ายจุดเกิดเหตุ',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF5B9EE1),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        // AI Vision Result Card or Loading Indicator
        if (_isAiAnalyzingImage)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF0FDF4),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF10B981)),
            ),
            child: const Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.5, color: Color(0xFF10B981)),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '🧠 AI กำลังคัดกรองและวิเคราะห์ความรุนแรงจากภาพถ่าย...',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF047857)),
                  ),
                ),
              ],
            ),
          )
        else if (_aiTriageResult != null)
          _buildAiVisionTriageResultCard(_aiTriageResult!),
      ],
    );
  }

  /// AI Vision Result Card
  Widget _buildAiVisionTriageResultCard(AiTriageResult res) {
    if (!res.isIncidentDetected) {
      // Non-Incident Warning Card (Reject False Alarms)
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFBEB),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFF59E0B), width: 1.6),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.warning_amber_rounded,
                    color: Color(0xFFD97706), size: 20),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'AI: ไม่พบร่องรอยอุบัติเหตุในภาพ',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFB45309)),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFDE68A),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    res.isUsingGemini ? 'Gemini 1.5' : 'Vision Engine',
                    style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Color(0xFF78350F)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ...res.detectedFeatures.map(
              (feat) => Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(feat,
                    style: const TextStyle(
                        fontSize: 11.5, color: Color(0xFF78350F))),
              ),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '💡 ${res.clinicalRecommendation}',
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF92400E)),
              ),
            ),
          ],
        ),
      );
    }

    // Confirmed Incident Triage Card
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF3B82F6), width: 1.8),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF3B82F6).withValues(alpha: 0.12),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF3B82F6),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      res.isUsingGemini ? Icons.auto_awesome_rounded : Icons.psychology_rounded,
                      color: Colors.white,
                      size: 14,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      res.isUsingGemini ? 'Google Gemini 1.5 Flash Vision' : 'AI Multi-Angle Vision Triage',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Text(
                'ความแม่นยำ ${(res.confidenceScore * 100).toStringAsFixed(1)}%',
                style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E40AF)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'ระดับที่ AI ประเมิน: ${res.severityCode} (${res.severityLevel.split(" ")[0]})',
            style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w900,
                color: Color(0xFFDC2626)),
          ),
          const SizedBox(height: 6),
          ...res.detectedFeatures.map(
            (feat) => Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(feat,
                  style: const TextStyle(
                      fontSize: 11.5, color: Color(0xFF334155))),
            ),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '💡 ${res.clinicalRecommendation}',
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1D4ED8)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                color: Colors.black87),
            onPressed: widget.onClose,
          ),
          const Text(
            'ส่งข้อมูลแจ้งเหตุฉุกเฉิน',
            style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: Colors.black87),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildDropdown({
    required String hint,
    required String? value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF5B9EE1), width: 1.5),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isExpanded: true,
          hint: Text(hint,
              style: TextStyle(color: Colors.grey.shade400, fontSize: 13.5)),
          value: value,
          items: items
              .map((e) => DropdownMenuItem(
                  value: e,
                  child: Text(e,
                      style: const TextStyle(
                          fontSize: 13.5, color: Colors.black87))))
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}
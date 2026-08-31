import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/models/incident_report.dart';
import '../../../core/services/incident_service.dart';
import '../../../core/services/location_service.dart';
import '../../../core/services/ai_vision_triage_service.dart';
import '../../auth_face_login/data/services/face_auth_repository.dart';

class SosReportScreen extends StatefulWidget {
  final VoidCallback onClose;

  const SosReportScreen({super.key, required this.onClose});

  @override
  State<SosReportScreen> createState() => _SosReportScreenState();
}

class _SosReportScreenState extends State<SosReportScreen> {
  String? _selectedIncidentType = 'อุบัติเหตุทางรถยนต์';
  String? _selectedSeverity = 'วิกฤต (Code Red - หมดสติ / บาดเจ็บสาหัส)';

  final TextEditingController _descController = TextEditingController();
  final TextEditingController _locationNoteController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();

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

  File? _pickedImage;
  String? _imageBase64;
  bool _isSubmitting = false;
  LatLng? _currentGps;
  bool _isLoadingGps = true;

  // AI Vision Triage Analysis State
  bool _isAiAnalyzingImage = false;
  AiTriageResult? _aiTriageResult;

  @override
  void initState() {
    super.initState();
    _fetchGpsLocation();
  }

  Future<void> _fetchGpsLocation() async {
    final pos = await LocationService.getCurrentLocation();
    if (mounted) {
      setState(() {
        _currentGps = pos ?? const LatLng(19.0284, 99.8962);
        _isLoadingGps = false;
      });
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 75,
      );

      if (picked != null) {
        final file = File(picked.path);
        final bytes = await file.readAsBytes();

        setState(() {
          _pickedImage = file;
          _imageBase64 = base64Encode(bytes);
          _isAiAnalyzingImage = true;
          _aiTriageResult = null;
        });

        // Run Deep CNN Vision Triage on Image
        final triageResult =
            await AiVisionTriageService().analyzeIncidentPhoto(bytes);

        if (mounted) {
          setState(() {
            _isAiAnalyzingImage = false;
            _aiTriageResult = triageResult;
            // Auto-preselect severity based on AI prediction
            _selectedSeverity = triageResult.severityLevel;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isAiAnalyzingImage = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ไม่สามารถเลือกรูปภาพได้: $e')),
        );
      }
    }
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
                'เลือกแหล่งที่มาของรูปภาพ',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(Icons.camera_alt_rounded, color: Color(0xFF5B9EE1)),
                title: const Text('ถ่ายรูปจากกล้อง (Camera)'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickImage(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_rounded, color: Color(0xFF00A896)),
                title: const Text('เลือกจากคลังภาพ (Gallery)'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickImage(ImageSource.gallery);
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

    final phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.orangeAccent,
          content: Text('⚠️ กรุณาระบุเบอร์โทรศัพท์ติดต่อกลับ เพื่อให้เจ้าหน้าที่ 1669 โทรยืนยันเหตุ'),
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    final lat = _currentGps?.latitude ?? 19.0284;
    final lng = _currentGps?.longitude ?? 99.8962;
    final locAddress = _locationNoteController.text.trim().isNotEmpty
        ? _locationNoteController.text.trim()
        : 'บริเวณพิกัด ${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)} (เชียงใหม่)';

    String descriptionText = _descController.text.trim();
    if (_aiTriageResult != null) {
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

    final newReport = IncidentReport(
      id: 'Case #AVCB${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}',
      type: _selectedIncidentType!,
      severity: _selectedSeverity!,
      description: descriptionText,
      latitude: lat,
      longitude: lng,
      province: 'เชียงใหม่',
      address: locAddress,
      photoBase64: _imageBase64,
      reporterName: repName,
      reporterEmail: repEmail,
      reporterPhone: phone,
      status: 'pending',
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
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            title: const Row(
              children: [
                Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 28),
                SizedBox(width: 8),
                Text('ส่งรายงานสำเร็จ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              ],
            ),
            content: Text(
              'ข้อมูลเหตุฉุกเฉิน พิกัด GPS ${_aiTriageResult != null ? "และการวิเคราะห์ AI Triage" : ""} ถูกส่งไปยังศูนย์สั่งการ 1669 และโรงพยาบาลในพื้นที่เรียบร้อยแล้ว',
              style: const TextStyle(fontSize: 14, color: Colors.black87),
            ),
            actions: [
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  widget.onClose();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF5B9EE1),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: const Text('ตกลง', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEB5757),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFEB5757).withValues(alpha: 0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: const Text(
                          'แจ้งเหตุฉุกเฉิน (SOS Report)',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // พิกัด GPS อัตโนมัติ
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE2F0FE),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFF5B9EE1).withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.my_location_rounded, color: Color(0xFF5B9EE1), size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _isLoadingGps
                                ? const Text(
                                    'กำลังค้นหาพิกัด GPS ปัจจุบัน...',
                                    style: TextStyle(fontSize: 12.5, color: Color(0xFF2C3E50)),
                                  )
                                : Text(
                                    'พิกัดที่เกิดเหตุ: ${_currentGps!.latitude.toStringAsFixed(4)}, ${_currentGps!.longitude.toStringAsFixed(4)} (GPS ล็อคแล้ว)',
                                    style: const TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF2C3E50),
                                    ),
                                  ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),

                    // ประเภทเหตุ
                    const Text(
                      'ประเภทเหตุ (Type of Incident)',
                      style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold, color: Colors.black87),
                    ),
                    const SizedBox(height: 8),
                    _buildDropdown(
                      hint: 'เลือกประเภทเหตุ',
                      value: _selectedIncidentType,
                      items: _incidentTypes,
                      onChanged: (val) => setState(() => _selectedIncidentType = val),
                    ),
                    const SizedBox(height: 18),

                    // ระดับความรุนแรง
                    const Text(
                      'ระดับความรุนแรง (Severity)',
                      style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold, color: Colors.black87),
                    ),
                    const SizedBox(height: 8),
                    _buildDropdown(
                      hint: 'เลือกระดับความรุนแรง',
                      value: _selectedSeverity,
                      items: _severities,
                      onChanged: (val) => setState(() => _selectedSeverity = val),
                    ),
                    const SizedBox(height: 18),

                    // สถานที่ / จุดสังเกต
                    const Text(
                      'สถานที่ / จุดสังเกตเพิ่มเติม (Location Note)',
                      style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold, color: Colors.black87),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _locationNoteController,
                      decoration: InputDecoration(
                        hintText: 'เช่น หน้าปั๊ม ปตท. ทางหลวงหมายเลข 107',
                        hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13.5),
                        prefixIcon: const Icon(Icons.location_on_outlined, color: Color(0xFF5B9EE1), size: 20),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(color: Color(0xFF5B9EE1), width: 1.5),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(color: Colors.grey.shade300, width: 1.5),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),

                    // รายละเอียดเหตุ
                    const Text(
                      'รายละเอียดเหตุเพิ่มเติม (Description)',
                      style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold, color: Colors.black87),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _descController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: 'ระบุจำนวนผู้บาดเจ็บ หรืออาการเบื้องต้น...',
                        hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13.5),
                        contentPadding: const EdgeInsets.all(14),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(color: Color(0xFF5B9EE1), width: 1.5),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(color: Colors.grey.shade300, width: 1.5),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // กล่องเลือกรูปภาพ + AI Vision Triage Card
                    if (_pickedImage != null) ...[
                      Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: Image.file(
                              _pickedImage!,
                              height: 180,
                              width: double.infinity,
                              fit: BoxFit.cover,
                            ),
                          ),
                          Positioned(
                            top: 10,
                            right: 10,
                            child: InkWell(
                              onTap: () => setState(() {
                                _pickedImage = null;
                                _imageBase64 = null;
                                _aiTriageResult = null;
                              }),
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: const BoxDecoration(
                                  color: Colors.black54,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.close_rounded, color: Colors.white, size: 18),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // 🧠 AI Deep Learning Vision Analysis Result Card
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
                                child: CircularProgressIndicator(strokeWidth: 2.5, color: Color(0xFF10B981)),
                              ),
                              SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  '🧠 AI Deep Learning (CNN) กำลังวิเคราะห์ระดับความรุนแรงจากภาพถ่าย...',
                                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Color(0xFF047857)),
                                ),
                              ),
                            ],
                          ),
                        )
                      else if (_aiTriageResult != null)
                        _buildAiVisionTriageResultCard(_aiTriageResult!),
                    ] else
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: const Color(0xFF5B9EE1), width: 1.5),
                        ),
                        child: Column(
                          children: [
                            const Icon(Icons.add_a_photo_outlined, size: 44, color: Color(0xFF5B9EE1)),
                            const SizedBox(height: 10),
                            const Text(
                              'ถ่ายรูปภาพจุดเกิดเหตุ (มี AI วิเคราะห์ความรุนแรงอัตโนมัติ)',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF2C3E50),
                              ),
                            ),
                            const SizedBox(height: 14),
                            ElevatedButton.icon(
                              onPressed: _showImageSourceDialog,
                              icon: const Icon(Icons.camera_alt, color: Colors.white, size: 18),
                              label: const Text('เลือกภาพถ่ายจุดเกิดเหตุ', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF5B9EE1),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              ),
                            ),
                          ],
                        ),
                      ),

                    const SizedBox(height: 24),

                    // ปุ่มกดยืนยันส่งข้อมูล
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _isSubmitting ? null : _submitReport,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFEB5757),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                          elevation: 3,
                        ),
                        child: _isSubmitting
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                              )
                            : const Text(
                                'ยืนยันการแจ้งเหตุฉุกเฉิน SOS',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// AI Vision Result Card
  Widget _buildAiVisionTriageResultCard(AiTriageResult res) {
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
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF3B82F6),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text('🧠 AI CNN Vision Triage', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
              ),
              const Spacer(),
              Text(
                'ความแม่นยำ ${(res.confidenceScore * 100).toStringAsFixed(1)}%',
                style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Color(0xFF1E40AF)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'ระดับที่ AI ประเมิน: ${res.severityCode} (${res.severityLevel.split(" ")[0]})',
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w900, color: Color(0xFFDC2626)),
          ),
          const SizedBox(height: 6),
          ...res.detectedFeatures.map(
            (feat) => Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(feat, style: const TextStyle(fontSize: 11.5, color: Color(0xFF334155))),
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
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF1D4ED8)),
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
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.black87),
            onPressed: widget.onClose,
          ),
          const Text(
            'ส่งข้อมูลแจ้งเหตุฉุกเฉิน',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.black87),
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
          hint: Text(hint, style: TextStyle(color: Colors.grey.shade400, fontSize: 13.5)),
          value: value,
          items: items.map((e) => DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(fontSize: 13.5, color: Colors.black87)))).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}
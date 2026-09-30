import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/services/location_service.dart';
import '../../../core/widgets/my_location_button.dart';
import '../../../core/services/hospital_location_service.dart';
import '../../../core/services/push_notification_service.dart';
import '../../auth_face_login/data/services/face_auth_repository.dart';
import 'agency_main_screen.dart';

/// ขั้นตอนบังคับหลังสมัครบัญชี role "agency" สำเร็จ — ให้กรอกข้อมูล/ปักหมุด
/// โรงพยาบาลของตัวเองก่อนเข้าใช้งานจริง เพิ่มตอนทำ multi-hospital เพราะเดิม
/// บัญชี agency ทุกบัญชีใช้ HospitalLocationService profile เดียวกันหมด
/// (HOSP-01) ไม่เคยมีขั้นตอนถามข้อมูลโรงพยาบาลตอนสมัครเลยสักนิด
///
/// ใช้ pattern แผนที่แตะเพื่อปักหมุดแบบเดียวกับ _showHospitalPinPickerModal()
/// ใน agency_home_screen.dart (และ hospital_pin_edit_dialog.dart ฝั่งเว็บ)
class HospitalSetupScreen extends StatefulWidget {
  final String email;

  const HospitalSetupScreen({super.key, required this.email});

  @override
  State<HospitalSetupScreen> createState() => _HospitalSetupScreenState();
}

class _HospitalSetupScreenState extends State<HospitalSetupScreen> {
  LatLng _pinLocation = const LatLng(19.0284, 99.8962); // เชียงใหม่ ค่าเริ่มต้น
  final MapController _mapController = MapController();
  bool _userMovedPin = false;

  @override
  void initState() {
    super.initState();
    // เริ่มที่ตำแหน่งปัจจุบันเลย (ส่วนใหญ่ตั้งค่าตอนอยู่ที่โรงพยาบาล) ไม่ต้องเลื่อนหาไกลๆ
    LocationService.getCurrentLocationOrNull().then((point) {
      if (point != null && mounted && !_userMovedPin) _moveTo(point);
    });
  }

  void _moveTo(LatLng point) {
    setState(() => _pinLocation = point);
    // GPS อาจตอบกลับก่อนแผนที่วาดเสร็จ — ย้ายหลังเฟรมถัดไปแทน
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        _mapController.move(point, 17);
      } catch (_) {}
    });
  }
  final _nameCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void dispose() {
    _mapController.dispose();
    _nameCtrl.dispose();
    _addressCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    if (_nameCtrl.text.trim().isEmpty ||
        _addressCtrl.text.trim().isEmpty ||
        _phoneCtrl.text.trim().isEmpty) {
      setState(() => _errorMessage = 'กรุณากรอกชื่อ ที่อยู่ และเบอร์โทร ER ให้ครบ');
      return;
    }
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final hospitalId = await HospitalLocationService().createHospital(
        location: _pinLocation,
        hospitalName: _nameCtrl.text.trim(),
        address: _addressCtrl.text.trim(),
        erPhone: _phoneCtrl.text.trim(),
      );
      await FaceAuthRepository.updateHospitalId(widget.email, hospitalId);
      // เส้นทางสมัคร agency ใหม่ไม่ผ่าน _navigateToRoleScreen() ของ
      // face_login_screen.dart (ไปหน้านี้แทน) จึงต้องลงทะเบียน push
      // notification เองตรงนี้ด้วย (เพิ่มตอนทำระบบแจ้งเตือนเบื้องหลัง)
      unawaited(PushNotificationService().initialize(widget.email));

      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AgencyMainScreen()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _errorMessage = 'บันทึกไม่สำเร็จ ลองใหม่อีกครั้ง';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // ห้ามกดย้อนกลับ/ปัดออกจากขั้นตอนนี้ — ทุกบัญชี agency ต้องมีโรงพยาบาล
    // เป็นของตัวเองก่อนถึงจะใช้งานต่อได้ ไม่ใช่ขั้นตอนที่ข้ามได้
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '🏥 ตั้งค่าโรงพยาบาลของคุณ',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                const Text(
                  'ก่อนใช้งาน ให้ระบุข้อมูลโรงพยาบาล/ศูนย์สั่งการของคุณก่อน — เคสที่แจ้งเข้า'
                  'มาในระบบจะถูกส่งมาที่โรงพยาบาลนี้อัตโนมัติเมื่ออยู่ใกล้ที่สุด',
                  style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                ),
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: SizedBox(
                    height: 260,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        FlutterMap(
                          mapController: _mapController,
                          options: MapOptions(
                            initialCenter: _pinLocation,
                            initialZoom: 13,
                            onTap: (_, point) =>
                                setState(() {
                                  _userMovedPin = true;
                                  _pinLocation = point;
                                }),
                          ),
                          children: [
                            TileLayer(
                              urlTemplate:
                                  'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                              userAgentPackageName: 'com.routealert.app',
                            ),
                            MarkerLayer(markers: [
                              Marker(
                                point: _pinLocation,
                                width: 52,
                                height: 52,
                                child: const Icon(Icons.location_on_rounded,
                                    size: 48, color: Color(0xFF00A896)),
                              ),
                            ]),
                          ],
                        ),
                        Positioned(
                          top: 10,
                          left: 12,
                          right: 12,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.black87,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Text(
                              'แตะบนแผนที่เพื่อปักหมุด — พิกัด: '
                              '${_pinLocation.latitude.toStringAsFixed(5)}, '
                              '${_pinLocation.longitude.toStringAsFixed(5)}',
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 11.5),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                        Positioned(
                          right: 12,
                          bottom: 12,
                          child: MyLocationButton(
                            onLocated: (point) {
                              _userMovedPin = true;
                              _moveTo(point);
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _nameCtrl,
                  decoration: InputDecoration(
                    labelText: 'ชื่อโรงพยาบาล / ศูนย์สั่งการ',
                    prefixIcon: const Icon(Icons.local_hospital_rounded,
                        color: Color(0xFF00A896)),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _addressCtrl,
                  decoration: InputDecoration(
                    labelText: 'ที่อยู่',
                    prefixIcon: const Icon(Icons.place_rounded,
                        color: Color(0xFF00A896)),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _phoneCtrl,
                  decoration: InputDecoration(
                    labelText: 'เบอร์สายด่วนห้องฉุกเฉิน (ER Hotline)',
                    prefixIcon: const Icon(Icons.phone_in_talk_rounded,
                        color: Color(0xFF00A896)),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 10),
                  Text(_errorMessage!,
                      style: const TextStyle(color: Colors.red, fontSize: 12.5)),
                ],
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: _isSaving ? null : _handleSave,
                    icon: _isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.save_rounded, color: Colors.white),
                    label: Text(
                      _isSaving ? 'กำลังบันทึก...' : '💾 บันทึกและเริ่มใช้งาน',
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Colors.white),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00A896),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

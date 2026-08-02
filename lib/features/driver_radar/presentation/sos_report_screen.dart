import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class SosReportScreen extends StatefulWidget {
  const SosReportScreen({super.key});

  @override
  State<SosReportScreen> createState() => _SosReportScreenState();
}

class _SosReportScreenState extends State<SosReportScreen> {
  // ตัวแปรเก็บค่า Dropdown
  String? _selectedIncidentType;
  String? _selectedSeverity;

  // ตัวแปรเก็บไฟล์รูปภาพที่เลือก
  File? _selectedImage;
  final ImagePicker _picker = ImagePicker();

  // รายการตัวเลือก ประเภทเหตุ
  final List<String> _incidentTypes = [
    'เกิดอุบัติเหตุรถชน (Car Accident)',
    'การจราจรติดขัดรุนแรง / ทางปิด (Traffic Jam)',
    'สิ่งกีดขวางบนท้องถนน (Road Obstruction)',
    'รถเสีย / ต้องการความช่วยเหลือ (Vehicle Breakdown)',
    'เหตุฉุกเฉินอื่นๆ (Other Emergency)',
  ];

  // รายการตัวเลือก ระดับความรุนแรง
  final List<String> _severityLevels = [
    'ต่ำ - ไม่กระทบการจราจร (Low)',
    'ปานกลาง - การจราจรชะลอตัว (Medium)',
    'สูง - ปิดการจราจร / มีผู้บาดเจ็บ (High)',
    'วิกฤต - ต้องการรถพยาบาลด่วน (Critical)',
  ];

  // ฟังก์ชันเลือกรูปภาพ (จากกล้อง หรือ แกลเลอรี)
  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: source,
        maxWidth: 1080,
        maxHeight: 1080,
        imageQuality: 85,
      );

      if (pickedFile != null) {
        setState(() {
          _selectedImage = File(pickedFile.path);
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ไม่สามารถเลือกรูปภาพได้: $e')),
      );
    }
  }

  // แสดง Modal ตัวเลือกแหล่งที่มาของรูปภาพ (กล้อง / แกลเลอรี)
  void _showImagePickerModal() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'เลือกแหล่งที่มาของรูปภาพ',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                ListTile(
                  leading: const Icon(Icons.camera_alt_rounded, color: Color(0xFF5B9EE1)),
                  title: const Text('ถ่ายภาพจากกล้อง (Camera)'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _pickImage(ImageSource.camera);
                  },
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.photo_library_rounded, color: Color(0xFF5B9EE1)),
                  title: const Text('เลือกจากแกลเลอรี (Gallery)'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _pickImage(ImageSource.gallery);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // --- 1. Header Bar ด้านบนตาม Figma ---
            _buildHeader(),

            // --- 2. ฟอร์มกรอกข้อมูล SOS ---
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // --- หัวข้อ 1: ประเภทเหตุ ---
                    _buildLabel('ประเภทเหตุ'),
                    const SizedBox(height: 6),
                    _buildDropdownField(
                      hint: 'Type of incident',
                      value: _selectedIncidentType,
                      items: _incidentTypes,
                      onChanged: (val) => setState(() => _selectedIncidentType = val),
                    ),

                    const SizedBox(height: 20),

                    // --- หัวข้อ 2: ระดับความรุนแรง ---
                    _buildLabel('ระดับความรุนแรง'),
                    const SizedBox(height: 6),
                    _buildDropdownField(
                      hint: 'Severity',
                      value: _selectedSeverity,
                      items: _severityLevels,
                      onChanged: (val) => setState(() => _selectedSeverity = val),
                    ),

                    const SizedBox(height: 24),

                    // --- หัวข้อ 3: กล่องอัปโหลดรูปภาพ ---
                    _buildUploadBox(),

                    const SizedBox(height: 28),

                    // --- ปุ่มส่ง (Send) สีน้ำเงิน ---
                    _buildButton(
                      text: 'ส่ง (Send)',
                      color: const Color(0xFF5B9EE1),
                      onPressed: () {
                        if (_selectedIncidentType == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('กรุณาเลือกประเภทเหตุ')),
                          );
                          return;
                        }
                        
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('ส่งรายงานเหตุฉุกเฉิน SOS เรียบร้อยแล้ว!'),
                            backgroundColor: Colors.green,
                          ),
                        );
                        Navigator.pop(context); // กลับไปยังหน้าแรก
                      },
                    ),

                    const SizedBox(height: 14),

                    // --- ปุ่มยกเลิก (Cancel) สีแดง ---
                    _buildButton(
                      text: 'ยกเลิก (Cancel)',
                      color: const Color(0xFFEB5757),
                      onPressed: () {
                        Navigator.pop(context); // ยกเลิกแล้วกลับหน้าเดิม
                      },
                    ),

                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),

      // --- 3. Bottom Navigation Bar ---
      bottomNavigationBar: _buildBottomNavigationBar(),
    );
  }

  // --- Header แถบบนพร้อมโลโก้ RouteAlert ---
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFF2C3E50), width: 2),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                const Icon(Icons.airport_shuttle_outlined,
                    size: 20, color: Color(0xFF2C3E50)),
                Positioned(
                  top: 4,
                  right: 4,
                  child: Icon(Icons.wifi,
                      size: 9, color: Colors.redAccent.shade700),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          const Text(
            'RouteAlert',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  // --- Helper: ป้ายชื่อหัวข้อ ---
  Widget _buildLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.bold,
        color: Colors.black87,
      ),
    );
  }

  // --- Helper: Dropdown Custom Style ตาม Figma ---
  Widget _buildDropdownField({
    required String hint,
    required String? value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF5B9EE1), width: 1.5),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          hint: Text(
            hint,
            style: TextStyle(
              color: Colors.grey.shade400,
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
          isExpanded: true,
          icon: const Icon(
            Icons.keyboard_arrow_down_rounded,
            color: Color(0xFF5B9EE1),
            size: 28,
          ),
          items: items.map((String item) {
            return DropdownMenuItem<String>(
              value: item,
              child: Text(
                item,
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.black87,
                ),
              ),
            );
          }).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  // --- Helper: กล่องเลือกรูปภาพอัปโหลดตาม Figma ---
  Widget _buildUploadBox() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF5B9EE1), width: 1.5),
      ),
      child: Column(
        children: [
          if (_selectedImage != null) ...[
            // ถ้าเลือกรูปแล้ว ให้แสดงรูปภาพตัวอย่าง
            Stack(
              alignment: Alignment.topRight,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.file(
                    _selectedImage!,
                    height: 160,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.cancel, color: Colors.red, size: 28),
                  onPressed: () {
                    setState(() => _selectedImage = null);
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
          ] else ...[
            // ไอคอนอัปโหลดวงกลมสีฟ้า
            Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(
                color: Color(0xFF8BB7F0),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.cloud_upload_outlined,
                color: Colors.white,
                size: 30,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'เลือกรูปภาพเพื่ออัปโหลด',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const Text(
              '(Select Photo To Upload)',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.black54,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'รองรับการอัปโหลด .JPG , .PNG , .HEIC',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade500,
              ),
            ),
            Text(
              '(Supported Format .JPG , .PNG , .HEIC)',
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade400,
              ),
            ),
            const SizedBox(height: 16),
          ],

          // ปุ่ม "เลือกไฟล์ (Select File)"
          ElevatedButton.icon(
            onPressed: _showImagePickerModal,
            icon: const Text(
              'เลือกไฟล์ (Select File)',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            label: const Icon(Icons.file_upload_outlined, color: Colors.white, size: 20),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF5B9EE1),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              elevation: 0,
            ),
          ),
        ],
      ),
    );
  }

  // --- Helper: ปุ่มกดขนาดใหญ่ (ส่ง / ยกเลิก) ---
  Widget _buildButton({
    required String text,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(25),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.35),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(25),
          ),
          elevation: 0,
        ),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  // --- Bottom Navigation Bar ---
  Widget _buildBottomNavigationBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: BottomNavigationBar(
        currentIndex: 0,
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.white,
        selectedItemColor: const Color(0xFF2C3E50),
        unselectedItemColor: Colors.grey.shade400,
        showSelectedLabels: false,
        showUnselectedLabels: false,
        elevation: 0,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.map_rounded, size: 28),
            label: 'Map',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.airport_shuttle_outlined, size: 28),
            label: 'Ambulance',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings_outlined, size: 28),
            label: 'Settings',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline_rounded, size: 28),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
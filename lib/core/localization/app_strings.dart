import '../services/app_language_service.dart';

/// พจนานุกรมข้อความไทย/อังกฤษแบบง่าย (คู่กับ AppLanguageService)
/// ปัจจุบันครอบคลุมหน้าจอแจ้งเหตุ SOS เป็นหลัก — เพิ่ม key ใหม่ตรงนี้เพื่อขยาย
/// ความครอบคลุมไปหน้าจออื่นได้เรื่อยๆ โดยไม่กระทบของเดิม
class AppStrings {
  static const Map<String, ({String th, String en})> _dict = {
    'sos_header_title': (
      th: 'ส่งข้อมูลแจ้งเหตุฉุกเฉิน',
      en: 'Submit Emergency Report',
    ),
    'sos_photo_picker_title': (
      th: 'เลือกแหล่งที่มาของรูปภาพ (แนบได้สูงสุด 5 รูป)',
      en: 'Choose photo source (up to 5 photos)',
    ),
    'sos_photo_camera_title': (th: 'ถ่ายรูปจากกล้อง (Camera)', en: 'Take a Photo (Camera)'),
    'sos_photo_camera_subtitle': (
      th: 'ถ่ายมุมมองจุดเกิดเหตุหรือรอยชน',
      en: 'Capture the scene or damage',
    ),
    'sos_photo_gallery_title': (th: 'เลือกจากคลังภาพ (Gallery)', en: 'Choose from Gallery'),
    'sos_photo_gallery_subtitle': (
      th: 'เลือกได้ครั้งละหลายรูปพร้อมกัน',
      en: 'Select multiple photos at once',
    ),
    'sos_location_note_label': (
      th: 'สถานที่ / จุดสังเกตใกล้เคียง',
      en: 'Location / Nearby Landmark',
    ),
    'sos_location_note_hint': (
      th: 'เช่น ตรงข้ามร้าน KFC, หน้าร้านก๋วยเตี๋ยว... (ระบุได้ตามสะดวก)',
      en: 'e.g. Opposite KFC, in front of the noodle shop... (optional)',
    ),
    'sos_phone_label': (th: 'เบอร์โทรศัพท์ติดต่อกลับ', en: 'Callback Phone Number'),
    'sos_phone_verified': (th: '✓ ยืนยันจากบัญชีแล้ว', en: '✓ Verified from account'),
    'sos_type_label': (th: 'ประเภทเหตุ (Type of Incident)', en: 'Type of Incident'),
    'sos_type_hint': (th: 'เลือกประเภทเหตุ', en: 'Select incident type'),
    'sos_severity_label': (th: 'ระดับความรุนแรง (Severity)', en: 'Severity'),
    'sos_severity_hint': (th: 'เลือกระดับความรุนแรง', en: 'Select severity level'),
    'sos_description_label': (
      th: 'รายละเอียดเหตุเพิ่มเติม (Description)',
      en: 'Additional Description',
    ),
    'sos_description_hint': (
      th: 'ระบุจำนวนผู้บาดเจ็บ หรืออาการเบื้องต้น...',
      en: 'Number of injured, initial condition...',
    ),
    'sos_submit_button': (
      th: 'ยืนยันการแจ้งเหตุฉุกเฉิน SOS',
      en: 'Confirm Emergency SOS Report',
    ),
    'sos_max_photos_warning': (
      th: 'สามารถแนบรูปถ่ายได้สูงสุด 5 รูป',
      en: 'You can attach up to 5 photos',
    ),
    'sos_missing_fields_warning': (
      th: 'กรุณาเลือกประเภทเหตุและระดับความรุนแรง',
      en: 'Please select incident type and severity',
    ),
    'sos_success_title': (th: 'ส่งรายงานสำเร็จ', en: 'Report Submitted'),
    'sos_track_case_button': (
      th: 'ติดตามสถานะเคสทันที',
      en: 'Track Case Status Now',
    ),
  };

  /// แปล key เป็นข้อความตามภาษาปัจจุบัน (ถ้าไม่มี key ให้คืน key กลับไปเพื่อกันแอปพัง)
  static String t(String key) {
    final entry = _dict[key];
    if (entry == null) return key;
    return AppLanguageService.isEnglish.value ? entry.en : entry.th;
  }
}

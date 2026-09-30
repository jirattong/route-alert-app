import 'dart:convert';

/// บันทึกผลที่วัดได้จริง 1 แถว — tools/multi_user_sim/src/results_doc.mjs ดึงไปทำตารางผลการทดลอง
/// ผูกกับสถานการณ์ผ่านรหัส [Sxx]/[Gxx] ในชื่อเทสต์ที่เรียกฟังก์ชันนี้
void scenarioResult({required String condition, required String expected, required String actual}) {
  // ignore: avoid_print
  print('@@RESULT ${jsonEncode({'condition': condition, 'expected': expected, 'actual': actual})}');
}

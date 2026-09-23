import 'dart:async';
import 'package:flutter/material.dart';

/// กล่องยืนยันเปลี่ยนสถานะเคส พร้อมคูลดาวน์นับถอยหลัง (ดีฟอลต์ 3 วินาที) ก่อนกด
/// ยืนยันได้จริง — กันไม่ให้เผลอกดเปลี่ยนสถานะเคสพลาดโดยไม่ตั้งใจ
///
/// เดิมมีแค่ในหน้ารายละเอียดเคส (`ambulance_incident_detail_screen.dart`) ดึงออก
/// มาเป็นฟังก์ชันกลางตรงนี้เพื่อใช้ซ้ำกับปุ่มอัปเดตสถานะด่วนบนหน้าหลัก
/// (`ambulance_home_screen.dart`) ด้วย — ปุ่มบนหน้าหลักเดิมกดครั้งเดียวทำงานเลย
/// ไม่มีการยืนยันใดๆ ต่างจากหน้ารายละเอียดที่ป้องกันไว้แล้ว
Future<void> showStatusConfirmDialog({
  required BuildContext context,
  required String nextTitle,
  required String nextDesc,
  required Future<void> Function() onConfirmed,
  int cooldownSeconds = 3,
}) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      int cooldownSec = cooldownSeconds;
      return StatefulBuilder(
        builder: (context, setModalState) {
          Timer? timer;
          if (cooldownSec > 0) {
            timer = Timer.periodic(const Duration(seconds: 1), (t) {
              if (cooldownSec > 0) {
                setModalState(() => cooldownSec--);
              } else {
                t.cancel();
              }
            });
          }

          return Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
              side: const BorderSide(color: Color(0xFFEB5757), width: 2),
            ),
            backgroundColor: Colors.white,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: const BoxDecoration(
                      color: Color(0xFFFFEAEA),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.published_with_changes_rounded,
                      size: 44,
                      color: Color(0xFFEB5757),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'ยืนยันเปลี่ยนสถานะ ?',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'เปลี่ยนเป็น: "$nextTitle"',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFEB5757),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '($nextDesc)',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            timer?.cancel();
                            Navigator.pop(ctx);
                          },
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            side: BorderSide(color: Colors.grey.shade400),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                          ),
                          child: Text(
                            'ยกเลิก',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: cooldownSec == 0
                              ? () async {
                                  timer?.cancel();
                                  Navigator.pop(ctx);
                                  await onConfirmed();
                                }
                              : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFEB5757),
                            disabledBackgroundColor: Colors.grey.shade300,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                          ),
                          child: Text(
                            cooldownSec > 0
                                ? 'รอ ($cooldownSec วิ)'
                                : 'ยืนยันอัปเดต',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: cooldownSec > 0
                                  ? Colors.grey.shade600
                                  : Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

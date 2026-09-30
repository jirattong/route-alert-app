import 'package:flutter/material.dart';

import '../../../core/models/incident_report.dart';
import '../../../core/services/ambulance_storage_service.dart';
import '../../../core/services/incident_service.dart';

/// การรับเคสของรถพยาบาล — ใช้ร่วมกันระหว่างปุ่มในรายการเคสและปุ่ม "รับเคส" บนแจ้งเตือน
/// เคสเดียวรับได้หลายคัน: เคสที่มีรถแล้วจะเป็นการ "ร่วมรับเคส" (ถามยืนยันก่อน)
class AmbulanceCaseActions {
  static final Set<String> _inFlight = {};

  /// คืนเคสล่าสุดหลังพยายามรับ (null ถ้าโหลดเคสไม่ได้เลย)
  static Future<IncidentReport?> acceptCase(
      BuildContext context, IncidentReport incident) async {
    // กดซ้ำระหว่างรอผล (ปุ่มในรายการ + ปุ่มบนแจ้งเตือน) ไม่ต้องยิงซ้ำ
    if (!_inFlight.add(incident.id)) return incident;
    try {
      return await _accept(context, incident);
    } finally {
      _inFlight.remove(incident.id);
    }
  }

  /// ข้อความเมื่อเลื่อนสถานะไม่สำเร็จ (null = สำเร็จ)
  static String? progressProblem(ProgressOutcome outcome) {
    switch (outcome) {
      case ProgressOutcome.updated:
      case ProgressOutcome.alreadyPast: // รถอีกคันในเคสเลื่อนไปก่อนแล้ว
        return null;
      case ProgressOutcome.caseClosed:
        return 'เคสนี้ถูกปิดหรือจบไปแล้ว ไม่ต้องอัปเดตสถานะต่อ';
      case ProgressOutcome.notFound:
        return 'ไม่พบเคสนี้ในระบบแล้ว';
      case ProgressOutcome.failed:
        return '⚠️ อัปเดตสถานะไม่สำเร็จ เช็คสัญญาณอินเทอร์เน็ตแล้วลองใหม่';
    }
  }

  static Future<IncidentReport?> _accept(
      BuildContext context, IncidentReport incident) async {
    final messenger = ScaffoldMessenger.of(context);
    void show(String text, Color color) => messenger.showSnackBar(SnackBar(
          content: Text(text),
          backgroundColor: color,
          duration: const Duration(seconds: 4),
        ));

    final profile = await AmbulanceStorageService.loadProfile();
    final myUnit = profile['ambulanceId']!;
    final myPlate = profile['plateNumber']!;

    // ปุ่มบนแจ้งเตือนอาจถูกกดทีหลังนานแล้ว เช็คสถานะจริงล่าสุดจาก Firestore ก่อน
    final fresh =
        await IncidentService().getIncidentById(incident.id, forceRemote: true) ??
            incident;
    if (fresh.hasUnit(myUnit, plate: myPlate)) {
      show('รถของคุณอยู่ในเคสนี้แล้ว', const Color(0xFF00A896));
      return fresh;
    }
    if (fresh.isClosed) {
      show('เคสนี้ปิดหรือจบไปแล้ว', const Color(0xFFF59E0B));
      return fresh;
    }
    if (!fresh.isJoinable) {
      show('เคสนี้เริ่มนำส่งผู้ป่วยแล้ว ไม่รับรถเพิ่ม', const Color(0xFFF59E0B));
      return fresh;
    }

    // รถพยาบาลคันเดียวรับได้ทีละ 1 เคส (เช็คจาก cache ก่อน — transaction เช็คซ้ำอีกชั้น)
    final busyIds = await IncidentService().getBusyAmbulanceIds();
    final busyKeys = await IncidentService().getBusyVehicleKeys();
    if (busyIds.contains(myUnit) ||
        busyKeys.contains(AssignedUnit.vehicleKeyFor(myPlate, myUnit))) {
      show('⚠️ รถของคุณมีเคสที่กำลังดำเนินการอยู่แล้ว ต้องทำเคสปัจจุบันให้เสร็จก่อนถึงจะรับเคสใหม่ได้',
          const Color(0xFFF59E0B));
      return fresh;
    }

    if (fresh.vehicleCount > 0) {
      if (!context.mounted) return fresh;
      final join = await _confirmJoin(context, fresh);
      if (join != true) return fresh;
    }

    final result = await IncidentService().assignAmbulance(
      id: fresh.id,
      ambulanceId: myUnit,
      ambulancePlate: myPlate,
      ambulanceCallSign: profile['callSign'],
      selfAccepted: true,
    );
    final latest = result.incident ?? fresh;
    switch (result.outcome) {
      case DispatchOutcome.assigned:
        show('🔴 ยืนยันรับเคสและบันทึกหมายเรียบร้อยแล้ว!', const Color(0xFFEB5757));
      case DispatchOutcome.joined:
        show('🚑 ร่วมรับเคสแล้ว — ตอนนี้มี ${latest.vehicleCount} คันกำลังดำเนินเคส',
            const Color(0xFFEB5757));
      case DispatchOutcome.alreadyMine:
        show('รถของคุณอยู่ในเคสนี้แล้ว', const Color(0xFF00A896));
      case DispatchOutcome.vehicleBusy:
        show('⚠️ รถของคุณมีเคสอื่นที่ยังไม่จบ (${result.busyCaseId}) ต้องทำเคสนั้นให้เสร็จก่อน',
            const Color(0xFFDC2626));
      case DispatchOutcome.caseClosed:
        show('เคสนี้ปิดหรือจบไปแล้ว', const Color(0xFFF59E0B));
      case DispatchOutcome.notJoinable:
        show('เคสนี้เริ่มนำส่งผู้ป่วยแล้ว ไม่รับรถเพิ่ม', const Color(0xFFF59E0B));
      case DispatchOutcome.notFound:
        show('ไม่พบเคสนี้ในระบบแล้ว', const Color(0xFFF59E0B));
      case DispatchOutcome.alreadyHasVehicles:
      case DispatchOutcome.failed:
        show('⚠️ รับเคสไม่สำเร็จ (เช็คสัญญาณอินเทอร์เน็ต) กรุณาลองใหม่', const Color(0xFFDC2626));
    }
    return result.ok ? await IncidentService().getIncidentById(fresh.id) ?? latest : latest;
  }

  static Future<bool?> _confirmJoin(BuildContext context, IncidentReport incident) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('ร่วมรับเคสนี้?'),
        content: Text(
          'ตอนนี้มี ${incident.vehicleCount} คันกำลังดำเนินเคสนี้อยู่แล้ว\n'
          '(${incident.vehiclesLabel})\n\n'
          'ร่วมรับเคสเมื่อต้องการรถเพิ่ม เช่น ผู้บาดเจ็บหลายคน — รถของคุณจะรับเคสอื่นไม่ได้จนกว่าเคสนี้จะจบ',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ยกเลิก')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFEB5757)),
            child: const Text('ร่วมรับเคส'),
          ),
        ],
      ),
    );
  }
}

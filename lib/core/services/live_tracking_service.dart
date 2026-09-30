import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';

import '../models/incident_report.dart';
import 'critical_notification_service.dart';
import 'incident_service.dart';
import 'notification_intent.dart';

/// สิ่งที่แสดงบนหน้าล็อก/Dynamic Island (iOS) หรือแจ้งเตือนค้าง (Android) ตอนนี้
@immutable
class TrackingState {
  final String incidentId;
  final String incidentType;
  // pending | enroute | near | arrived | transport | done
  final String phase;
  final String title;
  final String subtitle;
  final int? etaMinutes;
  final int? distanceMeters;
  final double progress;
  final bool ended;
  // ETA นี้ถือว่าเก่าเมื่อไหร่ (null = ช่วงที่ไม่มี ETA เช่นรอยืนยัน/ถึงแล้ว) —
  // หน้าล็อก iOS ใช้แสดง "กำลังรอตำแหน่งล่าสุดของรถ"
  final DateTime? staleAt;

  const TrackingState({
    required this.incidentId,
    required this.incidentType,
    required this.phase,
    required this.title,
    required this.subtitle,
    required this.etaMinutes,
    required this.distanceMeters,
    required this.progress,
    required this.ended,
    this.staleAt,
  });

  Map<String, dynamic> toChannelArgs() => {
        'incidentId': incidentId,
        'incidentType': incidentType,
        'phase': phase,
        'title': title,
        'subtitle': subtitle,
        'etaMinutes': etaMinutes,
        'distanceMeters': distanceMeters,
        'progress': progress,
        'staleInSeconds': staleAt?.difference(DateTime.now()).inSeconds,
      };

  String get detailLine {
    final parts = <String>[
      if (subtitle.isNotEmpty) subtitle,
      if (etaMinutes != null) 'อีกราว $etaMinutes นาที',
      if (distanceMeters != null) formatDistance(distanceMeters!),
    ];
    return parts.join(' · ');
  }

  static String formatDistance(int meters) => meters >= 1000
      ? '${(meters / 1000).toStringAsFixed(1)} กม.'
      : '$meters ม.';

  @override
  bool operator ==(Object other) =>
      other is TrackingState &&
      other.incidentId == incidentId &&
      other.phase == phase &&
      other.title == title &&
      other.subtitle == subtitle &&
      other.etaMinutes == etaMinutes &&
      other.distanceMeters == distanceMeters &&
      (other.progress - progress).abs() < 0.01 &&
      other.ended == ended &&
      other.staleAt == staleAt;

  @override
  int get hashCode =>
      Object.hash(incidentId, phase, title, subtitle, etaMinutes, distanceMeters, ended);
}

/// ติดตามรถพยาบาลที่กำลังมาหาผู้แจ้งเหตุแบบสด (เหมือน Grab) — ใช้ ETA/ระยะที่แอป
/// รถพยาบาลส่งขึ้น Firestore ไม่ต้องใช้ push (ใช้ได้กับบัญชี Apple ฟรี) แต่แอปต้องยัง
/// ทำงานอยู่ จึงเปิด [keepAlive] ให้หน้าผู้ขับขี่ใช้ GPS เบื้องหลังระหว่างมีเคสที่รออยู่
class LiveTrackingService with WidgetsBindingObserver {
  static final LiveTrackingService instance = LiveTrackingService._();
  LiveTrackingService._();

  static const MethodChannel _channel = MethodChannel('com.routealert/live_activity');
  static const _etaFreshFor = Duration(minutes: 3);
  static const _activeWindow = Duration(hours: 12);
  // เคสที่ไม่มีใครรับเลย (เช่นเคสทดสอบที่ลืมไว้) ไม่ต้องติดตาม/เปิด GPS เบื้องหลังนานขนาดนั้น
  static const _pendingWindow = Duration(hours: 2);

  /// true ระหว่างผู้ใช้มีเคสที่ยังไม่จบ — หน้าผู้ขับขี่ใช้ค่านี้เปิด GPS เบื้องหลัง
  final ValueNotifier<bool> keepAlive = ValueNotifier(false);

  String? _email;
  StreamSubscription<List<IncidentReport>>? _sub;
  Timer? _ticker;
  List<IncidentReport> _lastList = const [];
  String? _currentId;
  TrackingState? _lastApplied;
  bool _retryNativeOnResume = false;
  String? _legKey;
  int _legMaxMeters = 0;
  // เรียก native ทีละคำสั่งตามลำดับ กัน start ซ้อนกันจนเกิด Live Activity ซ้ำ
  Future<void> _nativeChain = Future.value();

  void _enqueueNative(Future<void> Function() task) {
    _nativeChain = _nativeChain.then((_) => task()).catchError((Object e) {
      debugPrint('LiveTrackingService native error: $e');
    });
  }

  bool get _isIOS => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
  bool get _isAndroid => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> start(String email) async {
    final clean = email.trim().toLowerCase();
    if (_email == clean && _sub != null) return;
    await stop();
    _email = clean;
    WidgetsBinding.instance.addObserver(this);
    await IncidentService().ensureInitialized();
    if (_email != clean) return;
    _onIncidents(await IncidentService().getLocalIncidents());
    // แอปถูกปิดไปรอบก่อน อาจมีของค้าง (Live Activity/แจ้งเตือนติดตามของเคสที่จบไปแล้ว)
    _enqueueNative(() => _cleanupExcept(_currentId));
    _sub = IncidentService().incidentsStream.listen(_onIncidents);
    // ETA ที่ไม่ได้อัปเดตนานต้องถูกซ่อน แม้ไม่มีข้อมูลใหม่เข้ามา
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) => _onIncidents(_lastList));
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    _ticker?.cancel();
    _ticker = null;
    WidgetsBinding.instance.removeObserver(this);
    _email = null;
    _enqueueNative(() => _cleanupExcept(null));
    await _nativeChain;
    _currentId = null;
    _lastApplied = null;
    _lastList = const [];
    keepAlive.value = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // iOS เริ่ม Live Activity ได้เฉพาะตอนแอปอยู่หน้าจอ — ถ้าเคสมาตอนพับแอป ลองใหม่ตอนเปิดกลับมา
    if (state == AppLifecycleState.resumed && _retryNativeOnResume) {
      final last = _lastApplied;
      _lastApplied = null;
      if (last != null) _enqueueNative(() => _apply(last));
    }
  }

  void _onIncidents(List<IncidentReport> list) {
    final email = _email;
    if (email == null) return;
    _lastList = list;
    final now = DateTime.now();

    final trackedId = _currentId;
    if (trackedId != null) {
      final tracked = list.where((i) => i.id == trackedId).firstOrNull;
      if (tracked == null || _isClosed(tracked) || tracked.archived) {
        _currentId = null;
        _lastApplied = null;
        final finalState =
            tracked == null ? null : stateFor(tracked, now, legMaxMeters: _legMaxMeters);
        _enqueueNative(() => _endNative(trackedId, finalState));
      }
    }

    final active = pickActive(list, email, now);
    keepAlive.value = active != null;
    if (active == null) return;

    if (active.id != _currentId) {
      final previous = _currentId;
      if (previous != null) _enqueueNative(() => _endNative(previous, null));
      _currentId = active.id;
      _lastApplied = null;
    }
    final legKey = '${active.id}|${active.ambulanceEtaTarget ?? ''}';
    if (legKey != _legKey) {
      _legKey = legKey;
      _legMaxMeters = 0;
    }
    final meters = active.ambulanceDistanceMeters;
    if (meters != null && meters > _legMaxMeters) _legMaxMeters = meters;

    final state = stateFor(active, now, legMaxMeters: _legMaxMeters);
    if (state == _lastApplied) return;
    _lastApplied = state;
    _enqueueNative(() => _apply(state));
  }

  static bool _isClosed(IncidentReport i) =>
      i.status == 'resolved' || i.status == 'cancelled';

  /// เคสล่าสุดที่ผู้ใช้คนนี้แจ้งและยังไม่จบ
  static IncidentReport? pickActive(
      List<IncidentReport> list, String email, DateTime now) {
    final me = email.trim().toLowerCase();
    if (me.isEmpty) return null;
    IncidentReport? best;
    for (final i in list) {
      if (i.reporterEmail.trim().toLowerCase() != me) continue;
      if (_isClosed(i) || i.archived) continue;
      final age = now.difference(i.createdAt);
      if (age > _activeWindow || (i.status == 'pending' && age > _pendingWindow)) continue;
      if (best == null || i.createdAt.isAfter(best.createdAt)) best = i;
    }
    return best;
  }

  static TrackingState stateFor(IncidentReport i, DateTime now, {int legMaxMeters = 0}) {
    final unit = i.reporterUnitLabel;
    final type = i.type.isNotEmpty ? i.type : 'เหตุฉุกเฉิน';
    // นาฬิกาเครื่องรถพยาบาลเดินเร็วกว่า → อย่าให้ ETA ดูสดเกินจริง
    final updatedAt = i.ambulanceEtaUpdatedAt == null
        ? null
        : (i.ambulanceEtaUpdatedAt!.isAfter(now) ? now : i.ambulanceEtaUpdatedAt!);
    final etaFresh = updatedAt != null && now.difference(updatedAt) <= _etaFreshFor;

    TrackingState build(String phase, String title, String subtitle,
            {String? etaTarget, double fallbackProgress = 0, bool ended = false}) {
      final useEta = etaTarget != null && etaFresh && i.ambulanceEtaTarget == etaTarget;
      final eta = useEta ? i.ambulanceEtaMinutes : null;
      final meters = useEta ? i.ambulanceDistanceMeters : null;
      var progress = fallbackProgress;
      if (meters != null && legMaxMeters > 0) {
        progress = (1 - meters / legMaxMeters).clamp(0.03, 0.97).toDouble();
      }
      return TrackingState(
        incidentId: i.id,
        incidentType: type,
        phase: phase,
        title: title,
        subtitle: subtitle,
        etaMinutes: eta == null ? null : (eta < 1 ? 1 : eta),
        distanceMeters: meters,
        progress: progress,
        ended: ended,
        // ช่วงที่ควรมี ETA: เก่าเมื่อครบ 3 นาทีหลังอัปเดตล่าสุด (ไม่มีเลย = เก่าแล้ว)
        staleAt: etaTarget == null || ended
            ? null
            : (useEta ? updatedAt.add(_etaFreshFor) : now),
      );
    }

    switch (i.status) {
      case 'resolved':
        return build('done', 'ถึงโรงพยาบาลเรียบร้อยแล้ว', i.hospitalName ?? unit,
            fallbackProgress: 1, ended: true);
      case 'cancelled':
        return build('done', 'ยกเลิกเคสแล้ว', type, fallbackProgress: 0, ended: true);
      case 'pending':
        return build('pending', 'รอโรงพยาบาลยืนยันเคส', type);
      case 'at_scene':
      case 'in_progress':
        return build('arrived', 'รถพยาบาลถึงจุดเกิดเหตุแล้ว', unit, fallbackProgress: 1);
      case 'transporting':
      case 'approaching_er':
        return build('transport', 'กำลังนำส่ง ${i.hospitalName ?? 'โรงพยาบาล'}', unit,
            etaTarget: 'hospital', fallbackProgress: 0.05);
      default:
        if (i.statusStep >= 3) {
          return build('transport', 'กำลังนำส่ง ${i.hospitalName ?? 'โรงพยาบาล'}', unit,
              etaTarget: 'hospital', fallbackProgress: 0.05);
        }
        if (i.statusStep == 2) {
          return build('arrived', 'รถพยาบาลถึงจุดเกิดเหตุแล้ว', unit, fallbackProgress: 1);
        }
        final near = i.ambulanceNearSceneAt != null;
        return build(near ? 'near' : 'enroute',
            near ? 'รถพยาบาลใกล้ถึงแล้ว' : 'รถพยาบาลกำลังมา', unit,
            etaTarget: 'scene', fallbackProgress: near ? 0.9 : 0.05);
    }
  }

  Future<void> _cleanupExcept(String? keepIncidentId) async {
    if (_isIOS) {
      try {
        await _channel.invokeMethod('endAllExcept', {'incidentId': keepIncidentId ?? ''});
      } on PlatformException catch (e) {
        debugPrint('Live Activity cleanup: ${e.code} ${e.message}');
      } on MissingPluginException {
        // ข้าม
      }
    } else if (_isAndroid) {
      await CriticalNotificationService().cancelTrackingNotifications(
          except: keepIncidentId == null
              ? null
              : trackingNotificationIdForIncident(keepIncidentId));
    }
  }

  Future<void> _apply(TrackingState state) async {
    if (_isIOS) {
      try {
        final result =
            await _channel.invokeMethod<Object?>('startOrUpdate', state.toChannelArgs());
        _retryNativeOnResume = false;
        if (result is String && result != 'dismissed') {
          _reportIosProblem(state.incidentId, switch (result) {
            'disabled' => 'ปิด Live Activities ไว้ — เปิดได้ที่ ตั้งค่า → RouteAlert → Live Activities',
            'ios_too_old' => 'ต้องใช้ iOS 16.2 ขึ้นไป',
            _ => result,
          });
        }
      } on PlatformException catch (e) {
        _retryNativeOnResume = true;
        debugPrint('Live Activity: ${e.code} ${e.message}');
        if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
          _reportIosProblem(state.incidentId, e.message ?? e.code);
        }
      } on MissingPluginException {
        _reportIosProblem(state.incidentId, 'ส่วนเชื่อมต่อฝั่ง iOS ไม่ได้ลงทะเบียน (bridge missing)');
      }
    } else if (_isAndroid) {
      await CriticalNotificationService().showTrackingNotification(
        id: trackingNotificationIdForIncident(state.incidentId),
        title: state.title,
        body: state.detailLine,
        progressPercent: (state.progress * 100).round(),
        payload: NotificationIntent(
          incidentId: state.incidentId,
          kind: 'tracking',
          audience: PushAudience.reporter,
        ).toPayload(),
      );
    }
  }

  // บอกผู้ใช้บนหน้าจอว่าทำไมหน้าล็อก/Dynamic Island ไม่ขึ้น — ครั้งเดียวต่อเคส
  final Set<String> _reportedProblems = {};
  void _reportIosProblem(String incidentId, String reason) {
    debugPrint('Live Activity problem: $reason');
    if (!_reportedProblems.add(incidentId)) return;
    final context = appNavigatorKey.currentContext;
    if (context == null || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('แสดงบนหน้าล็อก/Dynamic Island ไม่ได้: $reason'),
      duration: const Duration(seconds: 8),
    ));
  }

  Future<void> _endNative(String incidentId, TrackingState? finalState) async {
    if (_isIOS) {
      try {
        await _channel.invokeMethod('end', {
          'incidentId': incidentId,
          if (finalState != null) ...finalState.toChannelArgs(),
          // เคสจบ: ค้างสถานะสุดท้ายไว้บนหน้าล็อก 4 นาทีแล้วหายเอง
          'dismissAfterSeconds': finalState == null ? 0 : 240,
        });
      } on PlatformException catch (e) {
        debugPrint('Live Activity end: ${e.code} ${e.message}');
      } on MissingPluginException {
        // ข้าม
      }
    } else if (_isAndroid) {
      await CriticalNotificationService()
          .cancelNotification(trackingNotificationIdForIncident(incidentId));
    }
  }
}

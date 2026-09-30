import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'notification_intent.dart';

class HeadsUpAlertEvent {
  final String title;
  final String body;
  final bool isCritical;
  final DateTime timestamp;

  HeadsUpAlertEvent({
    required this.title,
    required this.body,
    required this.isCritical,
    required this.timestamp,
  });
}

class CriticalNotificationService {
  static final CriticalNotificationService _instance =
      CriticalNotificationService._internal();
  factory CriticalNotificationService() => _instance;
  CriticalNotificationService._internal();

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();
  bool _isInitialized = false;

  final StreamController<HeadsUpAlertEvent> _headsUpStreamController =
      StreamController<HeadsUpAlertEvent>.broadcast();

  Stream<HeadsUpAlertEvent> get headsUpStream =>
      _headsUpStreamController.stream;

  static const String _channelId = 'route_alert_emergency_heads_up_channel';
  static const String _channelName = '🚨 RouteAlert Emergency Siren Alert';
  static const String _channelDesc =
      'Heads-up banner alerts for approaching emergency vehicles';
  static const String _updatesChannelId = 'route_alert_case_updates';
  static const String _updatesChannelName = 'อัปเดตสถานะเคส';
  static const String _trackingChannelId = 'route_alert_live_tracking';
  static const String _trackingChannelName = 'ติดตามรถพยาบาลแบบสด';

  // ชุดปุ่มบนแจ้งเตือนเคสใหม่ — iOS ต้องลงทะเบียนเป็น category ไว้ล่วงหน้า
  static const String categoryNewAmbulance = 'RA_NEW_AMBULANCE';
  static const String categoryNewAgency = 'RA_NEW_AGENCY';
  static const Map<String, List<(String, String)>> incidentButtons = {
    categoryNewAmbulance: [(PushAction.view, 'ดูเคส'), (PushAction.accept, 'รับเคส')],
    categoryNewAgency: [(PushAction.view, 'ดูเคส'), (PushAction.dispatch, 'ส่งรถพยาบาล')],
  };

  Future<void>? _initFuture;
  bool _permissionsRequested = false;
  bool _launchDetailsConsumed = false;

  /// [requestPermissions] = false ใน isolate เบื้องหลังของ FCM (ไม่มีหน้าจอให้ขอสิทธิ์)
  Future<void> initialize({bool requestPermissions = true}) async {
    await (_initFuture ??= _initPlugin());
    if (requestPermissions && _isInitialized && !_permissionsRequested) {
      _permissionsRequested = true;
      await _requestPermissions();
    }
  }

  Future<void> _initPlugin() async {
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    final darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
      notificationCategories: [
        for (final entry in incidentButtons.entries)
          DarwinNotificationCategory(
            entry.key,
            actions: [
              for (final (id, label) in entry.value)
                DarwinNotificationAction.plain(
                  id,
                  label,
                  options: {DarwinNotificationActionOption.foreground},
                ),
            ],
          ),
      ],
    );

    try {
      await _notificationsPlugin.initialize(
        InitializationSettings(
          android: androidSettings,
          iOS: darwinSettings,
          macOS: darwinSettings,
        ),
        onDidReceiveNotificationResponse: _onNotificationResponse,
      );

      final androidPlugin =
          _notificationsPlugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();

      // Create Android High-Priority Heads-Up Channel
      await androidPlugin?.createNotificationChannel(AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDesc,
        importance: Importance.max,
        enableVibration: true,
        playSound: true,
        showBadge: true,
        vibrationPattern: Int64List.fromList([0, 600, 200, 600, 200, 600]),
        audioAttributesUsage: AudioAttributesUsage.alarm,
      ));
      await androidPlugin?.createNotificationChannel(
          const AndroidNotificationChannel(
        _updatesChannelId,
        _updatesChannelName,
        description: 'รถพยาบาลรับเคส ใกล้ถึง และเคสเสร็จสิ้น',
        importance: Importance.high,
      ));
      // ช่องเงียบสำหรับแจ้งเตือนค้างที่อัปเดตระยะ/ETA ตลอด (Android 8+ ใช้ค่าเสียงของช่อง)
      await androidPlugin?.createNotificationChannel(
          const AndroidNotificationChannel(
        _trackingChannelId,
        _trackingChannelName,
        description: 'ระยะและเวลาที่รถพยาบาลจะถึง ระหว่างรอรถ',
        importance: Importance.low,
        playSound: false,
        enableVibration: false,
        showBadge: false,
      ));

      _isInitialized = true;
    } catch (e) {
      _initFuture = null; // ให้ลองใหม่ได้ในการเรียกครั้งถัดไป
      debugPrint('CriticalNotificationService init error: $e');
    }
  }

  Future<void> _requestPermissions() async {
    try {
      await _notificationsPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      await _notificationsPlugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(
              alert: true, badge: true, sound: true, critical: true);
    } catch (e) {
      debugPrint('CriticalNotificationService permission error: $e');
    }
  }

  // แจ้งเตือนเรดาร์ (911/1669) ไม่มี payload จึงถูกข้ามเอง
  void _onNotificationResponse(NotificationResponse response) {
    NotificationIntentHub.dispatch(NotificationIntent.fromPayload(
      response.payload,
      actionId: response.actionId,
    ));
  }

  /// แอปถูกเปิดขึ้นมาจากการกดแจ้งเตือนตอนปิดสนิท — ส่งต่อครั้งเดียวต่อการเปิดแอป
  Future<void> consumeLaunchDetails() async {
    if (_launchDetailsConsumed) return;
    _launchDetailsConsumed = true;
    try {
      final details =
          await _notificationsPlugin.getNotificationAppLaunchDetails();
      final response = details?.notificationResponse;
      if (details?.didNotificationLaunchApp == true && response != null) {
        _onNotificationResponse(response);
      }
    } catch (e) {
      debugPrint('consumeLaunchDetails error: $e');
    }
  }

  /// แจ้งเตือนเคส 1 เคส = 1 แจ้งเตือน (id เดิมทับอันเก่า) — [emergency] ใช้ช่อง
  /// เสียงไซเรน/เด้งเต็ม ส่วนอัปเดตสถานะใช้ช่องปกติ
  Future<void> showIncidentNotification({
    required int id,
    required String title,
    required String body,
    required bool emergency,
    required String payload,
    required String threadId,
    required Color color,
    String? category,
  }) async {
    if (!_isInitialized) await initialize(requestPermissions: false);
    final buttons = incidentButtons[category] ?? const [];

    final androidDetails = AndroidNotificationDetails(
      emergency ? _channelId : _updatesChannelId,
      emergency ? _channelName : _updatesChannelName,
      importance: emergency ? Importance.max : Importance.high,
      priority: emergency ? Priority.max : Priority.high,
      category: emergency
          ? AndroidNotificationCategory.alarm
          : AndroidNotificationCategory.status,
      visibility: NotificationVisibility.public,
      color: color,
      ticker: title,
      styleInformation: BigTextStyleInformation(body, contentTitle: title),
      actions: [
        for (final (actionId, label) in buttons)
          AndroidNotificationAction(actionId, label,
              showsUserInterface: true, cancelNotification: true),
      ],
    );
    final darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBanner: true,
      presentList: true,
      presentSound: true,
      threadIdentifier: threadId,
      categoryIdentifier: buttons.isEmpty ? null : category,
      interruptionLevel:
          emergency ? InterruptionLevel.timeSensitive : InterruptionLevel.active,
    );

    try {
      await _notificationsPlugin.show(
        id,
        title,
        body,
        NotificationDetails(
            android: androidDetails, iOS: darwinDetails, macOS: darwinDetails),
        payload: payload,
      );
    } catch (e) {
      debugPrint('showIncidentNotification error: $e');
    }
  }

  /// แจ้งเตือนค้างติดตามรถพยาบาลของผู้แจ้งเหตุ (Android — เทียบเท่า Live Activity บน iOS)
  /// ไม่มีเสียง อัปเดตทับที่เดิมเรื่อยๆ ปัดทิ้งไม่ได้จนเคสจบ
  Future<void> showTrackingNotification({
    required int id,
    required String title,
    required String body,
    required int progressPercent,
    required String payload,
  }) async {
    if (!_isInitialized) await initialize(requestPermissions: false);
    try {
      await _notificationsPlugin.show(
        id,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _trackingChannelId,
            _trackingChannelName,
            importance: Importance.low,
            priority: Priority.low,
            ongoing: true,
            autoCancel: false,
            onlyAlertOnce: true,
            playSound: false,
            enableVibration: false,
            showProgress: true,
            maxProgress: 100,
            progress: progressPercent.clamp(0, 100),
            category: AndroidNotificationCategory.progress,
            visibility: NotificationVisibility.public,
            color: const Color(0xFF00A896),
          ),
        ),
        payload: payload,
      );
    } catch (e) {
      debugPrint('showTrackingNotification error: $e');
    }
  }

  /// ลบแจ้งเตือนติดตามรถที่ค้างอยู่ (เช่นของเคสก่อนหน้า หรือแอปถูกปิดไประหว่างเคส)
  Future<void> cancelTrackingNotifications({int? except}) async {
    if (!_isInitialized) await initialize(requestPermissions: false);
    try {
      final android = _notificationsPlugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      final active = await android?.getActiveNotifications() ?? const [];
      for (final n in active) {
        final id = n.id;
        if (id != null && id >= 0x20000000 && id < 0x40000000 && id != except) {
          await _notificationsPlugin.cancel(id);
        }
      }
    } catch (e) {
      debugPrint('cancelTrackingNotifications error: $e');
    }
  }

  Future<void> cancelNotification(int id) async {
    if (!_isInitialized) await initialize(requestPermissions: false);
    try {
      await _notificationsPlugin.cancel(id);
    } catch (_) {}
  }

  /// Displays real-time OS Heads-Up floating drop-down notification banner
  Future<void> showRadarAlert({
    required String title,
    required String body,
    bool isCritical = false,
  }) async {
    // ตอนเปิดแอป main.dart เตรียมไว้แบบยังไม่ขอสิทธิ์ — ต้องขอตรงนี้ ไม่งั้นไม่เคยได้สิทธิ์
    await initialize();

    // Broadcast to in-app drop-down banner listener as well
    if (!_headsUpStreamController.isClosed) {
      _headsUpStreamController.add(
        HeadsUpAlertEvent(
          title: title,
          body: body,
          isCritical: isCritical,
          timestamp: DateTime.now(),
        ),
      );
    }

    final androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.max,
      priority: Priority.max,
      ticker: '🚨 RouteAlert Emergency Alert',
      fullScreenIntent: isCritical,
      category: AndroidNotificationCategory.alarm,
      visibility: NotificationVisibility.public,
      enableVibration: true,
      playSound: true,
      vibrationPattern: isCritical
          ? Int64List.fromList([0, 800, 200, 800, 200, 800])
          : Int64List.fromList([0, 400, 200, 400]),
      styleInformation: BigTextStyleInformation(
        body,
        contentTitle: title,
        summaryText: 'RouteAlert AI Siren Detection',
      ),
    );

    const darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBanner: true,
      presentSound: true,
      presentBadge: true,
      interruptionLevel: InterruptionLevel.critical,
    );

    final notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
      macOS: darwinDetails,
    );

    try {
      await _notificationsPlugin.show(
        isCritical ? 911 : 1669,
        title,
        body,
        notificationDetails,
      );
    } catch (e) {
      debugPrint('Error showing notification: $e');
    }
  }

  /// Updates Ongoing Real-Time Live Notification with live distance countdown
  Future<void> updateLiveRadarNotification({
    required int distanceMeters,
    required String statusText,
    required bool isCritical,
    required double yieldProbability,
  }) async {
    await initialize();

    final title = isCritical
        ? '🚨 แจ้งเตือนมีรถพยาบาล: $distanceMeters M'
        : '📡 เรดาร์รถพยาบาล: $distanceMeters M';
    final body = isCritical
        ? 'ระยะห่าง $distanceMeters M • ชะลอและเบี่ยงซ้ายทันที (AI ${(yieldProbability * 100).toInt()}%)'
        : 'ระยะห่าง $distanceMeters M • $statusText (AI ${(yieldProbability * 100).toInt()}%)';

    if (!_headsUpStreamController.isClosed) {
      _headsUpStreamController.add(
        HeadsUpAlertEvent(
          title: title,
          body: body,
          isCritical: isCritical,
          timestamp: DateTime.now(),
        ),
      );
    }

    final androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.max,
      priority: Priority.max,
      ticker: '🚨 รถพยาบาล: $distanceMeters M',
      onlyAlertOnce: true,
      ongoing: true,
      category: AndroidNotificationCategory.alarm,
      visibility: NotificationVisibility.public,
      styleInformation: BigTextStyleInformation(
        '🚑 รถพยาบาลฉุกเฉินกำลังตามหลังมา\n'
        '📏 ระยะห่าง Real-Time: $distanceMeters เมตร\n'
        '🧠 AI Yield Risk Score: ${(yieldProbability * 100).toInt()}%\n'
        '⚡ คำแนะนำ: ${isCritical ? "ชะลอความเร็วและเบี่ยงซ้ายเพื่อเปิดทางทันที" : "ขับขี่ด้วยความระมัดระวัง"}',
        contentTitle: title,
        summaryText: 'RouteAlert Live Activity',
      ),
    );

    const darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBanner: true,
      presentSound: false,
      interruptionLevel: InterruptionLevel.timeSensitive,
    );

    final notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
    );

    try {
      await _notificationsPlugin.show(
        911,
        title,
        body,
        notificationDetails,
      );
    } catch (e) {
      debugPrint('updateLiveRadarNotification error: $e');
    }
  }

  Future<void> cancelAll() async {
    try {
      await _notificationsPlugin.cancelAll();
    } catch (_) {}
  }

  void dispose() {
    _headsUpStreamController.close();
  }
}

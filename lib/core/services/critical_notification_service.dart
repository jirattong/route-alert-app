import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

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

  Future<void> initialize() async {
    if (_isInitialized) return;

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
      requestCriticalPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
    );

    try {
      await _notificationsPlugin.initialize(initSettings);

      // Request permissions explicitly for Android 13+ (API 33+)
      final androidPlugin =
          _notificationsPlugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.requestNotificationsPermission();

      // Create Android High-Priority Heads-Up Channel
      final androidChannel = AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDesc,
        importance: Importance.max,
        enableVibration: true,
        playSound: true,
        showBadge: true,
        vibrationPattern: Int64List.fromList([0, 600, 200, 600, 200, 600]),
        audioAttributesUsage: AudioAttributesUsage.alarm,
      );

      await androidPlugin?.createNotificationChannel(androidChannel);

      _isInitialized = true;
    } catch (e) {
      debugPrint('CriticalNotificationService init error: $e');
    }
  }

  /// Displays real-time OS Heads-Up floating drop-down notification banner
  Future<void> showRadarAlert({
    required String title,
    required String body,
    bool isCritical = false,
  }) async {
    if (!_isInitialized) await initialize();

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
    if (!_isInitialized) await initialize();

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

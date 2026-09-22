import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:latlong2/latlong.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

class EmergencyVehicleData {
  final String id;
  final String callSign;
  final double latitude;
  final double longitude;
  final double speed;
  final double heading; // ทิศทางการเคลื่อนที่จริง (0-360 องศา, คำนวณจาก GPS)
  final String plateNumber;
  final String emergencyType;
  final bool sirenActive;
  final DateTime timestamp;
  final List<LatLng>? routePoints;
  final String? turnIntent;
  final String? destinationName;

  EmergencyVehicleData({
    required this.id,
    required this.callSign,
    required this.latitude,
    required this.longitude,
    required this.speed,
    this.heading = 0.0,
    this.plateNumber = '',
    required this.emergencyType,
    required this.sirenActive,
    required this.timestamp,
    this.routePoints,
    this.turnIntent,
    this.destinationName,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'callSign': callSign,
      'latitude': latitude,
      'longitude': longitude,
      'speed': speed,
      'heading': heading,
      'plateNumber': plateNumber,
      'emergencyType': emergencyType,
      'sirenActive': sirenActive,
      'timestamp': timestamp.toIso8601String(),
      if (routePoints != null)
        'routePoints': routePoints!
            .map((p) => [p.latitude, p.longitude])
            .toList(),
      if (turnIntent != null) 'turnIntent': turnIntent,
      if (destinationName != null) 'destinationName': destinationName,
    };
  }

  factory EmergencyVehicleData.fromMap(Map<String, dynamic> map) {
    List<LatLng>? parsedRoute;
    if (map['routePoints'] != null && map['routePoints'] is List) {
      parsedRoute = (map['routePoints'] as List).map((pt) {
        if (pt is List && pt.length >= 2) {
          return LatLng(
            (pt[0] as num).toDouble(),
            (pt[1] as num).toDouble(),
          );
        }
        return const LatLng(13.7563, 100.5018);
      }).toList();
    }

    return EmergencyVehicleData(
      id: map['id'] ?? 'AMB_01',
      callSign: map['callSign'] ?? 'Ambulance 1669',
      latitude: (map['latitude'] as num?)?.toDouble() ?? 13.7563,
      longitude: (map['longitude'] as num?)?.toDouble() ?? 100.5018,
      speed: (map['speed'] as num?)?.toDouble() ?? 60.0,
      heading: (map['heading'] as num?)?.toDouble() ?? 0.0,
      plateNumber: map['plateNumber'] ?? '',
      emergencyType: map['emergencyType'] ?? 'ผู้ป่วยวิกฤตฉุกเฉิน (Red Code)',
      sirenActive: map['sirenActive'] ?? true,
      timestamp: map['timestamp'] != null
          ? DateTime.parse(map['timestamp'])
          : DateTime.now(),
      routePoints: parsedRoute,
      turnIntent: map['turnIntent'],
      destinationName: map['destinationName'],
    );
  }

  String toJson() => json.encode(toMap());
  factory EmergencyVehicleData.fromJson(String str) =>
      EmergencyVehicleData.fromMap(json.decode(str));
}

class EmergencyMqttService {
  static final EmergencyMqttService _instance = EmergencyMqttService._internal();
  factory EmergencyMqttService() => _instance;
  EmergencyMqttService._internal();

  MqttServerClient? _client;
  bool _isConnected = false;
  // เก็บสาเหตุจริงที่เชื่อมต่อไม่ติด (exception/สถานะจริงจาก client) ไว้โชว์บน UI
  // debug bar เดิม initialize() กลืน exception ทิ้งเงียบๆ ไม่มีทางรู้เลยว่าติดตรงไหน
  String? _lastError;
  String? get lastError => _lastError;

  // ตัวนับ/สาเหตุ error ตอนรับข้อความจริง — เดิม catch(_) กลืน exception ตอน parse
  // ทิ้งเงียบๆ เหมือนกับจุด connect() ก่อนหน้านี้ ถ้าข้อความมาถึงจริงแต่ parse ไม่ผ่าน
  // จะไม่มีทางรู้เลยว่าเกิดอะไรขึ้น ต้องเปิดให้เห็นเพื่อวินิจฉัยว่าปัญหาอยู่ที่ชั้นไหน
  int _messagesReceivedCount = 0;
  int get messagesReceivedCount => _messagesReceivedCount;
  String? _lastParseError;
  String? get lastParseError => _lastParseError;
  static const String _broker = 'broker.emqx.io';
  static const int _port = 1883;
  // ใส่ namespace เฉพาะโปรเจกต์ (Firebase project id) กัน topic ชนกับคนอื่นที่
  // clone repo นี้ไปทดสอบบน broker.emqx.io สาธารณะตัวเดียวกัน
  static const String topicAmbulanceBroadcast =
      'routealert-ccf91/emergency/ambulance';

  final StreamController<EmergencyVehicleData> _emergencyStreamController =
      StreamController<EmergencyVehicleData>.broadcast();

  final StreamController<List<EmergencyVehicleData>> _fleetStreamController =
      StreamController<List<EmergencyVehicleData>>.broadcast();

  final Map<String, EmergencyVehicleData> _activeFleet = {};

  // เดิม _purgeStaleVehicles() เทียบเวลาปัจจุบันกับ EmergencyVehicleData.timestamp
  // ซึ่งเป็นเวลาจากนาฬิกาของ "เครื่องผู้ส่ง" (ambulance) เอง (toIso8601String() ไม่
  // ได้ normalize เป็น UTC จึงถูก parse กลับมาเป็นเวลาท้องถิ่นตามนาฬิกาเครื่องผู้ส่ง)
  // ถ้านาฬิกาสองเครื่องไม่ตรงกัน (ตั้งเขตเวลาผิด/นาฬิกาเพี้ยน) การหมดอายุจะพังทันที
  // ทั้งสองทาง (purge เร็วเกินไปทั้งที่รถยังส่งสัญญาณปกติ หรือไม่ purge เลยทั้งที่รถ
  // ออฟไลน์ไปแล้วจริง) จึงเปลี่ยนมาใช้เวลาที่ "เครื่องนี้" ได้รับข้อมูลจริงแทน (นาฬิกา
  // ท้องถิ่นของตัวเอง เชื่อถือได้เสมอ ไม่ขึ้นกับนาฬิกาเครื่องอื่น)
  final Map<String, DateTime> _lastReceivedAt = {};

  // เดิมไม่มีกลไกหมดอายุข้อมูลเลย — ปิดแอปฝั่ง Ambulance โดยไม่มีการส่งสัญญาณ
  // "ออฟไลน์" ใดๆ (MQTT Last Will ก็ไม่เคยตั้งไว้จริงตั้งแต่แรก) พิกัดล่าสุดที่
  // เคยส่งมาจะค้างอยู่ใน fleet ตลอดไปไม่มีวันหายจากแผนที่ฝั่ง Driver เลย เพิ่ม
  // ตัวจับเวลาตรวจสอบเป็นระยะ ถ้าไม่มีอัปเดตใหม่เกินเวลาที่กำหนด (นานกว่า
  // heartbeat broadcast ปกติทุก 3 วินาทีหลายเท่า) ถือว่าออฟไลน์แล้ว ลบออกจาก
  // fleet และแจ้งผ่าน emergencyStream เหมือนได้รับ sirenActive:false จริง
  // (ใช้ path เดิมที่ driver_home_screen.dart มีอยู่แล้ว ไม่ต้องแก้ไฟล์นั้นเลย)
  static const Duration _staleTimeout = Duration(seconds: 12);
  Timer? _staleCheckTimer;

  Stream<EmergencyVehicleData> get emergencyStream =>
      _emergencyStreamController.stream;

  Stream<List<EmergencyVehicleData>> get activeFleetStream =>
      _fleetStreamController.stream;

  List<EmergencyVehicleData> get activeFleet => _activeFleet.values.toList();

  // เปิดให้ UI เช็คสถานะการเชื่อมต่อ MQTT จริงได้ (ใช้ทำแถบ debug บนหน้าจอ เวลา
  // ทดสอบ 2 เครื่องแล้วไม่เจอกัน จะได้รู้ทันทีว่าติดที่ขั้นตอนไหน แทนที่จะเดา)
  bool get isConnected => _isConnected;

  Future<bool> initialize() async {
    if (_isConnected) return true;

    final clientId = 'RouteAlert_${DateTime.now().millisecondsSinceEpoch}';
    _client = MqttServerClient.withPort(_broker, clientId, _port);
    _client!.logging(on: false);
    _client!.keepAlivePeriod = 20;
    _client!.autoReconnect = true;
    _client!.connectTimeoutPeriod = 8000; // 8 วินาที กันค้างเงียบๆ นานเกินไป

    // เดิมมี .withWillQos(MqttQos.atLeastOnce) ต่อท้ายโดยไม่เคยตั้ง Will
    // topic/message เลย (ไม่มี .withWillTopic()/.withWillMessage() ที่ไหนในไฟล์
    // นี้) ทำให้แพ็กเก็ต CONNECT ที่ส่งไปผิดสเปก MQTT: Will QoS ถูกตั้งค่าทั้งที่
    // Will Flag เป็น 0 (ดูซอร์สแพ็กเกจ mqtt_client: withWillQos() ตั้งแค่บิต
    // willQos ไม่เคยเรียก will() ให้ willFlag=true) โบรกเกอร์ที่ตรวจสอบแพ็กเก็ต
    // เข้มงวด (เช่น broker.emqx.io) จะปิดการเชื่อมต่อเงียบๆ โดยไม่ส่ง CONNACK
    // กลับมาเลย ตรงกับอาการ "Missing Connection Acknowledgement" ที่เจอจริง —
    // แก้โดยตัดออก เพราะไม่มีการใช้ Will message จริงในระบบนี้อยู่แล้ว
    final connMessage = MqttConnectMessage()
        .withClientIdentifier(clientId)
        .startClean();
    _client!.connectionMessage = connMessage;

    try {
      await _client!.connect();
      _isConnected = _client!.connectionStatus?.state == MqttConnectionState.connected;

      if (_isConnected) {
        _lastError = null;
        _subscribeToEmergency();
        _staleCheckTimer ??= Timer.periodic(
            const Duration(seconds: 5), (_) => _purgeStaleVehicles());
      } else {
        _lastError =
            'ต่อไม่สำเร็จ: สถานะ=${_client!.connectionStatus?.state}, '
            'code=${_client!.connectionStatus?.returnCode}';
        debugPrint('[EmergencyMqttService] $_lastError');
      }
      return _isConnected;
    } catch (e) {
      _isConnected = false;
      _lastError = 'Exception: $e';
      debugPrint('[EmergencyMqttService] connect() threw: $e');
      return false;
    }
  }

  // ลบรถพยาบาลที่ไม่มีอัปเดตใหม่มานานเกินไปออกจาก fleet (ถือว่าออฟไลน์แล้ว —
  // ปิดแอป/ปิดเครื่อง/สัญญาณหลุด) แล้วยิง event ปลอม sirenActive:false ออกไป
  // ผ่าน emergencyStream เพื่อให้โค้ดฝั่ง Driver ที่มีอยู่แล้ว (ซึ่งรองรับกรณี
  // sirenActive:false อยู่แล้วปกติ) เคลียร์หมุด/สถานะที่ค้างอยู่ให้เอง
  void _purgeStaleVehicles() {
    final now = DateTime.now();
    final staleEntries = _activeFleet.values
        .where((v) {
          final lastSeen = _lastReceivedAt[v.id];
          // ไม่เคยมีบันทึกเวลารับจริง (ไม่ควรเกิดขึ้นตาม flow ปกติ) ถือว่า stale ไปเลย
          // เพื่อความปลอดภัย ดีกว่าปล่อยให้ค้างอยู่ใน fleet ตลอดไปแบบไม่มีวันหมดอายุ
          if (lastSeen == null) return true;
          return now.difference(lastSeen) > _staleTimeout;
        })
        .toList();
    if (staleEntries.isEmpty) return;

    for (final stale in staleEntries) {
      _activeFleet.remove(stale.id);
      _lastReceivedAt.remove(stale.id);
      debugPrint('[EmergencyMqttService] vehicle ${stale.id} timed out, '
          'marking offline (no update for > ${_staleTimeout.inSeconds}s)');
      _emergencyStreamController.add(
        EmergencyVehicleData(
          id: stale.id,
          callSign: stale.callSign,
          latitude: stale.latitude,
          longitude: stale.longitude,
          speed: 0.0,
          heading: stale.heading,
          plateNumber: stale.plateNumber,
          emergencyType: stale.emergencyType,
          sirenActive: false,
          timestamp: now,
        ),
      );
    }
    _fleetStreamController.add(_activeFleet.values.toList());
  }

  void _subscribeToEmergency() {
    debugPrint('[EmergencyMqttService] subscribing to $topicAmbulanceBroadcast');
    _client?.subscribe(topicAmbulanceBroadcast, MqttQos.atLeastOnce);
    _client?.updates?.listen((List<MqttReceivedMessage<MqttMessage>> messages) {
      _messagesReceivedCount++;
      final recMess = messages[0].payload as MqttPublishMessage;
      // ต้องถอดรหัสด้วย UTF-8 คู่กับฝั่งส่งที่เข้ารหัสด้วย addUTF8String() ข้างบน
      // (bytesToStringAsString() ของแพ็กเกจไม่ใช่ UTF-8 จริง ใช้ไม่ได้กับข้อความไทย)
      final payload = utf8.decode(recMess.payload.message.toList());
      debugPrint('[EmergencyMqttService] received #$_messagesReceivedCount: '
          '${payload.length > 120 ? payload.substring(0, 120) : payload}');

      try {
        final data = EmergencyVehicleData.fromJson(payload);
        _lastParseError = null;
        if (data.sirenActive) {
          _activeFleet[data.id] = data;
          // บันทึกเวลาที่ "เครื่องนี้" ได้รับข้อมูล (นาฬิกาท้องถิ่น) แทนการพึ่งพา
          // data.timestamp ที่มาจากนาฬิกาเครื่องผู้ส่ง ใช้เทียบ staleness แทน
          _lastReceivedAt[data.id] = DateTime.now();
        } else {
          _activeFleet.remove(data.id);
          _lastReceivedAt.remove(data.id);
        }
        _emergencyStreamController.add(data);
        _fleetStreamController.add(_activeFleet.values.toList());
      } catch (e) {
        _lastParseError = 'parse error: $e';
        debugPrint('[EmergencyMqttService] $_lastParseError | payload=$payload');
      }
    });
  }

  /// Broadcasts ambulance live location to other drivers on the road
  void broadcastAmbulanceLocation(EmergencyVehicleData data) {
    if (data.sirenActive) {
      _activeFleet[data.id] = data;
      // local echo ก็ต้องบันทึกเวลารับท้องถิ่นเหมือนกัน ไม่งั้น _lastReceivedAt
      // จะไม่มี entry ให้รถของตัวเอง (ฝั่งที่ broadcast เอง) แล้วโดน purge ผิดๆ
      _lastReceivedAt[data.id] = DateTime.now();
    } else {
      _activeFleet.remove(data.id);
      _lastReceivedAt.remove(data.id);
    }
    _emergencyStreamController.add(data);
    _fleetStreamController.add(_activeFleet.values.toList());

    if (!_isConnected || _client == null) {
      return;
    }

    try {
      // เดิมใช้ builder.addString() ซึ่งเรียก addUTF16String() ภายใน — เข้ารหัส
      // ตัวอักษรไทย (code unit > 255 ทุกตัว) เป็น 2 ไบต์แบบ raw 16-bit half-word
      // ไม่ใช่ UTF-8 มาตรฐาน แล้วฝั่งรับ (bytesToStringAsString) ก็ถอดรหัสแบบ
      // byte-ต่อ-1-ตัวอักษรธรรมดา (ไม่ใช่ UTF-8 เหมือนกัน) ทำให้ข้อความที่มีภาษาไทย
      // (เช่น callSign "หน่วยทดสอบ 1") เพี้ยนเป็นตัวอักษรควบคุมมั่วๆ จน JSON.decode()
      // parse ไม่ผ่านเลย ("Control character in string") แก้โดยเข้ารหัส UTF-8 จริง
      // ที่ทั้งสองฝั่งต้องตรงกัน (ฝั่งรับแก้คู่กันใน _subscribeToEmergency ด้านบน)
      final builder = MqttClientPayloadBuilder();
      builder.addUTF8String(data.toJson());
      _client!.publishMessage(
        topicAmbulanceBroadcast,
        MqttQos.atLeastOnce,
        builder.payload!,
      );
    } catch (_) {}
  }

  /// Seed initial simulated active ambulances for testing when offline
  void seedSimulatedFleet(LatLng userPos) {
    if (_activeFleet.isNotEmpty) return;

    final samples = [
      EmergencyVehicleData(
        id: 'AMB-1669-01',
        callSign: 'กู้ชีพนครพิงค์ 01',
        latitude: userPos.latitude + 0.012,
        longitude: userPos.longitude + 0.015,
        speed: 65.0,
        emergencyType: 'ผู้ป่วยวิกฤตฉุกเฉิน (Red Code)',
        sirenActive: true,
        timestamp: DateTime.now(),
      ),
      EmergencyVehicleData(
        id: 'AMB-1669-02',
        callSign: 'กู้ชีพมหาราช 02',
        latitude: userPos.latitude - 0.020,
        longitude: userPos.longitude + 0.018,
        speed: 55.0,
        emergencyType: 'อุบัติเหตุจราจร (Yellow Code)',
        sirenActive: true,
        timestamp: DateTime.now(),
      ),
      EmergencyVehicleData(
        id: 'AMB-1669-03',
        callSign: 'ศูนย์กู้ชีพพายัพ 03',
        latitude: userPos.latitude + 0.028,
        longitude: userPos.longitude - 0.022,
        speed: 48.0,
        emergencyType: 'ผู้ป่วยฉุกเฉินนำส่ง รพ.',
        sirenActive: true,
        timestamp: DateTime.now(),
      ),
    ];

    for (var s in samples) {
      _activeFleet[s.id] = s;
    }
    _fleetStreamController.add(_activeFleet.values.toList());
  }

  /// Calculates distance in meters between driver and ambulance (Haversine formula)
  static double calculateDistanceInMeters(
      LatLng driverPos, LatLng ambulancePos) {
    const double r = 6371000; // Earth radius in meters
    final double lat1Rad = driverPos.latitude * math.pi / 180;
    final double lat2Rad = ambulancePos.latitude * math.pi / 180;
    final double dLat =
        (ambulancePos.latitude - driverPos.latitude) * math.pi / 180;
    final double dLon =
        (ambulancePos.longitude - driverPos.longitude) * math.pi / 180;

    final double a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1Rad) *
            math.cos(lat2Rad) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));

    return r * c;
  }

  void dispose() {
    _staleCheckTimer?.cancel();
    _client?.disconnect();
    _emergencyStreamController.close();
    _fleetStreamController.close();
  }
}

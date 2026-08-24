import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:latlong2/latlong.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

class EmergencyVehicleData {
  final String id;
  final String callSign;
  final double latitude;
  final double longitude;
  final double speed;
  final String emergencyType;
  final bool sirenActive;
  final DateTime timestamp;

  EmergencyVehicleData({
    required this.id,
    required this.callSign,
    required this.latitude,
    required this.longitude,
    required this.speed,
    required this.emergencyType,
    required this.sirenActive,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'callSign': callSign,
      'latitude': latitude,
      'longitude': longitude,
      'speed': speed,
      'emergencyType': emergencyType,
      'sirenActive': sirenActive,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  factory EmergencyVehicleData.fromMap(Map<String, dynamic> map) {
    return EmergencyVehicleData(
      id: map['id'] ?? 'AMB_01',
      callSign: map['callSign'] ?? 'Ambulance 1669',
      latitude: (map['latitude'] as num?)?.toDouble() ?? 13.7563,
      longitude: (map['longitude'] as num?)?.toDouble() ?? 100.5018,
      speed: (map['speed'] as num?)?.toDouble() ?? 60.0,
      emergencyType: map['emergencyType'] ?? 'ผู้ป่วยวิกฤตฉุกเฉิน (Red Code)',
      sirenActive: map['sirenActive'] ?? true,
      timestamp: map['timestamp'] != null
          ? DateTime.parse(map['timestamp'])
          : DateTime.now(),
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
  static const String _broker = 'broker.emqx.io';
  static const int _port = 1883;
  static const String topicAmbulanceBroadcast = 'routealert/emergency/ambulance';

  final StreamController<EmergencyVehicleData> _emergencyStreamController =
      StreamController<EmergencyVehicleData>.broadcast();

  Stream<EmergencyVehicleData> get emergencyStream =>
      _emergencyStreamController.stream;

  Future<bool> initialize() async {
    if (_isConnected) return true;

    final clientId = 'RouteAlert_${DateTime.now().millisecondsSinceEpoch}';
    _client = MqttServerClient.withPort(_broker, clientId, _port);
    _client!.logging(on: false);
    _client!.keepAlivePeriod = 20;
    _client!.autoReconnect = true;

    final connMessage = MqttConnectMessage()
        .withClientIdentifier(clientId)
        .startClean()
        .withWillQos(MqttQos.atLeastOnce);
    _client!.connectionMessage = connMessage;

    try {
      await _client!.connect();
      _isConnected = _client!.connectionStatus?.state == MqttConnectionState.connected;

      if (_isConnected) {
        _subscribeToEmergency();
      }
      return _isConnected;
    } catch (e) {
      _isConnected = false;
      return false;
    }
  }

  void _subscribeToEmergency() {
    _client?.subscribe(topicAmbulanceBroadcast, MqttQos.atLeastOnce);
    _client?.updates?.listen((List<MqttReceivedMessage<MqttMessage>> messages) {
      final recMess = messages[0].payload as MqttPublishMessage;
      final payload =
          MqttPublishPayload.bytesToStringAsString(recMess.payload.message);

      try {
        final data = EmergencyVehicleData.fromJson(payload);
        _emergencyStreamController.add(data);
      } catch (_) {}
    });
  }

  /// Broadcasts ambulance live location to other drivers on the road
  void broadcastAmbulanceLocation(EmergencyVehicleData data) {
    if (!_isConnected || _client == null) {
      // Local broadcast fallback
      _emergencyStreamController.add(data);
      return;
    }

    final builder = MqttClientPayloadBuilder();
    builder.addString(data.toJson());
    _client!.publishMessage(
      topicAmbulanceBroadcast,
      MqttQos.atLeastOnce,
      builder.payload!,
    );
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
    _client?.disconnect();
    _emergencyStreamController.close();
  }
}

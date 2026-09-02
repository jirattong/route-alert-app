import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HospitalProfile {
  final String hospitalId;
  final String hospitalName;
  final double latitude;
  final double longitude;
  final String address;
  final String erPhone;
  final DateTime lastUpdated;

  const HospitalProfile({
    required this.hospitalId,
    required this.hospitalName,
    required this.latitude,
    required this.longitude,
    required this.address,
    required this.erPhone,
    required this.lastUpdated,
  });

  LatLng get location => LatLng(latitude, longitude);

  Map<String, dynamic> toMap() {
    return {
      'hospitalId': hospitalId,
      'hospitalName': hospitalName,
      'latitude': latitude,
      'longitude': longitude,
      'address': address,
      'erPhone': erPhone,
      'lastUpdated': lastUpdated.toIso8601String(),
    };
  }

  factory HospitalProfile.fromMap(Map<String, dynamic> map) {
    return HospitalProfile(
      hospitalId: map['hospitalId'] ?? 'HOSP-01',
      hospitalName: map['hospitalName'] ?? 'ศูนย์การแพทย์ฉุกเฉิน มหาราชนคร',
      latitude: (map['latitude'] as num?)?.toDouble() ?? 19.0284,
      longitude: (map['longitude'] as num?)?.toDouble() ?? 99.8962,
      address: map['address'] ?? 'อำเภอเมือง จังหวัดเชียงใหม่',
      erPhone: map['erPhone'] ?? '053-936150 (สายด่วน ER)',
      lastUpdated: map['lastUpdated'] != null
          ? DateTime.tryParse(map['lastUpdated'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  String toJson() => json.encode(toMap());
  factory HospitalProfile.fromJson(String str) =>
      HospitalProfile.fromMap(json.decode(str));

  HospitalProfile copyWith({
    String? hospitalId,
    String? hospitalName,
    double? latitude,
    double? longitude,
    String? address,
    String? erPhone,
    DateTime? lastUpdated,
  }) {
    return HospitalProfile(
      hospitalId: hospitalId ?? this.hospitalId,
      hospitalName: hospitalName ?? this.hospitalName,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      address: address ?? this.address,
      erPhone: erPhone ?? this.erPhone,
      lastUpdated: lastUpdated ?? this.lastUpdated,
    );
  }
}

class HospitalWithDistance {
  final HospitalProfile profile;
  final double distanceKm;
  final int etaMinutes;

  const HospitalWithDistance({
    required this.profile,
    required this.distanceKm,
    required this.etaMinutes,
  });
}

/// Service to manage fixed hospital location pinning & multi-device synchronization
class HospitalLocationService {
  static final HospitalLocationService _instance =
      HospitalLocationService._internal();
  factory HospitalLocationService() => _instance;
  HospitalLocationService._internal();

  static const String _prefKey = 'hospital_pinned_profile_v1';
  static const String _collectionName = 'hospital_profiles';

  HospitalProfile _currentProfile = HospitalProfile(
    hospitalId: 'HOSP-01',
    hospitalName: 'ศูนย์การแพทย์ฉุกเฉิน โรงพยาบาลมหาราชนคร',
    latitude: 19.0284,
    longitude: 99.8962,
    address: 'ต.สุเทพ อ.เมือง จ.เชียงใหม่',
    erPhone: '053-936150 (ต่อ ER)',
    lastUpdated: DateTime.now(),
  );

  // Regional Hospital Directory
  final List<HospitalProfile> _registeredHospitals = [
    HospitalProfile(
      hospitalId: 'HOSP-01',
      hospitalName: 'โรงพยาบาลมหาราชนครเชียงใหม่ (สวนดอก)',
      latitude: 19.0284,
      longitude: 99.8962,
      address: '110 ถ.อินทวโรรส ต.ศรีภูมิ อ.เมือง จ.เชียงใหม่',
      erPhone: '053-936150',
      lastUpdated: DateTime.now(),
    ),
    HospitalProfile(
      hospitalId: 'HOSP-02',
      hospitalName: 'โรงพยาบาลนครพิงค์ (ศูนย์อุบัติเหตุภาคเหนือ)',
      latitude: 18.8475,
      longitude: 98.9660,
      address: '159 ม.10 ถ.โชตนา ต.ดอนแก้ว อ.แม่ริม จ.เชียงใหม่',
      erPhone: '053-999200',
      lastUpdated: DateTime.now(),
    ),
    HospitalProfile(
      hospitalId: 'HOSP-03',
      hospitalName: 'โรงพยาบาลสันทราย',
      latitude: 18.8920,
      longitude: 99.0430,
      address: 'ต.หนองหาร อ.สันทราย จ.เชียงใหม่',
      erPhone: '053-865399',
      lastUpdated: DateTime.now(),
    ),
    HospitalProfile(
      hospitalId: 'HOSP-04',
      hospitalName: 'โรงพยาบาลฝาง',
      latitude: 19.9160,
      longitude: 99.2130,
      address: 'ต.เวียง อ.ฝาง จ.เชียงใหม่',
      erPhone: '053-451151',
      lastUpdated: DateTime.now(),
    ),
  ];

  final StreamController<HospitalProfile> _profileStreamController =
      StreamController<HospitalProfile>.broadcast();

  Stream<HospitalProfile> get profileStream => _profileStreamController.stream;
  HospitalProfile get currentProfile => _currentProfile;
  LatLng get hospitalLocation => _currentProfile.location;
  List<HospitalProfile> get allHospitals => List.unmodifiable(_registeredHospitals);

  Future<void> initialize({String hospitalId = 'HOSP-01'}) async {
    await _loadFromLocal();
    _initFirestoreListener(hospitalId);
  }

  Future<void> _loadFromLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedJson = prefs.getString(_prefKey);
      if (savedJson != null && savedJson.isNotEmpty) {
        _currentProfile = HospitalProfile.fromJson(savedJson);
        _profileStreamController.add(_currentProfile);

        // Update in directory
        final idx = _registeredHospitals.indexWhere((h) => h.hospitalId == _currentProfile.hospitalId);
        if (idx != -1) {
          _registeredHospitals[idx] = _currentProfile;
        } else {
          _registeredHospitals.insert(0, _currentProfile);
        }
      }
    } catch (e) {
      debugPrint('Error loading local hospital profile: $e');
    }
  }

  void _initFirestoreListener(String hospitalId) {
    try {
      FirebaseFirestore.instance
          .collection(_collectionName)
          .doc(hospitalId)
          .snapshots()
          .listen((doc) {
        if (doc.exists && doc.data() != null) {
          try {
            final profile = HospitalProfile.fromMap(doc.data()!);
            _currentProfile = profile;
            _saveToLocal(profile);
            _profileStreamController.add(_currentProfile);
          } catch (e) {
            debugPrint('Error parsing hospital profile from Firestore: $e');
          }
        }
      }, onError: (err) {
        debugPrint('Firestore hospital profile error: $err');
      });
    } catch (_) {}
  }

  /// 🏥 AI Nearest Hospital Matcher: Calculates distance and returns nearest hospital to user's GPS
  HospitalWithDistance findNearestHospital(LatLng userLocation) {
    final list = getHospitalsSortedByDistance(userLocation);
    if (list.isNotEmpty) {
      return list.first;
    }
    return HospitalWithDistance(
      profile: _currentProfile,
      distanceKm: calculateDistanceKm(userLocation, _currentProfile.location),
      etaMinutes: 4,
    );
  }

  /// Returns all hospitals sorted from closest to farthest
  List<HospitalWithDistance> getHospitalsSortedByDistance(LatLng userLocation) {
    final List<HospitalWithDistance> result = [];

    for (var h in _registeredHospitals) {
      final distKm = calculateDistanceKm(userLocation, h.location);
      // Rough emergency vehicle speed ~60 km/h -> 1 km per minute + 1 min prep
      final etaMin = (distKm * 1.0).clamp(2.0, 60.0).round();

      result.add(HospitalWithDistance(
        profile: h,
        distanceKm: double.parse(distKm.toStringAsFixed(2)),
        etaMinutes: etaMin,
      ));
    }

    result.sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
    return result;
  }

  /// Haversine Distance in Kilometers
  static double calculateDistanceKm(LatLng p1, LatLng p2) {
    const Distance distance = Distance();
    return distance.as(LengthUnit.Kilometer, p1, p2);
  }

  /// Update and pin new hospital location (called from Pin Picker Modal)
  Future<bool> updatePinnedLocation({
    required LatLng newLocation,
    String? hospitalName,
    String? address,
    String? erPhone,
  }) async {
    try {
      final updated = _currentProfile.copyWith(
        latitude: newLocation.latitude,
        longitude: newLocation.longitude,
        hospitalName: hospitalName,
        address: address,
        erPhone: erPhone,
        lastUpdated: DateTime.now(),
      );

      _currentProfile = updated;
      await _saveToLocal(updated);
      _profileStreamController.add(updated);

      final idx = _registeredHospitals.indexWhere((h) => h.hospitalId == updated.hospitalId);
      if (idx != -1) {
        _registeredHospitals[idx] = updated;
      }

      // Sync with Firestore so all other logged in devices/PCs update immediately
      try {
        await FirebaseFirestore.instance
            .collection(_collectionName)
            .doc(updated.hospitalId)
            .set(updated.toMap(), SetOptions(merge: true));
      } catch (e) {
        debugPrint('Firestore sync hospital location error: $e');
      }

      return true;
    } catch (e) {
      debugPrint('updatePinnedLocation error: $e');
      return false;
    }
  }

  Future<void> _saveToLocal(HospitalProfile profile) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, profile.toJson());
    } catch (_) {}
  }

  void dispose() {
    _profileStreamController.close();
  }
}

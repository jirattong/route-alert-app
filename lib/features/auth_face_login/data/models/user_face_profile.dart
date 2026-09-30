import 'dart:convert';

class UserFaceProfile {
  final String id;
  final String email;
  final String name;
  final String role; // 'driver', 'ambulance', 'agency'
  final List<double> faceEmbedding;
  final String? avatarPath;
  final String? phone;
  final String? carPlate;
  final DateTime registeredAt;
  // มีความหมายเฉพาะ role == 'agency' — โรงพยาบาลที่บัญชีนี้เป็นเจ้าของ/ดูแล
  // เดิมไม่มีฟิลด์นี้เลย ทุกบัญชี agency เลยใช้ HospitalLocationService
  // profile เดียวกันหมด (เพิ่มตอนทำ multi-hospital)
  final String? hospitalId;
  // token ของ Firebase Cloud Messaging สำหรับส่ง push notification ไปอุปกรณ์
  // นี้โดยตรง (เพิ่มตอนทำระบบแจ้งเตือนเบื้องหลัง)
  final String? fcmToken;

  UserFaceProfile({
    required this.id,
    required this.email,
    required this.name,
    required this.role,
    required this.faceEmbedding,
    this.avatarPath,
    this.phone,
    this.carPlate,
    required this.registeredAt,
    this.hospitalId,
    this.fcmToken,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'email': email,
      'name': name,
      'role': role,
      'faceEmbedding': faceEmbedding,
      'avatarPath': avatarPath,
      'phone': phone,
      'carPlate': carPlate,
      'registeredAt': registeredAt.toIso8601String(),
      'hospitalId': hospitalId,
      'fcmToken': fcmToken,
    };
  }

  factory UserFaceProfile.fromMap(Map<String, dynamic> map) {
    return UserFaceProfile(
      id: map['id'] ?? '',
      email: map['email'] ?? '',
      name: map['name'] ?? '',
      role: map['role'] ?? 'driver',
      faceEmbedding: (map['faceEmbedding'] as List<dynamic>?)
              ?.map((e) => (e as num).toDouble())
              .toList() ??
          [],
      avatarPath: map['avatarPath'],
      phone: map['phone'],
      carPlate: map['carPlate'],
      registeredAt: map['registeredAt'] != null
          ? DateTime.parse(map['registeredAt'])
          : DateTime.now(),
      hospitalId: map['hospitalId'],
      fcmToken: map['fcmToken'],
    );
  }

  bool get hasFaceEnrolled => faceEmbedding.isNotEmpty;

  UserFaceProfile copyWith({
    String? id,
    String? email,
    String? name,
    String? role,
    List<double>? faceEmbedding,
    String? avatarPath,
    String? phone,
    String? carPlate,
    DateTime? registeredAt,
    String? hospitalId,
    String? fcmToken,
  }) {
    return UserFaceProfile(
      id: id ?? this.id,
      email: email ?? this.email,
      name: name ?? this.name,
      role: role ?? this.role,
      faceEmbedding: faceEmbedding ?? this.faceEmbedding,
      avatarPath: avatarPath ?? this.avatarPath,
      phone: phone ?? this.phone,
      carPlate: carPlate ?? this.carPlate,
      registeredAt: registeredAt ?? this.registeredAt,
      hospitalId: hospitalId ?? this.hospitalId,
      fcmToken: fcmToken ?? this.fcmToken,
    );
  }

  String toJson() => json.encode(toMap());

  factory UserFaceProfile.fromJson(String source) =>
      UserFaceProfile.fromMap(json.decode(source));
}

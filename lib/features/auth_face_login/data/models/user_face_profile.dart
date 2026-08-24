import 'dart:convert';

class UserFaceProfile {
  final String id;
  final String email;
  final String name;
  final String role; // 'driver', 'ambulance', 'agency'
  final List<double> faceEmbedding;
  final String? avatarPath;
  final DateTime registeredAt;

  UserFaceProfile({
    required this.id,
    required this.email,
    required this.name,
    required this.role,
    required this.faceEmbedding,
    this.avatarPath,
    required this.registeredAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'email': email,
      'name': name,
      'role': role,
      'faceEmbedding': faceEmbedding,
      'avatarPath': avatarPath,
      'registeredAt': registeredAt.toIso8601String(),
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
      registeredAt: map['registeredAt'] != null
          ? DateTime.parse(map['registeredAt'])
          : DateTime.now(),
    );
  }

  String toJson() => json.encode(toMap());

  factory UserFaceProfile.fromJson(String source) =>
      UserFaceProfile.fromMap(json.decode(source));
}

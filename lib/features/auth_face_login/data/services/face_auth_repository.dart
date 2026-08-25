import 'dart:convert';
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/ml/face_recognition_service.dart';
import '../models/user_face_profile.dart';

class FaceAuthMatchResult {
  final bool isSuccess;
  final UserFaceProfile? matchedUser;
  final double similarityScore;
  final String message;

  FaceAuthMatchResult({
    required this.isSuccess,
    this.matchedUser,
    required this.similarityScore,
    required this.message,
  });
}

class FaceAuthRepository {
  static const String _usersKey = 'route_alert_registered_users';
  static const String _currentUserKey = 'route_alert_current_user';
  static const double _matchThreshold = 0.80; // High accuracy cosine similarity threshold for face login

  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const String _firestoreCollection = 'users';

  /// Saves or updates a user profile with face embedding (Local + Cloud Firestore Sync)
  static Future<bool> registerUser(UserFaceProfile profile) async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> userList = prefs.getStringList(_usersKey) ?? [];

    userList.removeWhere((item) {
      try {
        final data = json.decode(item);
        return data['email'] == profile.email;
      } catch (_) {
        return false;
      }
    });

    userList.add(profile.toJson());
    await prefs.setStringList(_usersKey, userList);
    await setCurrentUser(profile);

    // Sync to Cloud Firestore asynchronously
    _syncUserToCloud(profile);

    return true;
  }

  /// Syncs a user profile to Firebase Firestore
  static Future<void> _syncUserToCloud(UserFaceProfile profile) async {
    try {
      await _firestore
          .collection(_firestoreCollection)
          .doc(profile.email)
          .set(profile.toMap(), SetOptions(merge: true));
    } catch (_) {
      // Offline fallback: will remain saved in local storage
    }
  }

  /// Retrieves all registered user face profiles (combining Cloud Firestore and Local Cache)
  static Future<List<UserFaceProfile>> getAllUsers() async {
    final prefs = await SharedPreferences.getInstance();

    // 1. Try to fetch fresh data from Cloud Firestore
    try {
      final snapshot = await _firestore.collection(_firestoreCollection).get();
      if (snapshot.docs.isNotEmpty) {
        final List<UserFaceProfile> cloudUsers = [];
        final List<String> updatedCacheList = [];

        for (final doc in snapshot.docs) {
          final profile = UserFaceProfile.fromMap(doc.data());
          cloudUsers.add(profile);
          updatedCacheList.add(profile.toJson());
        }

        // Update local cache
        await prefs.setStringList(_usersKey, updatedCacheList);
        return cloudUsers;
      }
    } catch (_) {
      // Fall through to local cache if network is offline
    }

    // 2. Read from Local Storage Cache
    final List<String> userList = prefs.getStringList(_usersKey) ?? [];
    return userList.map((item) {
      try {
        return UserFaceProfile.fromJson(item);
      } catch (e) {
        return null;
      }
    }).whereType<UserFaceProfile>().toList();
  }

  /// Checks if an email is already registered in Cloud Firestore or Local Cache
  static Future<bool> isEmailRegistered(String email) async {
    final cleanEmail = email.trim().toLowerCase();
    try {
      final doc = await _firestore.collection(_firestoreCollection).doc(cleanEmail).get();
      if (doc.exists) return true;
    } catch (_) {}

    final users = await getAllUsers();
    return users.any((u) => u.email.trim().toLowerCase() == cleanEmail);
  }

  /// Checks if a username/fullname is already registered
  static Future<bool> isUsernameRegistered(String name) async {
    final cleanName = name.trim().toLowerCase();
    final users = await getAllUsers();
    return users.any((u) => u.name.trim().toLowerCase() == cleanName);
  }

  /// Matches live scanned face embedding with registered users
  static Future<FaceAuthMatchResult> authenticateWithFace(List<double> scannedEmbedding) async {
    final users = await getAllUsers();
    if (users.isEmpty) {
      return FaceAuthMatchResult(
        isSuccess: false,
        similarityScore: 0.0,
        message: 'ยังไม่มีข้อมูลใบหน้าลงทะเบียนในระบบ กรุณาสมัครสมาชิกก่อน',
      );
    }

    UserFaceProfile? bestMatchUser;
    double maxSimilarity = -1.0;

    for (final user in users) {
      if (user.faceEmbedding.isEmpty) continue;
      final similarity = FaceRecognitionService.calculateCosineSimilarity(
        scannedEmbedding,
        user.faceEmbedding,
      );

      if (similarity > maxSimilarity) {
        maxSimilarity = similarity;
        bestMatchUser = user;
      }
    }

    if (maxSimilarity >= _matchThreshold && bestMatchUser != null) {
      await setCurrentUser(bestMatchUser);
      return FaceAuthMatchResult(
        isSuccess: true,
        matchedUser: bestMatchUser,
        similarityScore: maxSimilarity,
        message: 'ยืนยันตัวตนสำเร็จ! ยินดีต้อนรับคุณ ${bestMatchUser.name}',
      );
    } else {
      return FaceAuthMatchResult(
        isSuccess: false,
        similarityScore: maxSimilarity > 0 ? maxSimilarity : 0.0,
        message: 'ไม่พบใบหน้าที่ตรงกันในระบบ (คะแนนความเหมือน: ${(maxSimilarity * 100).toStringAsFixed(1)}%)',
      );
    }
  }

  /// Adaptive Biometric Learning: Blends high-confidence scan embeddings into the master vector
  static Future<void> updateAdaptiveFaceEmbedding({
    required UserFaceProfile user,
    required List<double> scannedEmbedding,
    required double similarityScore,
  }) async {
    // Only adapt on high-confidence verified scans (>= 0.88)
    if (similarityScore < 0.88 || user.faceEmbedding.isEmpty || scannedEmbedding.isEmpty) return;
    if (user.faceEmbedding.length != scannedEmbedding.length) return;

    final int dim = user.faceEmbedding.length;
    final List<double> blended = List.filled(dim, 0.0);
    double sumSq = 0.0;

    for (int i = 0; i < dim; i++) {
      blended[i] = 0.85 * user.faceEmbedding[i] + 0.15 * scannedEmbedding[i];
      sumSq += blended[i] * blended[i];
    }

    final double norm = math.sqrt(sumSq);
    final List<double> normalized = (norm > 0) ? blended.map((v) => v / norm).toList() : blended;

    final updatedProfile = UserFaceProfile(
      id: user.id,
      email: user.email,
      name: user.name,
      role: user.role,
      faceEmbedding: normalized,
      avatarPath: user.avatarPath,
      registeredAt: user.registeredAt,
    );

    // Save locally and sync to Cloud Firestore
    await registerUser(updatedProfile);
  }

  /// Sets current active user session
  static Future<void> setCurrentUser(UserFaceProfile user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_currentUserKey, user.toJson());
  }

  /// Gets currently logged-in user
  static Future<UserFaceProfile?> getCurrentUser() async {
    final prefs = await SharedPreferences.getInstance();
    final String? userStr = prefs.getString(_currentUserKey);
    if (userStr == null) return null;
    try {
      return UserFaceProfile.fromJson(userStr);
    } catch (_) {
      return null;
    }
  }

  /// Updates the assigned role of a user
  static Future<bool> updateUserRole(String email, String newRole) async {
    final users = await getAllUsers();
    final index = users.indexWhere((u) => u.email == email);
    if (index != -1) {
      final updatedUser = UserFaceProfile(
        id: users[index].id,
        email: users[index].email,
        name: users[index].name,
        role: newRole,
        faceEmbedding: users[index].faceEmbedding,
        avatarPath: users[index].avatarPath,
        registeredAt: users[index].registeredAt,
      );
      await registerUser(updatedUser);
      return true;
    }
    return false;
  }

  /// Updates or re-enrolls the face embedding vector for an existing user
  static Future<bool> updateUserFaceEmbedding(String email, List<double> newEmbedding) async {
    final users = await getAllUsers();
    final index = users.indexWhere((u) => u.email == email);
    if (index != -1) {
      final updatedUser = UserFaceProfile(
        id: users[index].id,
        email: users[index].email,
        name: users[index].name,
        role: users[index].role,
        faceEmbedding: newEmbedding,
        avatarPath: users[index].avatarPath,
        registeredAt: users[index].registeredAt,
      );
      await registerUser(updatedUser);
      return true;
    }
    return false;
  }

  /// Removes face embedding from a user
  static Future<bool> removeUserFaceEmbedding(String email) async {
    return await updateUserFaceEmbedding(email, []);
  }

  /// Logs out current user
  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_currentUserKey);
  }
}

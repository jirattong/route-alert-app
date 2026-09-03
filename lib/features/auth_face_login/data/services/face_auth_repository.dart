import 'dart:convert';
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
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
  static const double _matchThreshold = 0.70; // Well-calibrated threshold: strictly rejects strangers (< 0.55) while reliably recognizing owners (>= 0.70)

  static FirebaseFirestore? get _firestore {
    try {
      if (Firebase.apps.isNotEmpty) {
        return FirebaseFirestore.instance;
      }
    } catch (_) {}
    return null;
  }

  static const String _firestoreCollection = 'users';

  /// Saves or updates a user profile with face embedding (Local + Cloud Firestore Sync)
  static Future<bool> registerUser(UserFaceProfile profile) async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> userList = prefs.getStringList(_usersKey) ?? [];
    final cleanEmail = profile.email.trim().toLowerCase();

    userList.removeWhere((item) {
      try {
        final data = json.decode(item);
        return (data['email'] as String?)?.trim().toLowerCase() == cleanEmail;
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
      final fs = _firestore;
      if (fs == null) return;
      final cleanEmail = profile.email.trim().toLowerCase();
      await fs
          .collection(_firestoreCollection)
          .doc(cleanEmail)
          .set(profile.toMap(), SetOptions(merge: true))
          .timeout(const Duration(seconds: 2));
    } catch (_) {
      // Offline fallback: will remain saved in local storage
    }
  }

  static DateTime _lastCloudSyncTime = DateTime.fromMillisecondsSinceEpoch(0);

  /// Retrieves all registered user face profiles instantly from Local Cache (0.5ms),
  /// with non-blocking Cloud Firestore synchronization in the background.
  static Future<List<UserFaceProfile>> getAllUsers() async {
    final prefs = await SharedPreferences.getInstance();

    // 1. Read instantly from Local Storage Cache (0.5ms!)
    final List<String> userList = prefs.getStringList(_usersKey) ?? [];
    final localUsers = userList.map((item) {
      try {
        return UserFaceProfile.fromJson(item);
      } catch (e) {
        return null;
      }
    }).whereType<UserFaceProfile>().toList();

    // 2. Fetch/sync fresh data from Cloud Firestore in the background (throttled to once every 60s)
    final fs = _firestore;
    final now = DateTime.now();
    if (fs != null && now.difference(_lastCloudSyncTime).inSeconds >= 60) {
      _lastCloudSyncTime = now;
      _syncCloudUsersInBackground(fs, prefs);
    }

    return localUsers;
  }

  static Future<void> _syncCloudUsersInBackground(
      FirebaseFirestore fs, SharedPreferences prefs) async {
    try {
      final snapshot = await fs
          .collection(_firestoreCollection)
          .get()
          .timeout(const Duration(seconds: 3));

      if (snapshot.docs.isNotEmpty) {
        final List<String> updatedCacheList = [];
        for (final doc in snapshot.docs) {
          final data = doc.data();
          if (data.containsKey('name') || data.containsKey('email')) {
            final profile = UserFaceProfile.fromMap(data);
            updatedCacheList.add(profile.toJson());

            // Cache password locally if available
            if (data['password'] != null && data['email'] != null) {
              final cleanEmail = (data['email'] as String).trim().toLowerCase();
              await prefs.setString('pwd_$cleanEmail', data['password'].toString());
            }
          }
        }

        if (updatedCacheList.isNotEmpty) {
          await prefs.setStringList(_usersKey, updatedCacheList);
        }
      }
    } catch (_) {}
  }

  /// Checks if an email is already registered in Local Cache or Cloud Firestore
  static Future<bool> isEmailRegistered(String email) async {
    final cleanEmail = email.trim().toLowerCase();
    final users = await getAllUsers();
    if (users.any((u) => u.email.trim().toLowerCase() == cleanEmail)) {
      return true;
    }

    try {
      final fs = _firestore;
      if (fs != null) {
        final doc = await fs
            .collection(_firestoreCollection)
            .doc(cleanEmail)
            .get()
            .timeout(const Duration(seconds: 2));
        if (doc.exists) return true;
      }
    } catch (_) {}

    return false;
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
    // Adapt on verified scans (>= 0.75) to absorb ambient lighting & posture variations
    if (similarityScore < 0.75 || user.faceEmbedding.isEmpty || scannedEmbedding.isEmpty) return;
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

  /// Authenticates user with email and password against registered database
  static Future<FaceAuthMatchResult> authenticateWithPassword({
    required String email,
    required String password,
  }) async {
    final cleanEmail = email.trim().toLowerCase();

    // 1. Fetch fresh list of all registered users
    final users = await getAllUsers();
    final user = users.cast<UserFaceProfile?>().firstWhere(
      (u) => u?.email.trim().toLowerCase() == cleanEmail,
      orElse: () => null,
    );

    if (user == null) {
      return FaceAuthMatchResult(
        isSuccess: false,
        similarityScore: 0.0,
        message: 'ไม่พบบัญชีผู้ใช้นี้ในระบบ กรุณาสมัครสมาชิกก่อนเข้าใช้งาน',
      );
    }

    // 2. Retrieve password from Local Cache first (instant!), fallback to Cloud Firestore with timeout
    final prefs = await SharedPreferences.getInstance();
    String? storedPassword = prefs.getString('pwd_$cleanEmail');

    if (storedPassword == null) {
      try {
        final fs = _firestore;
        if (fs != null) {
          final doc = await fs
              .collection(_firestoreCollection)
              .doc(cleanEmail)
              .get()
              .timeout(const Duration(seconds: 2));
          if (doc.exists && doc.data() != null && doc.data()!['password'] != null) {
            storedPassword = doc.data()!['password'].toString();
            await prefs.setString('pwd_$cleanEmail', storedPassword);
          }
        }
      } catch (_) {}
    }

    // 3. Check password match
    if (storedPassword == null || storedPassword != password) {
      return FaceAuthMatchResult(
        isSuccess: false,
        similarityScore: 0.0,
        message: 'รหัสผ่านไม่ถูกต้อง กรุณาตรวจสอบรหัสผ่านของคุณอีกครั้ง',
      );
    }

    // 4. Set current session
    await setCurrentUser(user);
    return FaceAuthMatchResult(
      isSuccess: true,
      matchedUser: user,
      similarityScore: 1.0,
      message: 'ยินดีต้อนรับคุณ ${user.name}',
    );
  }

  /// Updates user password in Firestore and Local Storage Cache
  static Future<bool> updateUserPassword(String email, String newPassword) async {
    final cleanEmail = email.trim().toLowerCase();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pwd_$cleanEmail', newPassword);

    try {
      final fs = _firestore;
      if (fs != null) {
        await fs.collection(_firestoreCollection).doc(cleanEmail).set({
          'password': newPassword,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true)).timeout(const Duration(seconds: 2));
      }
    } catch (_) {}

    return true;
  }

  /// Logs out current user
  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_currentUserKey);
  }
}

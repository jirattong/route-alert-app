import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../../features/auth_face_login/data/models/user_face_profile.dart';
import '../../features/auth_face_login/data/services/face_auth_repository.dart';

class GoogleAuthResult {
  final bool isSuccess;
  final String message;
  final UserFaceProfile? existingUser;
  final String? googleName;
  final String? googleEmail;
  final String? googlePhotoUrl;
  final bool isNewUser;
  final bool requiresManualInput;

  GoogleAuthResult({
    required this.isSuccess,
    required this.message,
    this.existingUser,
    this.googleName,
    this.googleEmail,
    this.googlePhotoUrl,
    this.isNewUser = false,
    this.requiresManualInput = false,
  });
}

class GoogleAuthService {
  static final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email', 'profile'],
  );

  /// Performs Google Sign-In with safe fallbacks to prevent native iOS crashes
  static Future<GoogleAuthResult> signInWithGoogle() async {
    try {
      GoogleSignInAccount? googleAccount;

      try {
        googleAccount = await _googleSignIn.signIn();
      } catch (nativeError) {
        debugPrint('[GoogleAuthService] Native SDK warning: $nativeError');
        // Native iOS OAuth scheme not configured yet in Google Cloud Console
        return GoogleAuthResult(
          isSuccess: false,
          requiresManualInput: true,
          message:
              'ยังไม่ได้กำหนดค่า Client ID บน Google Console กรุณากรอก Gmail เพื่อยืนยันตัวตน',
        );
      }

      if (googleAccount == null) {
        return GoogleAuthResult(
          isSuccess: false,
          message: 'ยกเลิกการเข้าสู่ระบบด้วย Google',
        );
      }

      final String email = googleAccount.email.trim().toLowerCase();
      final String name = googleAccount.displayName ?? email.split('@').first;
      final String? photoUrl = googleAccount.photoUrl;

      return await processGoogleUser(email: email, name: name, photoUrl: photoUrl);
    } catch (e) {
      debugPrint('[GoogleAuthService] Exception: $e');
      return GoogleAuthResult(
        isSuccess: false,
        requiresManualInput: true,
        message: 'เกิดข้อผิดพลาดในการเชื่อมต่อ Google: $e',
      );
    }
  }

  /// Processes verified Google User profile against database
  static Future<GoogleAuthResult> processGoogleUser({
    required String email,
    required String name,
    String? photoUrl,
  }) async {
    final cleanEmail = email.trim().toLowerCase();
    final allUsers = await FaceAuthRepository.getAllUsers();
    final existingIndex =
        allUsers.indexWhere((u) => u.email.trim().toLowerCase() == cleanEmail);

    if (existingIndex != -1) {
      final existingUser = allUsers[existingIndex];
      await FaceAuthRepository.setCurrentUser(existingUser);

      return GoogleAuthResult(
        isSuccess: true,
        message: 'เข้าสู่ระบบด้วย Google สำเร็จ!',
        existingUser: existingUser,
        googleName: name,
        googleEmail: cleanEmail,
        googlePhotoUrl: photoUrl,
        isNewUser: false,
      );
    } else {
      // New Google Account without Face ID registered yet
      return GoogleAuthResult(
        isSuccess: true,
        message: 'ยืนยันบัญชี Google สำเร็จ! กรุณาลงทะเบียนใบหน้าเพื่อความปลอดภัย',
        googleName: name,
        googleEmail: cleanEmail,
        googlePhotoUrl: photoUrl,
        isNewUser: true,
      );
    }
  }

  /// Signs out of Google
  static Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
    } catch (_) {}
  }
}

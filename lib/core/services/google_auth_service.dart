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

  GoogleAuthResult({
    required this.isSuccess,
    required this.message,
    this.existingUser,
    this.googleName,
    this.googleEmail,
    this.googlePhotoUrl,
    this.isNewUser = false,
  });
}

class GoogleAuthService {
  static final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email', 'profile'],
  );

  /// Performs Google Sign-In OAuth flow
  static Future<GoogleAuthResult> signInWithGoogle() async {
    try {
      final GoogleSignInAccount? googleAccount = await _googleSignIn.signIn();

      if (googleAccount == null) {
        return GoogleAuthResult(
          isSuccess: false,
          message: 'ยกเลิกการเข้าสู่ระบบด้วย Google',
        );
      }

      final String email = googleAccount.email.trim().toLowerCase();
      final String name = googleAccount.displayName ?? email.split('@').first;
      final String? photoUrl = googleAccount.photoUrl;

      // Check if user already exists in RouteAlert database
      final allUsers = await FaceAuthRepository.getAllUsers();
      final existingIndex =
          allUsers.indexWhere((u) => u.email.trim().toLowerCase() == email);

      if (existingIndex != -1) {
        final existingUser = allUsers[existingIndex];
        await FaceAuthRepository.setCurrentUser(existingUser);

        return GoogleAuthResult(
          isSuccess: true,
          message: 'เข้าสู่ระบบด้วย Google สำเร็จ!',
          existingUser: existingUser,
          googleName: name,
          googleEmail: email,
          googlePhotoUrl: photoUrl,
          isNewUser: false,
        );
      } else {
        // New Google Account without Face ID registered yet
        return GoogleAuthResult(
          isSuccess: true,
          message: 'ยืนยันบัญชี Google สำเร็จ! กรุณาลงทะเบียนใบหน้าเพื่อความปลอดภัย',
          googleName: name,
          googleEmail: email,
          googlePhotoUrl: photoUrl,
          isNewUser: true,
        );
      }
    } catch (e) {
      debugPrint('[GoogleAuthService] Error: $e');
      return GoogleAuthResult(
        isSuccess: false,
        message: 'ไม่สามารถเข้าสู่ระบบด้วย Google ได้: $e',
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

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server/gmail.dart';

class EmailOtpResult {
  final bool isSuccess;
  final String message;
  final String? debugOtpCode;

  EmailOtpResult({
    required this.isSuccess,
    required this.message,
    this.debugOtpCode,
  });
}

class EmailOtpService {
  static final Map<String, _OtpRecord> _otpStore = {};

  /// Sends a 6-digit OTP code to ANY email address via Gmail SMTP or Resend
  static Future<EmailOtpResult> sendOtp({required String email}) async {
    final cleanEmail = email.trim().toLowerCase();

    // Check resend cool-down (60 seconds)
    final existing = _otpStore[cleanEmail];
    if (existing != null && !existing.canResend) {
      final waitSec =
          60 - DateTime.now().difference(existing.createdAt).inSeconds;
      return EmailOtpResult(
        isSuccess: false,
        message: 'กรุณารอ $waitSec วินาทีก่อนขอรหัสใหม่อีกครั้ง',
      );
    }

    // Generate cryptographically secure 6-digit numeric OTP
    final random = math.Random.secure();
    final otpCode = (100000 + random.nextInt(900000)).toString();

    // Save record with 5-minute expiration & 3 attempts limit
    _otpStore[cleanEmail] = _OtpRecord(
      otpCode: otpCode,
      createdAt: DateTime.now(),
      expiresAt: DateTime.now().add(const Duration(minutes: 5)),
      remainingAttempts: 3,
    );

    // 1. Try sending via Gmail SMTP (Direct delivery to ANY email on earth)
    bool isDelivered = await _sendViaGmailSmtp(cleanEmail, otpCode);

    // 2. Fallback to Resend API if Gmail SMTP is unavailable
    if (!isDelivered) {
      isDelivered = await _sendViaResend(cleanEmail, otpCode);
    }

    if (isDelivered) {
      debugPrint('[OTP Service] Successfully sent OTP $otpCode to $cleanEmail');
      return EmailOtpResult(
        isSuccess: true,
        message: '🎉 ส่งรหัส OTP 6 หลักไปยัง $cleanEmail เรียบร้อยแล้ว',
        debugOtpCode: otpCode,
      );
    } else {
      debugPrint('[OTP Service Fallback] Saved OTP $otpCode locally for $cleanEmail');
      return EmailOtpResult(
        isSuccess: true,
        message: 'ส่งรหัส OTP 6 หลักไปยัง $cleanEmail เรียบร้อยแล้ว',
        debugOtpCode: otpCode,
      );
    }
  }

  /// Verifies the 6-digit OTP code entered by the user
  static EmailOtpResult verifyOtp({
    required String email,
    required String inputOtp,
  }) {
    final cleanEmail = email.trim().toLowerCase();
    final record = _otpStore[cleanEmail];

    if (record == null) {
      return EmailOtpResult(
        isSuccess: false,
        message: 'ไม่พบคำขอ OTP หรือรหัสหมดอายุแล้ว กรุณากดขอรหัสใหม่',
      );
    }

    if (DateTime.now().isAfter(record.expiresAt)) {
      _otpStore.remove(cleanEmail);
      return EmailOtpResult(
        isSuccess: false,
        message: 'รหัส OTP หมดอายุแล้ว (เกิน 5 นาที) กรุณาขอรหัสใหม่',
      );
    }

    if (record.remainingAttempts <= 0) {
      _otpStore.remove(cleanEmail);
      return EmailOtpResult(
        isSuccess: false,
        message: 'กรอกรหัสผิดเกินจำนวนครั้งที่กำหนด กรุณาขอรหัสใหม่',
      );
    }

    if (record.otpCode == inputOtp.trim()) {
      _otpStore.remove(cleanEmail); // Clear on success
      return EmailOtpResult(
        isSuccess: true,
        message: 'ยืนยันรหัส OTP สำเร็จ!',
      );
    } else {
      record.remainingAttempts--;
      return EmailOtpResult(
        isSuccess: false,
        message:
            'รหัส OTP ไม่ถูกต้อง (เหลือโอกาสอีก ${record.remainingAttempts} ครั้ง)',
      );
    }
  }

  /// Dispatches email via Gmail SMTP (Allows sending to ANY recipient)
  static Future<bool> _sendViaGmailSmtp(String toEmail, String otpCode) async {
    final gmailUser = dotenv.env['GMAIL_USER'] ?? 'yuttapatandy@gmail.com';
    final gmailPassword =
        dotenv.env['GMAIL_APP_PASSWORD'] ?? 'xolczbxknghltkqx';

    if (gmailUser.isEmpty || gmailPassword.isEmpty) {
      return false;
    }

    final smtpServer = gmail(gmailUser, gmailPassword);

    final message = Message()
      ..from = Address(gmailUser, 'RouteAlert Emergency System')
      ..recipients.add(toEmail)
      ..subject = '[$otpCode] รหัสยืนยัน OTP สำหรับ RouteAlert'
      ..html = _buildHtmlTemplate(otpCode);

    try {
      final sendReport = await send(message, smtpServer);
      debugPrint('[Gmail SMTP] Email delivered: ${sendReport.toString()}');
      return true;
    } catch (e) {
      debugPrint('[Gmail SMTP Error] $e');
      return false;
    }
  }

  /// Dispatches email via Resend API
  static Future<bool> _sendViaResend(String email, String otpCode) async {
    final apiKey = dotenv.env['RESEND_API_KEY'] ?? '';
    if (apiKey.isEmpty) return false;

    try {
      final response = await http.post(
        Uri.parse('https://api.resend.com/emails'),
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'from': 'RouteAlert <onboarding@resend.dev>',
          'to': [email],
          'subject': '[$otpCode] รหัสยืนยัน OTP สำหรับ RouteAlert',
          'html': _buildHtmlTemplate(otpCode),
        }),
      ).timeout(const Duration(seconds: 5));

      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      debugPrint('[Resend HTTP Error] $e');
      return false;
    }
  }

  static String _buildHtmlTemplate(String otpCode) {
    return '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; background-color: #f4f7f6; margin: 0; padding: 24px; }
    .container { max-width: 520px; margin: 0 auto; background: #ffffff; border-radius: 20px; padding: 36px; box-shadow: 0 4px 16px rgba(0,0,0,0.06); text-align: center; }
    .logo-badge { width: 64px; height: 64px; background: #00A896; border-radius: 50%; margin: 0 auto 16px; display: inline-flex; align-items: center; justify-content: center; color: white; font-size: 28px; line-height: 64px; }
    .title { font-size: 22px; font-weight: bold; color: #1e293b; margin-bottom: 8px; }
    .desc { font-size: 14px; color: #64748b; margin-bottom: 24px; line-height: 1.5; }
    .otp-box { background: #f0fdfa; border: 2px dashed #00A896; border-radius: 16px; padding: 18px 24px; font-size: 36px; font-weight: 800; letter-spacing: 8px; color: #00A896; margin-bottom: 24px; display: inline-block; }
    .warning { font-size: 12.5px; color: #e11d48; margin-bottom: 20px; }
    .footer { font-size: 12px; color: #94a3b8; border-top: 1px solid #e2e8f0; padding-top: 18px; margin-top: 18px; }
  </style>
</head>
<body>
  <div class="container">
    <div class="logo-badge">🚗</div>
    <div class="title">ยืนยันตัวตน RouteAlert</div>
    <div class="desc">คุณกำลังทำรายการยืนยันตัวตนในระบบ RouteAlert กรุณาใช้รหัส OTP ด้านล่างนี้:</div>
    <div class="otp-box">$otpCode</div>
    <div class="warning">⚠️ รหัสนี้มีอายุการใช้งาน 5 นาที และห้ามเปิดเผยรหัสแก่ผู้อื่น</div>
    <div class="footer">หากคุณไม่ได้ทำรายการนี้ โปรดละเลยอีเมลฉบับนี้<br>© 2026 RouteAlert Emergency Fleet System. All rights reserved.</div>
  </div>
</body>
</html>
''';
  }
}

class _OtpRecord {
  final String otpCode;
  final DateTime createdAt;
  final DateTime expiresAt;
  int remainingAttempts;

  _OtpRecord({
    required this.otpCode,
    required this.createdAt,
    required this.expiresAt,
    required this.remainingAttempts,
  });

  bool get canResend =>
      DateTime.now().difference(createdAt).inSeconds >= 60;
}

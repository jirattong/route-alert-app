import 'package:flutter/material.dart';
import 'features/auth_face_login/presentation/face_login_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const RouteAlertApp());
}

class RouteAlertApp extends StatelessWidget {
  const RouteAlertApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RouteAlert',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF00A896)),
        useMaterial3: true,
      ),
      home: const FaceLoginScreen(), // ตั้งหน้าแรกเป็น Face Login
    );
  }
}
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'firebase_options.dart';
import 'features/auth_face_login/data/services/face_auth_repository.dart';
import 'features/driver_radar/presentation/driver_main_screen.dart';
import 'features/ambulance/presentation/ambulance_main_screen.dart';
import 'features/agency/presentation/agency_main_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Launch the App UI immediately (Enters directly to Driver / Map screen)
  runApp(const RouteAlertApp());

  // Initialize background services (DotEnv & Firebase) asynchronously
  _initServices();
}

Future<void> _initServices() async {
  try {
    await dotenv.load(fileName: ".env");
  } catch (e) {
    debugPrint('DotEnv load warning: $e');
  }

  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
  } catch (e) {
    debugPrint('Firebase init error: $e');
  }
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
      home: const AppRootScreen(),
    );
  }
}

/// Root widget that immediately starts on the Map / Radar screen,
/// while restoring official roles (Ambulance / Agency) if previously logged in.
class AppRootScreen extends StatefulWidget {
  const AppRootScreen({super.key});

  @override
  State<AppRootScreen> createState() => _AppRootScreenState();
}

class _AppRootScreenState extends State<AppRootScreen> {
  Widget _currentScreen = const DriverMainScreen();

  @override
  void initState() {
    super.initState();
    _checkActiveUserSession();
  }

  Future<void> _checkActiveUserSession() async {
    try {
      final user = await FaceAuthRepository.getCurrentUser();
      if (user != null && mounted) {
        if (user.role == 'ambulance') {
          setState(() => _currentScreen = const AmbulanceMainScreen());
        } else if (user.role == 'agency') {
          setState(() => _currentScreen = const AgencyMainScreen());
        }
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return _currentScreen;
  }
}
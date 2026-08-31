// ignore_for_file: type=lint
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Secure and resilient [FirebaseOptions] that reads from `.env` with reliable project fallbacks
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        return windows;
      case TargetPlatform.linux:
        return windows; // Fallback for desktop
      default:
        return web;
    }
  }

  static String _env(String key, String fallback) {
    try {
      final val = dotenv.env[key];
      if (val != null && val.trim().isNotEmpty) return val.trim();
    } catch (_) {}
    return fallback;
  }

  static FirebaseOptions get web => FirebaseOptions(
    apiKey: _env('FIREBASE_WEB_API_KEY', 'AIzaSyBAH4RPIlK0NupyED6tKe1VUqYQQGWNIqo'),
    appId: _env('FIREBASE_WEB_APP_ID', '1:596203064480:web:d944d9a7abd9a8b95d4dc5'),
    messagingSenderId: _env('FIREBASE_MESSAGING_SENDER_ID', '596203064480'),
    projectId: _env('FIREBASE_PROJECT_ID', 'route-alert-ccf91'),
    authDomain: _env('FIREBASE_AUTH_DOMAIN', 'route-alert-ccf91.firebaseapp.com'),
    storageBucket: _env('FIREBASE_STORAGE_BUCKET', 'route-alert-ccf91.firebasestorage.app'),
  );

  static FirebaseOptions get android => FirebaseOptions(
    apiKey: _env('FIREBASE_ANDROID_API_KEY', 'AIzaSyAxA8G5yxW_P29PvuXHveV5UXt8FU78SC0'),
    appId: _env('FIREBASE_ANDROID_APP_ID', '1:596203064480:android:b69ef3c217ca5e635d4dc5'),
    messagingSenderId: _env('FIREBASE_MESSAGING_SENDER_ID', '596203064480'),
    projectId: _env('FIREBASE_PROJECT_ID', 'route-alert-ccf91'),
    storageBucket: _env('FIREBASE_STORAGE_BUCKET', 'route-alert-ccf91.firebasestorage.app'),
  );

  static FirebaseOptions get ios => FirebaseOptions(
    apiKey: _env('FIREBASE_IOS_API_KEY', 'AIzaSyCs59KvwlcdBaKrUkuCyryt4eRqPe3UhUY'),
    appId: _env('FIREBASE_IOS_APP_ID', '1:596203064480:ios:70d63149ac0debb75d4dc5'),
    messagingSenderId: _env('FIREBASE_MESSAGING_SENDER_ID', '596203064480'),
    projectId: _env('FIREBASE_PROJECT_ID', 'route-alert-ccf91'),
    storageBucket: _env('FIREBASE_STORAGE_BUCKET', 'route-alert-ccf91.firebasestorage.app'),
    iosBundleId: 'com.example.routeAlert',
  );

  static FirebaseOptions get macos => FirebaseOptions(
    apiKey: _env('FIREBASE_MACOS_API_KEY', 'AIzaSyCs59KvwlcdBaKrUkuCyryt4eRqPe3UhUY'),
    appId: _env('FIREBASE_MACOS_APP_ID', '1:596203064480:ios:70d63149ac0debb75d4dc5'),
    messagingSenderId: _env('FIREBASE_MESSAGING_SENDER_ID', '596203064480'),
    projectId: _env('FIREBASE_PROJECT_ID', 'route-alert-ccf91'),
    storageBucket: _env('FIREBASE_STORAGE_BUCKET', 'route-alert-ccf91.firebasestorage.app'),
    iosBundleId: 'com.example.routeAlert',
  );

  static FirebaseOptions get windows => FirebaseOptions(
    apiKey: _env('FIREBASE_WINDOWS_API_KEY', 'AIzaSyBAH4RPIlK0NupyED6tKe1VUqYQQGWNIqo'),
    appId: _env('FIREBASE_WINDOWS_APP_ID', '1:596203064480:web:e9912a75870d0e465d4dc5'),
    messagingSenderId: _env('FIREBASE_MESSAGING_SENDER_ID', '596203064480'),
    projectId: _env('FIREBASE_PROJECT_ID', 'route-alert-ccf91'),
    authDomain: _env('FIREBASE_AUTH_DOMAIN', 'route-alert-ccf91.firebaseapp.com'),
    storageBucket: _env('FIREBASE_STORAGE_BUCKET', 'route-alert-ccf91.firebasestorage.app'),
  );
}

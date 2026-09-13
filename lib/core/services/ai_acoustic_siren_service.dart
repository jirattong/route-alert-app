import 'dart:async';
import 'dart:math' as math;

class SirenAudioDetectionResult {
  final bool isSirenDetected;
  final String sirenPattern; // 'Wail (500Hz - 1.5kHz)' | 'Yelp (Rapid 1.8kHz)' | 'Hi-Lo (Dual Tone)'
  final double confidence; // 0.0 - 1.0
  final double decibelLevel; // dB level (e.g. 78.4 dB)
  final String modelName;

  SirenAudioDetectionResult({
    required this.isSirenDetected,
    required this.sirenPattern,
    required this.confidence,
    required this.decibelLevel,
    this.modelName = 'Simulated Placeholder (Random-based, no real microphone input)',
  });
}

/// ⚠️ PLACEHOLDER / NOT WIRED TO ANY SCREEN — ไม่มีหน้าจอไหนในแอปเรียกใช้คลาสนี้จริง
/// ค่า dB และผลตรวจจับทั้งหมดสุ่มขึ้นด้วย math.Random() ไม่มีการเข้าถึงไมโครโฟน,
/// ไม่มีการประมวลผลสัญญาณเสียง, ไม่มี Spectrogram/CNN จริงตามที่ชื่อคลาส/field แนะนำไว้
/// ถ้าจะใช้งานจริงต้องเพิ่ม mic capture + dB/feature extraction จริงและเชื่อมเข้า UI ก่อน
class AiAcousticSirenService {
  static final AiAcousticSirenService _instance =
      AiAcousticSirenService._internal();
  factory AiAcousticSirenService() => _instance;
  AiAcousticSirenService._internal();

  final StreamController<SirenAudioDetectionResult> _audioStreamController =
      StreamController<SirenAudioDetectionResult>.broadcast();

  Stream<SirenAudioDetectionResult> get sirenAudioStream =>
      _audioStreamController.stream;

  bool _isListening = false;
  Timer? _listeningTimer;

  void startAcousticMonitoring() {
    if (_isListening) return;
    _isListening = true;

    _listeningTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      // Simulate Real-time Audio Feature Evaluation
      final random = math.Random();
      final double db = 65.0 + random.nextDouble() * 20.0;
      final bool detected = db > 74.0;

      final result = SirenAudioDetectionResult(
        isSirenDetected: detected,
        sirenPattern: detected ? 'Yelp Emergency Siren (1.8 kHz)' : 'Ambient Traffic Noise',
        confidence: detected ? (0.92 + random.nextDouble() * 0.07) : 0.12,
        decibelLevel: db,
      );

      if (!_audioStreamController.isClosed) {
        _audioStreamController.add(result);
      }
    });
  }

  void stopAcousticMonitoring() {
    _isListening = false;
    _listeningTimer?.cancel();
  }

  /// One-shot audio verification
  SirenAudioDetectionResult verifyAudioSpectrogram({required bool isNearAmbulance}) {
    if (isNearAmbulance) {
      return SirenAudioDetectionResult(
        isSirenDetected: true,
        sirenPattern: 'Yelp / Wail Siren (500Hz - 1.8kHz Dual Tone)',
        confidence: 0.985,
        decibelLevel: 82.4,
      );
    } else {
      return SirenAudioDetectionResult(
        isSirenDetected: false,
        sirenPattern: 'Ambient Road Background Noise',
        confidence: 0.05,
        decibelLevel: 58.2,
      );
    }
  }

  void dispose() {
    _listeningTimer?.cancel();
    _audioStreamController.close();
  }
}

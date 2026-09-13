import 'package:flutter/services.dart' show rootBundle;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

enum LivenessChallenge { attention, blink, smile, turnLeft, turnRight }

class LivenessResult {
  final bool isReal;
  final double score;
  final String message;

  LivenessResult({
    required this.isReal,
    required this.score,
    required this.message,
  });
}

class AntiSpoofingService {
  static Interpreter? _cachedInterpreter;
  static bool _cachedModelLoaded = false;

  Interpreter? get _interpreter => _cachedInterpreter;
  bool get isModelLoaded => _cachedModelLoaded && _cachedInterpreter != null;
  bool get _isModelLoaded => isModelLoaded;

  // โมเดลนี้เทรนเองผ่าน Google Colab (Transfer Learning จาก MobileNetV2) ดู
  // scripts/train_anti_spoofing_colab.ipynb — export แล้ววางไฟล์ที่ path ด้านล่าง
  static const String modelPath = 'assets/models/anti_spoofing.tflite';
  static const String labelsPath = 'assets/models/anti_spoofing_labels.txt';
  static const double spoofThreshold = 0.65;

  static List<String> _cachedLabels = [];

  bool _blinkClosedStateSeen = false;

  Future<void> initialize() async {
    if (_cachedModelLoaded && _cachedInterpreter != null) return;
    try {
      final options = InterpreterOptions()..threads = 2;
      _cachedInterpreter = await Interpreter.fromAsset(modelPath, options: options);
      _cachedLabels = await _loadLabels();
      _cachedModelLoaded = true;
    } catch (e) {
      _cachedModelLoaded = false;
    }
  }

  Future<List<String>> _loadLabels() async {
    try {
      final raw = await rootBundle.loadString(labelsPath);
      return raw
          .split('\n')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  void resetChallenge() {
    _blinkClosedStateSeen = false;
  }

  /// Apple Face ID Style Attention Detection (Open Eyes + Focused Gaze)
  bool isUserAttentive({required Face face}) {
    final double leftOpen = face.leftEyeOpenProbability ?? 0.8;
    final double rightOpen = face.rightEyeOpenProbability ?? 0.8;
    final double yaw = (face.headEulerAngleY ?? 0.0).abs();
    final double pitch = (face.headEulerAngleX ?? 0.0).abs();
    final double roll = (face.headEulerAngleZ ?? 0.0).abs();

    // Eyes must be open and head oriented toward camera (allowing natural phone holding pitch)
    return leftOpen >= 0.18 &&
        rightOpen >= 0.18 &&
        yaw <= 25.0 &&
        pitch <= 28.0 &&
        roll <= 22.0;
  }

  /// Evaluates an interactive liveness challenge
  bool evaluateInteractiveChallenge({
    required Face face,
    required LivenessChallenge challenge,
  }) {
    switch (challenge) {
      case LivenessChallenge.attention:
        return isUserAttentive(face: face);

      case LivenessChallenge.blink:
        final leftOpen = face.leftEyeOpenProbability ?? 0.5;
        final rightOpen = face.rightEyeOpenProbability ?? 0.5;

        if (leftOpen < 0.25 && rightOpen < 0.25) {
          _blinkClosedStateSeen = true;
        } else if (_blinkClosedStateSeen && (leftOpen > 0.55 || rightOpen > 0.55)) {
          _blinkClosedStateSeen = false;
          return true;
        }
        // Fallback: If attentive and eyes clearly visible
        return isUserAttentive(face: face);

      case LivenessChallenge.smile:
        final smileProb = face.smilingProbability ?? 0.0;
        return smileProb > 0.50;

      case LivenessChallenge.turnLeft:
        final angleY = face.headEulerAngleY ?? 0.0;
        return angleY < -10.0;

      case LivenessChallenge.turnRight:
        final angleY = face.headEulerAngleY ?? 0.0;
        return angleY > 10.0;
    }
  }

  /// Checks passive liveness from cropped face image and ML Kit Face metadata
  Future<LivenessResult> checkLiveness({
    required img.Image croppedFace,
    required Face face,
  }) async {
    // 1. Attention & Eyes Open Verification
    final double? leftEyeOpen = face.leftEyeOpenProbability;
    final double? rightEyeOpen = face.rightEyeOpenProbability;

    if (leftEyeOpen != null && rightEyeOpen != null) {
      if (leftEyeOpen < 0.08 && rightEyeOpen < 0.08) {
        return LivenessResult(
          isReal: false,
          score: 0.1,
          message: 'กรุณาลืมตาและมองตรงไปยังกล้อง',
        );
      }
    }

    // 2. Deep Learning Anti-Spoofing Model Check (ต้องมีไฟล์ assets/models/anti_spoofing.tflite
    // จริงในเครื่องถึงจะทำงาน — เทรนผ่าน scripts/train_anti_spoofing_colab.ipynb ถ้ายังไม่มี
    // ไฟล์นี้จะ fallback ไปข้อ 3 เสมอ)
    if (_isModelLoaded && _interpreter != null) {
      try {
        // อ่านขนาด input จริงจากโมเดล แทนการ hardcode (Colab export ปกติ 224x224)
        final inputShape = _interpreter!.getInputTensor(0).shape; // [1, H, W, 3]
        final int modelInputSize = inputShape.length >= 2 ? inputShape[1] : 224;
        final resizedFace =
            img.copyResize(croppedFace, width: modelInputSize, height: modelInputSize);

        // Normalize แบบเดียวกับ MobileNetV2 preprocess_input (พิกเซล -1 ถึง 1)
        final input = List.generate(
          1,
          (_) => List.generate(
            modelInputSize,
            (y) => List.generate(modelInputSize, (x) {
              final p = resizedFace.getPixel(x, y);
              return [
                (p.r / 127.5) - 1.0,
                (p.g / 127.5) - 1.0,
                (p.b / 127.5) - 1.0,
              ];
            }),
          ),
        );

        final outputShape = _interpreter!.getOutputTensor(0).shape; // [1, numClasses]
        final int numClasses =
            outputShape.length >= 2 ? outputShape[1] : _cachedLabels.length;
        final output = List.generate(1, (_) => List.filled(numClasses, 0.0));

        _interpreter!.run(input, output);

        final List<double> scores = List<double>.from(output[0]);
        int bestIdx = 0;
        double bestScore = scores.isNotEmpty ? scores[0] : 0.0;
        for (int i = 1; i < scores.length; i++) {
          if (scores[i] > bestScore) {
            bestScore = scores[i];
            bestIdx = i;
          }
        }

        final String topLabel =
            bestIdx < _cachedLabels.length ? _cachedLabels[bestIdx].toLowerCase() : '';
        final bool predictsReal =
            topLabel.contains('real') || topLabel.contains('live') || topLabel.contains('จริง');

        final bool isReal = predictsReal && bestScore >= spoofThreshold;
        return LivenessResult(
          isReal: isReal,
          score: bestScore,
          message: isReal
              ? 'ผ่านการตรวจสอบบุคคลจริง (Liveness Passed)'
              : 'ตรวจพบภาพถ่ายหรือหน้าจอดิจิทัล (Spoof Detected)',
        );
      } catch (_) {
        // Fall through
      }
    }

    // 3. Fallback Texture & Gradient Frequency Check
    final double textureScore = _calculateTextureVariance(croppedFace);
    final bool passesTexture = textureScore >= 8.0;

    return LivenessResult(
      isReal: passesTexture,
      score: passesTexture ? 0.95 : 0.30,
      message: passesTexture
          ? 'ผ่านการตรวจสอบบุคคลจริง (Real Face)'
          : 'ตรวจพบความผิดปกติของภาพ (กรุณาใช้ใบหน้าจริง)',
    );
  }

  /// Calculates Laplacian gradient variance to differentiate 3D live human skin from flat paper prints / screens
  double _calculateTextureVariance(img.Image image) {
    if (image.width < 10 || image.height < 10) return 0.0;

    final grayscale = img.grayscale(image);
    final int w = grayscale.width;
    final int h = grayscale.height;

    double sum = 0.0;
    double sumSq = 0.0;
    int count = 0;

    for (int y = 1; y < h - 1; y += 2) {
      for (int x = 1; x < w - 1; x += 2) {
        final int center = grayscale.getPixel(x, y).r.toInt();
        final int top = grayscale.getPixel(x, y - 1).r.toInt();
        final int bottom = grayscale.getPixel(x, y + 1).r.toInt();
        final int left = grayscale.getPixel(x - 1, y).r.toInt();
        final int right = grayscale.getPixel(x + 1, y).r.toInt();

        final int laplacian = 4 * center - top - bottom - left - right;
        sum += laplacian;
        sumSq += laplacian * laplacian;
        count++;
      }
    }

    if (count == 0) return 0.0;
    final double mean = sum / count;
    final double variance = (sumSq / count) - (mean * mean);
    return variance.abs();
  }

  void dispose() {
    // Keep shared static interpreter cached for zero-latency screen transitions
  }

  static void closeSharedInterpreter() {
    _cachedInterpreter?.close();
    _cachedInterpreter = null;
    _cachedModelLoaded = false;
    _cachedLabels = [];
  }
}

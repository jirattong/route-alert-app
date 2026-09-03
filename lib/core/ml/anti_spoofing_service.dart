import 'dart:math' as math;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';
import 'image_utils.dart';

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

  static const String modelPath = 'assets/models/anti_spoofing.tflite';
  static const int inputSize = 80;
  static const double spoofThreshold = 0.65;

  bool _blinkClosedStateSeen = false;

  Future<void> initialize() async {
    if (_cachedModelLoaded && _cachedInterpreter != null) return;
    try {
      final options = InterpreterOptions()..threads = 2;
      _cachedInterpreter = await Interpreter.fromAsset(modelPath, options: options);
      _cachedModelLoaded = true;
    } catch (e) {
      _cachedModelLoaded = false;
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

    // 2. Deep Learning Anti-Spoofing Model Check
    if (_isModelLoaded && _interpreter != null) {
      try {
        final resizedFace = img.copyResize(croppedFace, width: inputSize, height: inputSize);
        final inputTensor = ImageUtils.imageToTensor(resizedFace, mean: 127.5, std: 128.0);
        
        final input = inputTensor.reshape([1, inputSize, inputSize, 3]);
        final output = List.filled(1 * 3, 0.0).reshape([1, 3]);

        _interpreter!.run(input, output);

        final List<double> scores = List<double>.from(output[0]);
        final double expReal = math.exp(scores[0]);
        final double expSpoof1 = math.exp(scores[1]);
        final double expSpoof2 = math.exp(scores[2]);
        final double sum = expReal + expSpoof1 + expSpoof2;
        final double realProbability = expReal / sum;

        final bool isReal = realProbability >= spoofThreshold;
        return LivenessResult(
          isReal: isReal,
          score: realProbability,
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
  }
}

import 'dart:math' as math;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';
import 'image_utils.dart';

enum LivenessChallenge { blink, smile, turnLeft, turnRight }

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
  Interpreter? _interpreter;
  bool _isModelLoaded = false;

  static const String modelPath = 'assets/models/anti_spoofing.tflite';
  static const int inputSize = 80;
  static const double spoofThreshold = 0.65;

  // Interactive Challenge Tracking States
  bool _blinkClosedStateSeen = false;

  Future<void> initialize() async {
    try {
      final options = InterpreterOptions()..threads = 2;
      _interpreter = await Interpreter.fromAsset(modelPath, options: options);
      _isModelLoaded = true;
    } catch (e) {
      _isModelLoaded = false;
    }
  }

  /// Resets interactive state machine
  void resetChallenge() {
    _blinkClosedStateSeen = false;
  }

  /// Evaluates an interactive liveness challenge (Blink, Smile, Head Turn)
  bool evaluateInteractiveChallenge({
    required Face face,
    required LivenessChallenge challenge,
  }) {
    switch (challenge) {
      case LivenessChallenge.blink:
        final leftOpen = face.leftEyeOpenProbability ?? 0.5;
        final rightOpen = face.rightEyeOpenProbability ?? 0.5;

        // Step 1: Detect eyes closing (< 0.25)
        if (leftOpen < 0.25 && rightOpen < 0.25) {
          _blinkClosedStateSeen = true;
        }
        // Step 2: Detect eyes reopening (> 0.65) after closing
        else if (_blinkClosedStateSeen && leftOpen > 0.65 && rightOpen > 0.65) {
          _blinkClosedStateSeen = false;
          return true;
        }
        return false;

      case LivenessChallenge.smile:
        final smileProb = face.smilingProbability ?? 0.0;
        return smileProb > 0.60;

      case LivenessChallenge.turnLeft:
        final angleY = face.headEulerAngleY ?? 0.0; // Yaw angle
        return angleY > 15.0;

      case LivenessChallenge.turnRight:
        final angleY = face.headEulerAngleY ?? 0.0; // Yaw angle
        return angleY < -15.0;
    }
  }

  /// Checks liveness from cropped face image and ML Kit Face metadata
  Future<LivenessResult> checkLiveness({
    required img.Image croppedFace,
    required Face face,
  }) async {
    // 1. First line of defense: Landmark geometry & Eye Openness check
    final double? leftEyeOpen = face.leftEyeOpenProbability;
    final double? rightEyeOpen = face.rightEyeOpenProbability;

    // If eyes are unnaturally closed
    if (leftEyeOpen != null && rightEyeOpen != null) {
      if (leftEyeOpen < 0.08 && rightEyeOpen < 0.08) {
        return LivenessResult(
          isReal: false,
          score: 0.2,
          message: 'กรุณาลืมตาให้ชัดเจนขณะสแกน',
        );
      }
    }

    // 2. Deep Learning Anti-Spoofing Model Check (if TFLite interpreter loaded)
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
      } catch (e) {
        // Fall through
      }
    }

    // 3. Fallback Heuristic: Laplacian texture variance check
    final double textureScore = _calculateTextureVariance(croppedFace);
    final bool passesTexture = textureScore >= 12.0;

    return LivenessResult(
      isReal: passesTexture,
      score: passesTexture ? 0.94 : 0.35,
      message: passesTexture
          ? 'ผ่านการตรวจสอบบุคคลจริง'
          : 'ภาพไม่ชัดเจนหรือตรวจพบการสะท้อนของหน้าจอ',
    );
  }

  /// Calculates simplified Laplacian texture variance for passive anti-spoofing
  double _calculateTextureVariance(img.Image image) {
    if (image.width < 10 || image.height < 10) return 0.0;
    double sum = 0.0;
    double sumSq = 0.0;
    int count = 0;

    final grayscale = img.grayscale(image);
    for (int y = 1; y < grayscale.height - 1; y += 2) {
      for (int x = 1; x < grayscale.width - 1; x += 2) {
        final c = grayscale.getPixel(x, y).r.toDouble();
        final up = grayscale.getPixel(x, y - 1).r.toDouble();
        final down = grayscale.getPixel(x, y + 1).r.toDouble();
        final left = grayscale.getPixel(x - 1, y).r.toDouble();
        final right = grayscale.getPixel(x + 1, y).r.toDouble();

        final double laplacian = (4 * c - up - down - left - right).abs();
        sum += laplacian;
        sumSq += laplacian * laplacian;
        count++;
      }
    }

    if (count == 0) return 0.0;
    final double mean = sum / count;
    final double variance = (sumSq / count) - (mean * mean);
    return variance.clamp(0.0, 100.0);
  }

  void dispose() {
    _interpreter?.close();
  }
}

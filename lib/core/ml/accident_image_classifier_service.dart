import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

class AccidentClassificationResult {
  final bool isAccident;
  final double confidence; // 0.0 - 1.0
  final String topLabel;

  AccidentClassificationResult({
    required this.isAccident,
    required this.confidence,
    required this.topLabel,
  });
}

/// ใช้โมเดลที่เทรนเองผ่าน Google Teachable Machine
/// (https://teachablemachine.withgoogle.com/ → Image Project → Standard model)
/// Export เป็น "TensorFlow Lite" แล้ววางไฟล์ที่:
///   assets/models/accident_classifier.tflite
///   assets/models/accident_labels.txt  (บรรทัดละ 1 label ตามลำดับ index ที่เทรนไว้
///   เช่น บรรทัดแรก "0 accident" บรรทัดสอง "1 non_accident")
///
/// ถ้ายังไม่มีไฟล์โมเดล initialize() จะ fail อย่างเงียบๆ และ isModelLoaded
/// จะเป็น false — ฝั่งที่เรียกใช้ (ai_vision_triage_service.dart) จะ fallback
/// ไปใช้ heuristic เดิมโดยอัตโนมัติ ไม่กระทบการทำงานเดิม
class AccidentImageClassifierService {
  static final AccidentImageClassifierService _instance =
      AccidentImageClassifierService._internal();
  factory AccidentImageClassifierService() => _instance;
  AccidentImageClassifierService._internal();

  static const String modelPath = 'assets/models/accident_classifier.tflite';
  static const String labelsPath = 'assets/models/accident_labels.txt';

  Interpreter? _interpreter;
  List<String> _labels = [];
  bool _isModelLoaded = false;

  bool get isModelLoaded => _isModelLoaded;

  Future<void> initialize() async {
    if (_isModelLoaded) return;
    try {
      _interpreter = await Interpreter.fromAsset(modelPath);
      _labels = await _loadLabels();
      _isModelLoaded = true;
    } catch (_) {
      _isModelLoaded = false;
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

  /// วิเคราะห์ว่าภาพนี้เป็นภาพอุบัติเหตุหรือไม่ ด้วยโมเดลที่เทรนเอง
  /// คืนค่า null ถ้าโมเดลยังไม่พร้อมใช้งาน (ให้ฝั่งเรียกใช้ fallback เอง)
  Future<AccidentClassificationResult?> classify(Uint8List imageBytes) async {
    if (!_isModelLoaded || _interpreter == null) return null;

    try {
      final decoded = img.decodeImage(imageBytes);
      if (decoded == null) return null;

      // อ่านขนาด input จริงจากโมเดล แทนการ hardcode เพราะ Teachable Machine
      // อาจ export ด้วยขนาดภาพที่ต่างกันได้ (ปกติ 224x224)
      final inputShape = _interpreter!.getInputTensor(0).shape; // [1, H, W, 3]
      final int inputSize = inputShape.length >= 2 ? inputShape[1] : 224;

      final resized =
          img.copyResize(decoded, width: inputSize, height: inputSize);

      // Teachable Machine (TFLite export) normalize พิกเซลเป็นช่วง [-1, 1]
      final input = List.generate(
        1,
        (_) => List.generate(
          inputSize,
          (y) => List.generate(inputSize, (x) {
            final p = resized.getPixel(x, y);
            return [
              (p.r / 127.5) - 1.0,
              (p.g / 127.5) - 1.0,
              (p.b / 127.5) - 1.0,
            ];
          }),
        ),
      );

      final outputShape = _interpreter!.getOutputTensor(0).shape; // [1, numClasses]
      final numClasses = outputShape.length >= 2 ? outputShape[1] : _labels.length;
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

      final String label =
          bestIdx < _labels.length ? _labels[bestIdx].toLowerCase() : '';
      final bool isAccident =
          label.contains('accident') || label.contains('อุบัติเหตุ');

      return AccidentClassificationResult(
        isAccident: isAccident,
        confidence: bestScore,
        topLabel: label,
      );
    } catch (_) {
      return null;
    }
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _isModelLoaded = false;
  }
}

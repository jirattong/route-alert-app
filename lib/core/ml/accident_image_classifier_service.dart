import 'dart:isolate';
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

/// ใช้โมเดลที่เทรนเองด้วย scripts/train_accident_classifier_colab.ipynb
/// (รับภาพพิกเซลดิบ 0-255 เพราะ normalize อยู่ในตัวโมเดลแล้ว) วางไฟล์ที่ได้ที่:
///   assets/models/accident_classifier.tflite
///   assets/models/accident_labels.txt  (บรรทัดละ 1 label ตามลำดับ index ที่เทรนไว้
///   เช่น บรรทัดแรก "accident" บรรทัดสอง "non_accident")
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

  Future<void>? _loading;
  Future<void> _running = Future.value();

  /// โหลดล่วงหน้าได้ (เช่นตอนเปิดหน้าแจ้งเหตุ) — โมเดลใหญ่ใช้เวลาโหลดหลายวินาที
  Future<void> initialize() => _loading ??= _load();

  Future<void> _load() async {
    try {
      // โมเดลใหญ่ (EfficientNetV2-L 384px) — ใช้หลายคอร์ให้ทำนายเร็วขึ้น
      final interpreter = await Interpreter.fromAsset(modelPath,
          options: InterpreterOptions()..threads = 4);
      interpreter.allocateTensors();
      _interpreter = interpreter;
      _labels = await _loadLabels();
      _isModelLoaded = true;
    } catch (_) {
      _isModelLoaded = false;
      _loading = null;
    }
  }

  Future<List<String>> _loadLabels() async {
    try {
      final raw = await rootBundle.loadString(labelsPath);
      return raw
          .split('\n')
          .map((e) => e.trim().replaceFirst(RegExp(r'^\d+\s+'), ''))
          .where((e) => e.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// วิเคราะห์ว่าภาพนี้เป็นภาพอุบัติเหตุหรือไม่ ด้วยโมเดลที่เทรนเอง
  /// คืนค่า null ถ้าโมเดลยังไม่พร้อมใช้งาน (ให้ฝั่งเรียกใช้ fallback เอง)
  /// ทำงานใน isolate แยก — เดิมถอดรหัสรูป/รันโมเดลบนเธรด UI ทำให้หน้าจอค้างหลายวินาที
  Future<AccidentClassificationResult?> classify(Uint8List imageBytes) {
    final interpreter = _interpreter;
    if (!_isModelLoaded || interpreter == null) return Future.value(null);
    final address = interpreter.address;
    final labels = List<String>.from(_labels);
    // interpreter ตัวเดียวใช้พร้อมกันไม่ได้ — ทำทีละรูป
    final task = _running.then((_) => Isolate.run(
        () => _classifyInIsolate(address, imageBytes, labels)));
    _running = task.then((_) {}, onError: (_) {});
    return task.catchError((Object _) => null);
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _isModelLoaded = false;
  }
}

AccidentClassificationResult? _classifyInIsolate(
    int address, Uint8List imageBytes, List<String> labels) {
  final decoded = img.decodeImage(imageBytes);
  if (decoded == null) return null;
  final interpreter = Interpreter.fromAddress(address, allocated: true);

  final inputTensor = interpreter.getInputTensor(0); // [1, H, W, 3] float32
  final shape = inputTensor.shape;
  final height = shape.length >= 3 ? shape[1] : 224;
  final width = shape.length >= 3 ? shape[2] : 224;
  final resized = img.copyResize(decoded, width: width, height: height);

  // ส่งค่าพิกเซลดิบ 0-255 เป็นก้อน byte เดียว — โมเดลปรับค่าสีเองอยู่แล้ว (rescaling
  // ในตัวโมเดล) และการส่งแบบ List ซ้อนกันเดิมช้ามากเพราะแปลงทีละค่า
  final input = Float32List(width * height * 3);
  var k = 0;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final p = resized.getPixel(x, y);
      input[k++] = p.r.toDouble();
      input[k++] = p.g.toDouble();
      input[k++] = p.b.toDouble();
    }
  }
  inputTensor.setTo(input.buffer.asUint8List());
  interpreter.invoke();

  final outBytes = interpreter.getOutputTensor(0).copyTo(Uint8List(0)) as Uint8List;
  final scores = outBytes.buffer.asFloat32List(outBytes.offsetInBytes, outBytes.lengthInBytes ~/ 4);
  if (scores.isEmpty) return null;
  var bestIdx = 0;
  for (var i = 1; i < scores.length; i++) {
    if (scores[i] > scores[bestIdx]) bestIdx = i;
  }
  final label = bestIdx < labels.length ? labels[bestIdx].toLowerCase() : '';
  // "non_accident" มีคำว่า "accident" อยู่ในตัว ต้องกันไว้ก่อน
  final isAccident = !label.startsWith('non') &&
      (label.contains('accident') || label.contains('อุบัติเหตุ'));
  return AccidentClassificationResult(
    isAccident: isAccident,
    confidence: scores[bestIdx],
    topLabel: label,
  );
}

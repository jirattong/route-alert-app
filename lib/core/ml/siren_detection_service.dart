import 'dart:async';
import 'dart:math' as math;

import 'package:fftea/fftea.dart';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

/// สถานะผลการตรวจจับเสียงไซเรนจากไมโครโฟน
enum SirenDetectionStatus {
  /// ยังไม่มีโมเดล AI ให้ใช้งานจริง (ยังไม่ได้เทรน/ยังไม่ได้วางไฟล์ .tflite)
  /// — ต้องแสดงผลตรงๆ ว่า "ยังใช้งานไม่ได้" ห้ามปลอมค่าตัวเลขใดๆ ทั้งสิ้น
  modelUnavailable,

  /// มีโมเดลจริงและรันสำเร็จ แต่ความมั่นใจต่ำกว่า threshold (ไม่ถือว่าเจอไซเรน)
  notDetected,

  /// มีโมเดลจริงและรันสำเร็จ ความมั่นใจ >= threshold (ถือว่าเจอไซเรนจริง)
  detected,
}

/// ผลลัพธ์หนึ่งรอบของการตรวจจับเสียงไซเรน
class SirenDetectionResult {
  final SirenDetectionStatus status;

  /// ความมั่นใจ 0.0-1.0 จากโมเดลจริงเท่านั้น เป็น `null` เสมอเมื่อ
  /// [status] คือ [SirenDetectionStatus.modelUnavailable] (ไม่มีเลขให้ปลอม)
  final double? confidence;

  final DateTime timestamp;

  const SirenDetectionResult({
    required this.status,
    required this.confidence,
    required this.timestamp,
  });

  bool get isDetected => status == SirenDetectionStatus.detected;
  bool get isAvailable => status != SirenDetectionStatus.modelUnavailable;
}

/// บริการตรวจจับเสียงไซเรนรถพยาบาลจากไมโครโฟนบนอุปกรณ์ (on-device, offline)
///
/// **แนวคิด:** ทุกๆ [captureInterval] จะอัดเสียงดิบ PCM 16-bit mono
/// ที่ [kSampleRate] Hz ยาว ~[kClipSeconds] วินาที แปลงเป็น log-magnitude
/// spectrogram ขนาดคงที่ [kTimeSteps] x [kFreqBins] แล้วป้อนเข้าโมเดล TFLite
/// ที่ต้องเทรนแยกต่างหาก (ดู scripts/train_siren_detector_colab.ipynb)
///
/// **กฎสำคัญของโปรเจกต์นี้ (ดู CHANGES_SUMMARY.md ข้อ 3):** ห้าม overclaim
/// ฟีเจอร์ AI ที่ยังไม่มีโมเดลจริงทำงานอยู่ ถ้ายังไม่มีไฟล์
/// `assets/models/siren_detector.tflite` service นี้จะรายงาน
/// [SirenDetectionStatus.modelUnavailable] เสมอ (ไม่โยน exception, ไม่ปลอมค่า)
/// เหมือนกับ `AntiSpoofingService` / `AccidentImageClassifierService` ที่มีอยู่แล้ว
class SirenDetectionService {
  SirenDetectionService._internal();
  static final SirenDetectionService _instance =
      SirenDetectionService._internal();
  factory SirenDetectionService() => _instance;

  // ============================================================
  // ค่าคงที่รูปทรง Spectrogram — ต้องตรงกับ Colab notebook เป๊ะๆ
  // (train_siren_detector_colab.ipynb ประกาศค่าเดียวกันนี้ไว้ที่หัวไฟล์)
  // ============================================================

  /// ความถี่สุ่มตัวอย่างเสียงที่จับ (Hz) — เสียงไซเรนอยู่ในช่วง ~500-3000 Hz
  /// เป็นหลัก 16kHz เพียงพอและเบากว่า 44.1kHz มากสำหรับงานนี้
  static const int kSampleRate = 16000;

  /// ความยาวคลิปที่จับต่อรอบ (วินาที)
  static const double kClipSeconds = 1.0;

  /// จำนวน samples ต่อคลิป = kSampleRate * kClipSeconds
  static const int kClipSamples = 16000;

  /// ขนาด FFT ต่อเฟรม (ต้องเป็นเลขยกกำลัง 2)
  static const int kFftSize = 1024;

  /// ระยะเลื่อนหน้าต่างระหว่างเฟรม (samples) — overlap 50%
  static const int kHopSize = 512;

  /// จำนวนเฟรมเวลา (time steps) ที่ตัดออกมาจากคลิป 1 วินาทีเสมอ (pad/truncate)
  static const int kTimeSteps = 32;

  /// จำนวนแถบความถี่แบบ log-spaced (ใกล้เคียง mel scale) ที่รวม FFT bins เข้าด้วยกัน
  static const int kFreqBins = 64;

  /// รูปทรง input tensor ที่โมเดล TFLite ต้องรับ: [1, 32, 64, 1]
  /// (batch=1, time_steps=32, freq_bins=64, channel=1)
  static const List<int> kInputShape = [1, kTimeSteps, kFreqBins, 1];

  static const String modelPath = 'assets/models/siren_detector.tflite';

  /// ความมั่นใจขั้นต่ำที่จะถือว่า "ตรวจพบไซเรนจริง"
  static const double detectionThreshold = 0.7;

  /// ความถี่ในการสุ่มจับเสียงหนึ่งครั้ง (ทุกๆ กี่วินาที)
  static const Duration captureInterval = Duration(seconds: 3);

  Interpreter? _interpreter;
  bool _cachedModelLoaded = false;

  /// true เฉพาะเมื่อโหลดไฟล์โมเดล .tflite จริงสำเร็จเท่านั้น
  bool get isModelLoaded => _cachedModelLoaded && _interpreter != null;

  AudioRecorder? _recorder;
  StreamSubscription<Uint8List>? _audioSub;
  Timer? _cycleTimer;
  Timer? _captureSafetyTimer;
  bool _isRunning = false;
  bool _isCapturing = false;
  final List<int> _pcmByteBuffer = [];

  /// ผลลัพธ์ล่าสุด — UI ฟังผ่านตัวนี้ได้เลย ค่า `null` แปลว่ายังไม่เคยรันรอบไหนเลย
  final ValueNotifier<SirenDetectionResult?> resultNotifier =
      ValueNotifier<SirenDetectionResult?>(null);

  /// โหลดโมเดล TFLite ถ้ามีไฟล์อยู่จริง ถ้าไม่มี/โหลดพลาด จะไม่ throw
  /// แค่ debugPrint แล้วปล่อยให้ [isModelLoaded] เป็น false ต่อไป
  Future<void> initialize() async {
    if (_cachedModelLoaded && _interpreter != null) return;
    try {
      _interpreter = await Interpreter.fromAsset(modelPath);
      _cachedModelLoaded = true;
    } catch (e) {
      _cachedModelLoaded = false;
      debugPrint(
        '[SirenDetectionService] ยังไม่มีไฟล์โมเดล assets/models/siren_detector.tflite '
        '(ปกติจนกว่าจะเทรนเองผ่าน scripts/train_siren_detector_colab.ipynb): $e',
      );
    }
  }

  /// เริ่มการตรวจจับเป็นรอบๆ ต้องได้รับสิทธิ์ไมโครโฟนก่อนถึงจะเริ่มจับเสียงได้
  /// เรียกซ้ำได้อย่างปลอดภัย (no-op ถ้าทำงานอยู่แล้ว)
  Future<bool> start() async {
    await initialize();
    if (_isRunning) return true;

    _recorder ??= AudioRecorder();
    final hasPermission = await _recorder!.hasPermission();
    if (!hasPermission) {
      debugPrint('[SirenDetectionService] ไม่ได้รับสิทธิ์ไมโครโฟน (RECORD_AUDIO)');
      return false;
    }

    _isRunning = true;
    _scheduleNextCapture(immediate: true);
    return true;
  }

  /// หยุดการตรวจจับทั้งหมดและคืนทรัพยากรไมโครโฟน (ควรเรียกใน dispose() ของหน้าจอ)
  Future<void> stop() async {
    _isRunning = false;
    _cycleTimer?.cancel();
    _cycleTimer = null;
    _captureSafetyTimer?.cancel();
    _captureSafetyTimer = null;
    await _audioSub?.cancel();
    _audioSub = null;
    if (_isCapturing) {
      try {
        await _recorder?.stop();
      } catch (_) {}
      _isCapturing = false;
    }
    _pcmByteBuffer.clear();
    resultNotifier.value = null;
  }

  void _scheduleNextCapture({bool immediate = false}) {
    if (!_isRunning) return;
    _cycleTimer?.cancel();
    _cycleTimer =
        Timer(immediate ? Duration.zero : captureInterval, _captureOnce);
  }

  Future<void> _captureOnce() async {
    if (!_isRunning || _isCapturing) return;
    _isCapturing = true;
    _pcmByteBuffer.clear();
    try {
      const config = RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: kSampleRate,
        numChannels: 1,
      );
      final stream = await _recorder!.startStream(config);
      _audioSub = stream.listen(
        (chunk) {
          _pcmByteBuffer.addAll(chunk);
          // PCM16 mono = 2 bytes ต่อ 1 sample
          if (_pcmByteBuffer.length >= kClipSamples * 2) {
            _finishCapture();
          }
        },
        onError: (e) {
          debugPrint('[SirenDetectionService] audio stream error: $e');
          _finishCapture();
        },
      );

      // กันไว้เผื่อจับเสียงไม่ครบ 1 วินาทีภายในเวลาอันควร (เช่น hardware ช้า)
      _captureSafetyTimer?.cancel();
      _captureSafetyTimer = Timer(const Duration(milliseconds: 1800), () {
        if (_isCapturing) _finishCapture();
      });
    } catch (e) {
      debugPrint('[SirenDetectionService] เริ่มอัดเสียงไม่สำเร็จ: $e');
      _isCapturing = false;
      _scheduleNextCapture();
    }
  }

  Future<void> _finishCapture() async {
    if (!_isCapturing) return;
    _isCapturing = false;
    _captureSafetyTimer?.cancel();
    _captureSafetyTimer = null;
    await _audioSub?.cancel();
    _audioSub = null;
    try {
      await _recorder?.stop();
    } catch (_) {}

    final bytes = List<int>.from(_pcmByteBuffer);
    _pcmByteBuffer.clear();

    await _processCapturedAudio(bytes);
    _scheduleNextCapture();
  }

  List<double> _pcm16BytesToDoubles(List<int> bytes) {
    final n = bytes.length ~/ 2;
    if (n == 0) return const [];
    final byteData = Uint8List.fromList(bytes).buffer.asByteData();
    final out = List<double>.filled(n, 0.0);
    for (int i = 0; i < n; i++) {
      final sample = byteData.getInt16(i * 2, Endian.little);
      out[i] = sample / 32768.0;
    }
    return out;
  }

  Future<void> _processCapturedAudio(List<int> pcmBytes) async {
    final samples = _pcm16BytesToDoubles(pcmBytes);
    if (samples.isEmpty) return;

    if (!isModelLoaded) {
      resultNotifier.value = SirenDetectionResult(
        status: SirenDetectionStatus.modelUnavailable,
        confidence: null,
        timestamp: DateTime.now(),
      );
      return;
    }

    try {
      final spectrogram = computeLogSpectrogram(samples);

      final input = [
        List.generate(
          kTimeSteps,
          (t) => List.generate(kFreqBins, (f) => [spectrogram[t][f]]),
        ),
      ];
      final output = List.generate(1, (_) => List.filled(1, 0.0));
      _interpreter!.run(input, output);

      final double confidence = output[0][0].clamp(0.0, 1.0);
      resultNotifier.value = SirenDetectionResult(
        status: confidence >= detectionThreshold
            ? SirenDetectionStatus.detected
            : SirenDetectionStatus.notDetected,
        confidence: confidence,
        timestamp: DateTime.now(),
      );
    } catch (e) {
      debugPrint('[SirenDetectionService] inference error: $e');
      // ไม่ปลอมค่า confidence เมื่อรันโมเดลพลาด — รายงานตรงๆ ว่าใช้งานไม่ได้รอบนี้
      resultNotifier.value = SirenDetectionResult(
        status: SirenDetectionStatus.modelUnavailable,
        confidence: null,
        timestamp: DateTime.now(),
      );
    }
  }

  /// คำนวณ log-magnitude spectrogram ขนาดคงที่ [kTimeSteps] x [kFreqBins]
  /// จากคลื่นเสียงดิบ mono normalized -1.0..1.0
  ///
  /// ขั้นตอน:
  /// 1. Pad/truncate ให้ยาวพอดี [kClipSamples] samples เสมอ
  /// 2. แบ่งเป็นเฟรมทับซ้อน (Hann window, ขนาด [kFftSize], hop [kHopSize])
  /// 3. Real FFT แต่ละเฟรมด้วย package `fftea`
  /// 4. รวม magnitude ของ FFT bins เป็น [kFreqBins] แถบแบบ log-spaced
  ///    (ประมาณ mel scale แบบง่าย ไม่ต้องพึ่ง library เสียง)
  /// 5. บีบอัดด้วย log และ normalize ให้อยู่ในช่วง 0.0-1.0 ต่อคลิป
  static List<List<double>> computeLogSpectrogram(List<double> samples) {
    final padded = List<double>.filled(kClipSamples, 0.0);
    final copyLen = math.min(samples.length, kClipSamples);
    for (int i = 0; i < copyLen; i++) {
      padded[i] = samples[i];
    }

    final fft = FFT(kFftSize);
    final window = _hannWindow(kFftSize);
    final frames = <List<double>>[];

    int offset = 0;
    while (frames.length < kTimeSteps) {
      final frame = Float64List(kFftSize);
      for (int i = 0; i < kFftSize; i++) {
        final idx = offset + i;
        frame[i] = (idx < padded.length ? padded[idx] : 0.0) * window[i];
      }
      final spectrum = fft.realFft(frame);
      final mags = spectrum.magnitudes(); // length == kFftSize
      frames.add(_binToLogFreqBins(mags));
      offset += kHopSize;
    }

    return frames;
  }

  static List<double> _hannWindow(int size) {
    return List<double>.generate(
      size,
      (i) => 0.5 - 0.5 * math.cos(2 * math.pi * i / (size - 1)),
    );
  }

  /// รวม linear-frequency magnitude bins ของ FFT (ครึ่งแรกที่ไม่ซ้ำ, ตัด DC)
  /// เป็น [kFreqBins] แถบแบบ log-spaced แล้วบีบอัด+normalize
  static List<double> _binToLogFreqBins(Float64List linearMags) {
    const int nyquistBins = kFftSize ~/ 2; // ครึ่งที่ไม่ซ้ำสำหรับสัญญาณจริง
    final result = List<double>.filled(kFreqBins, 0.0);

    final maxLog = math.log(nyquistBins.toDouble());
    for (int b = 0; b < kFreqBins; b++) {
      final loEdge = math.exp(maxLog * b / kFreqBins);
      final hiEdge = math.exp(maxLog * (b + 1) / kFreqBins);
      final int lo = loEdge.floor().clamp(1, nyquistBins - 1);
      final int hi = hiEdge.floor().clamp(lo + 1, nyquistBins);
      double sum = 0.0;
      int count = 0;
      for (int k = lo; k < hi; k++) {
        sum += linearMags[k];
        count++;
      }
      result[b] = count > 0 ? sum / count : 0.0;
    }

    // Log compress (dB-like)
    for (int b = 0; b < kFreqBins; b++) {
      result[b] = math.log(result[b] + 1e-6);
    }

    // Normalize 0..1 ต่อคลิป (min-max) กันโมเดลเจอ scale ที่แกว่งมากเกินไป
    double minVal = result.reduce(math.min);
    double maxVal = result.reduce(math.max);
    final range = (maxVal - minVal).abs() < 1e-6 ? 1.0 : (maxVal - minVal);
    for (int b = 0; b < kFreqBins; b++) {
      result[b] = ((result[b] - minVal) / range).clamp(0.0, 1.0);
    }

    return result;
  }

  /// คืนทรัพยากรทั้งหมด (interpreter + recorder) — เรียกตอนแอปปิดจริงๆ เท่านั้น
  /// ปกติแค่เรียก [stop] ตอนออกจากหน้าจอ ไม่ต้อง dispose ทิ้งโมเดลที่โหลดแคชไว้
  Future<void> dispose() async {
    await stop();
    await _recorder?.dispose();
    _recorder = null;
  }
}

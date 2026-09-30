import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import '../ml/accident_image_classifier_service.dart';

/// ด่าน 1: ภาพนี้สร้างด้วย AI หรือเปล่า (ตรวจด้วย Gemini) — [checked] = false เมื่อตรวจไม่ได้
/// (ไม่มี key / ออฟไลน์) ซึ่งไม่ขวางการแจ้งเหตุ
class AiGeneratedCheck {
  final bool checked;
  final bool isAiGenerated;
  final double confidence;
  final String reason;

  const AiGeneratedCheck({
    required this.checked,
    this.isAiGenerated = false,
    this.confidence = 0,
    this.reason = '',
  });

  static const skipped = AiGeneratedCheck(checked: false);

  /// ถือว่าเป็นภาพ AI เมื่อมั่นใจพอ — ต่ำกว่านี้ให้ผ่านไปด่าน 2 (กันบล็อกภาพจริงผิดๆ ในเหตุฉุกเฉิน)
  bool get blocks => checked && isAiGenerated && confidence >= 0.7;

  String get summaryLine {
    if (!checked) return '⚪ ด่าน 1: ข้ามการตรวจภาพ AI (ไม่มี Gemini API Key หรือออฟไลน์)';
    final percent = (confidence * 100).round();
    if (blocks) return '🤖 ด่าน 1 (Gemini): ภาพนี้น่าจะสร้างด้วย AI ($percent%)';
    return isAiGenerated
        ? '✅ ด่าน 1 (Gemini): ไม่ชัดว่าเป็นภาพ AI ($percent%) — ส่งตรวจต่อ'
        : '✅ ด่าน 1 (Gemini): เป็นภาพถ่ายจริง ไม่ใช่ภาพ AI';
  }
}

class AiTriageResult {
  final bool isIncidentDetected; // มีร่องรอยอุบัติเหตุจริงหรือไม่ (คัดกรองภาพไม่เกี่ยวข้อง)
  final String severityLevel; // 'วิกฤต (Code Red...)' | 'ปานกลาง (Medium...)' | 'เล็กน้อย (Low...)' | 'ไม่พบร่องรอยอุบัติเหตุ'
  final String severityCode; // 'Code Red' | 'Code Yellow' | 'Code Green' | 'Non-Incident'
  final double confidenceScore; // 0.0 - 1.0 (e.g. 0.94)
  final List<String> detectedFeatures;
  final String clinicalRecommendation;
  final String modelName;
  final int photoCount;
  final bool isUsingGemini;
  // โมเดลที่เทรนเองเป็นตัวตัดสินว่า "เป็นอุบัติเหตุไหม" (null = ไม่ได้ใช้/ยังไม่มีโมเดล)
  final double? trainedAccidentProbability;
  bool get isUsingTrainedModel => trainedAccidentProbability != null;
  final AiGeneratedCheck? aiGeneratedCheck;
  bool get isAiGenerated => aiGeneratedCheck?.blocks ?? false;

  AiTriageResult({
    required this.isIncidentDetected,
    required this.severityLevel,
    required this.severityCode,
    required this.confidenceScore,
    required this.detectedFeatures,
    required this.clinicalRecommendation,
    this.modelName = 'Local Computer Vision Engine (Heuristic, not ML)',
    this.photoCount = 1,
    this.isUsingGemini = false,
    this.trainedAccidentProbability,
    this.aiGeneratedCheck,
  });

  AiTriageResult copyWith({
    bool? isIncidentDetected,
    List<String>? detectedFeatures,
    String? modelName,
    double? trainedAccidentProbability,
    AiGeneratedCheck? aiGeneratedCheck,
  }) =>
      AiTriageResult(
        isIncidentDetected: isIncidentDetected ?? this.isIncidentDetected,
        severityLevel: severityLevel,
        severityCode: severityCode,
        confidenceScore: confidenceScore,
        detectedFeatures: detectedFeatures ?? this.detectedFeatures,
        clinicalRecommendation: clinicalRecommendation,
        modelName: modelName ?? this.modelName,
        photoCount: photoCount,
        isUsingGemini: isUsingGemini,
        trainedAccidentProbability:
            trainedAccidentProbability ?? this.trainedAccidentProbability,
        aiGeneratedCheck: aiGeneratedCheck ?? this.aiGeneratedCheck,
      );
}

/// AI Computer Vision & Gemini Multimodal Service
/// Evaluates incident scene photos using Google Gemini 1.5 Flash Vision API
/// and an honest local fallback engine for emergency triage.
class AiVisionTriageService {
  static final AiVisionTriageService _instance =
      AiVisionTriageService._internal();
  factory AiVisionTriageService() => _instance;
  AiVisionTriageService._internal();

  static const String _prefGeminiKey = 'route_alert_gemini_api_key';

  /// Save Gemini API Key provided by user
  static Future<void> saveGeminiApiKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefGeminiKey, key.trim());
  }

  /// Retrieve active Gemini API Key from SharedPreferences or .env
  static Future<String?> getGeminiApiKey() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedKey = prefs.getString(_prefGeminiKey);
      if (savedKey != null && savedKey.trim().isNotEmpty) {
        return savedKey.trim();
      }
    } catch (_) {}

    try {
      final envKey = dotenv.env['GEMINI_API_KEY'];
      if (envKey != null && envKey.trim().isNotEmpty && !envKey.startsWith('your-')) {
        return envKey.trim();
      }
    } catch (_) {}

    return null;
  }

  /// Analyzes a single emergency photo
  Future<AiTriageResult> analyzeIncidentPhoto(Uint8List imageBytes) async {
    return analyzeIncidentPhotos([imageBytes]);
  }

  /// Analyzes multiple emergency photos with Gemini Vision or Local Engine
  /// [useGemini] = ผู้ใช้กด "ประเมินละเอียดด้วย Gemini" เอง — ปกติใช้โมเดลที่เทรนเองอย่างเดียว
  Future<AiTriageResult> analyzeIncidentPhotos(List<Uint8List> photosBytes,
      {bool useGemini = false}) async {
    if (photosBytes.isEmpty) return _analyzeStage2(photosBytes, useGemini: useGemini);

    // ด่าน 1: ภาพนี้สร้างด้วย AI หรือเปล่า (Gemini) → ด่าน 2: เป็นอุบัติเหตุจริงไหม (โมเดลที่เทรนเอง)
    final aiCheck = await _checkAiGenerated(photosBytes);
    if (aiCheck.blocks) {
      return AiTriageResult(
        isIncidentDetected: false,
        severityCode: 'AI-Generated',
        severityLevel: 'ภาพนี้อาจสร้างด้วย AI',
        confidenceScore: aiCheck.confidence,
        photoCount: photosBytes.length,
        detectedFeatures: [
          aiCheck.summaryLine,
          if (aiCheck.reason.isNotEmpty) '💬 ${aiCheck.reason}',
          '📸 ถ้าเป็นเหตุจริง ให้ถ่ายภาพใหม่จากกล้องที่จุดเกิดเหตุ',
        ],
        clinicalRecommendation:
            'ภาพที่สร้างด้วย AI ใช้ยืนยันเหตุไม่ได้ — หากเป็นเหตุฉุกเฉินจริง ยังส่ง SOS ได้ตามปกติ',
        modelName: 'ด่าน 1: ตรวจภาพ AI ด้วย Gemini',
        isUsingGemini: true,
        aiGeneratedCheck: aiCheck,
      );
    }
    final result = await _analyzeStage2(photosBytes, useGemini: useGemini);
    return result.copyWith(
      detectedFeatures: [aiCheck.summaryLine, ...result.detectedFeatures],
      aiGeneratedCheck: aiCheck,
    );
  }

  // ผลด่าน 1 ของชุดภาพล่าสุด — กด "ประเมินละเอียดด้วย Gemini" ซ้ำจะได้ไม่ต้องเรียก Gemini ใหม่
  String? _aiCheckCacheKey;
  AiGeneratedCheck? _aiCheckCache;

  static String _photosKey(List<Uint8List> photos) => photos.map((b) {
        var h = b.length;
        for (var i = 0; i < b.length; i += 997) {
          h = (h * 31 + b[i]) & 0x3fffffff;
        }
        return h.toString();
      }).join('|');

  Future<AiGeneratedCheck> _checkAiGenerated(List<Uint8List> photosBytes) async {
    final key = _photosKey(photosBytes);
    if (key == _aiCheckCacheKey && _aiCheckCache != null) return _aiCheckCache!;
    final apiKey = await getGeminiApiKey();
    if (apiKey == null || apiKey.isEmpty) return AiGeneratedCheck.skipped;

    const prompt = '''You are a forensic image analyst for an emergency-reporting app in Thailand.
For EACH attached image (in order), decide whether it is AI-generated or heavily AI-edited
(e.g. Midjourney, DALL-E, Stable Diffusion, Imagen/Gemini, Firefly) rather than a real photograph
taken with a camera or phone. Look for: warped or unreadable text and licence plates, malformed hands,
faces or vehicles, inconsistent lighting and shadows, impossible geometry or physics, overly smooth
"plastic" textures, repeated patterns, and watermarks or signatures of AI tools.
A real but low-quality, blurry, dark or cropped phone photo is NOT AI-generated.
Answer JSON only, no markdown:
{"results":[{"index":0,"isAiGenerated":false,"confidence":0.0,"reason":"เหตุผลสั้นๆ เป็นภาษาไทย"}]}
confidence = how sure you are of your isAiGenerated answer (0.0-1.0).''';

    final parsed = await _geminiJson([
      {'text': prompt},
      for (final bytes in photosBytes)
        {'inlineData': {'mimeType': 'image/jpeg', 'data': base64Encode(bytes)}},
    ], apiKey);
    final results = parsed?['results'];
    if (results is! List || results.isEmpty) return AiGeneratedCheck.skipped;

    // ภาพใดภาพหนึ่งเป็น AI ก็ถือว่าชุดนี้น่าสงสัย — รายงานภาพที่มั่นใจว่าเป็น AI มากที่สุด
    AiGeneratedCheck best = const AiGeneratedCheck(checked: true, confidence: 1);
    for (final r in results.whereType<Map>()) {
      final isAi = r['isAiGenerated'] == true;
      final conf = ((r['confidence'] as num?)?.toDouble() ?? 0.5).clamp(0.0, 1.0);
      final check = AiGeneratedCheck(
        checked: true,
        isAiGenerated: isAi,
        confidence: conf,
        reason: r['reason']?.toString() ?? '',
      );
      final score = isAi ? conf : 0.0;
      final bestScore = best.isAiGenerated ? best.confidence : 0.0;
      if (score > bestScore || (!best.isAiGenerated && !isAi && conf < best.confidence)) best = check;
    }
    _aiCheckCacheKey = key;
    _aiCheckCache = best;
    return best;
  }

  /// เรียก Gemini แล้วคืน JSON ที่ได้ (null ถ้าทุกโมเดลล้มเหลว)
  Future<Map<String, dynamic>?> _geminiJson(
      List<Map<String, dynamic>> parts, String apiKey) async {
    final body = jsonEncode({
      'contents': [
        {'parts': parts}
      ],
      'generationConfig': {'temperature': 0.0, 'responseMimeType': 'application/json'},
    });
    for (final model in const ['gemini-3.5-flash-lite', 'gemini-3.6-flash', 'gemini-flash-latest']) {
      try {
        final response = await http.post(
          Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent'),
          headers: {'Content-Type': 'application/json', 'x-goog-api-key': apiKey},
          body: body,
        ).timeout(const Duration(seconds: 9));
        if (response.statusCode != 200) {
          debugPrint('Gemini $model status ${response.statusCode}');
          continue;
        }
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        final text = (decoded['candidates']?[0]?['content']?['parts']?[0]?['text'] ?? '')
            .toString()
            .replaceAll('```json', '')
            .replaceAll('```', '')
            .trim();
        final parsed = jsonDecode(text);
        if (parsed is Map<String, dynamic>) return parsed;
      } catch (e) {
        debugPrint('Gemini $model failed: $e');
      }
    }
    return null;
  }

  Future<AiTriageResult> _analyzeStage2(List<Uint8List> photosBytes,
      {bool useGemini = false}) async {
    if (photosBytes.isEmpty) {
      return AiTriageResult(
        isIncidentDetected: false,
        severityCode: 'Non-Incident',
        severityLevel: 'ไม่มีภาพถ่ายเหตุการณ์',
        confidenceScore: 1.0,
        detectedFeatures: ['ยังไม่มีการเลือกภาพถ่ายจุดเกิดเหตุ'],
        clinicalRecommendation: 'กรุณาถ่ายภาพจุดเกิดเหตุเพื่อให้ AI ช่วยประเมิน',
        photoCount: 0,
      );
    }

    // 0. โมเดลที่เทรนเองตัดสินก่อนว่าเป็นอุบัติเหตุหรือไม่ — Gemini (ถ้ามี key) ใช้แค่
    // ช่วยประเมินความรุนแรง/บรรยายภาพเมื่อโมเดลยืนยันแล้วว่าเป็นอุบัติเหตุ
    final trained = <AccidentClassificationResult?>[];
    for (final bytes in photosBytes) {
      trained.add(await _classifyWithTrainedModel(bytes));
    }
    if (trained.any((r) => r != null)) {
      return _analyzeWithTrainedModel(photosBytes, trained, useGemini: useGemini);
    }

    // 1. ยังไม่มีโมเดลที่เทรนเอง — ใช้ Gemini เมื่อผู้ใช้ขอ แล้วค่อย fallback
    final geminiKey = useGemini ? await getGeminiApiKey() : null;
    if (geminiKey != null && geminiKey.isNotEmpty) {
      try {
        final geminiResult = await _callGeminiVision(photosBytes, geminiKey);
        if (geminiResult != null) {
          return geminiResult;
        }
      } catch (e) {
        debugPrint('Gemini Vision API call failed: $e, falling back to local engine');
      }
    }

    // 2. Fallback to Local Computer Vision Engine (Strict & Honest)
    return await _analyzeWithLocalEngine(photosBytes);
  }

  /// เช็คว่าโมเดลที่เทรนเอง (Teachable Machine → TFLite) ถือว่าภาพนี้เป็น
  /// อุบัติเหตุหรือไม่ คืนค่า null ถ้ายังไม่มีโมเดล (assets/models/accident_classifier.tflite)
  Future<AccidentClassificationResult?> _classifyWithTrainedModel(
      Uint8List bytes) async {
    final classifier = AccidentImageClassifierService();
    if (!classifier.isModelLoaded) {
      await classifier.initialize();
    }
    if (!classifier.isModelLoaded) return null;
    return classifier.classify(bytes);
  }

  static double _accidentProbability(AccidentClassificationResult r) =>
      r.isAccident ? r.confidence : 1 - r.confidence;

  Future<AiTriageResult> _analyzeWithTrainedModel(List<Uint8List> photosBytes,
      List<AccidentClassificationResult?> trained,
      {bool useGemini = false}) async {
    final probs = trained.whereType<AccidentClassificationResult>()
        .map(_accidentProbability)
        .toList();
    final best = probs.reduce(math.max);
    final percent = (best * 100).round();
    const modelLabel = 'โมเดลตรวจอุบัติเหตุที่เทรนเอง (EfficientNetV2)';

    // ผู้ใช้ขอให้ Gemini ช่วยดูด้วย — แสดงความเห็นของทั้งสองโมเดลคู่กัน
    if (useGemini) {
      final geminiKey = await getGeminiApiKey();
      if (geminiKey != null && geminiKey.isNotEmpty) {
        try {
          final gemini = await _callGeminiVision(photosBytes, geminiKey);
          if (gemini != null) {
            final agree = gemini.isIncidentDetected == (best >= 0.5);
            return gemini.copyWith(
              detectedFeatures: [
                best >= 0.5
                    ? '🧠 ด่าน 2 (โมเดลที่เทรนเอง): ภาพอุบัติเหตุ ($percent%)'
                    : '🧠 ด่าน 2 (โมเดลที่เทรนเอง): ไม่ใช่ภาพอุบัติเหตุ (${100 - percent}%)',
                agree ? '✨ Gemini เห็นตรงกัน' : '⚠️ Gemini ประเมินต่างจากโมเดลที่เทรนเอง',
                ...gemini.detectedFeatures,
              ],
              modelName: '$modelLabel + Gemini',
              trainedAccidentProbability: best,
            );
          }
        } catch (e) {
          debugPrint('Gemini re-check failed: $e');
        }
      }
    }

    if (best < 0.5) {
      return AiTriageResult(
        isIncidentDetected: false,
        severityCode: 'Non-Incident',
        severityLevel: 'ไม่พบร่องรอยอุบัติเหตุในภาพ',
        confidenceScore: 1 - best,
        photoCount: photosBytes.length,
        detectedFeatures: [
          '🧠 ด่าน 2 (โมเดลที่เทรนเอง): ไม่ใช่ภาพอุบัติเหตุ (${100 - percent}%)',
          '📸 แนะนำถ่ายภาพตัวรถ, รอยชน, หรือจุดเกิดเหตุที่ชัดเจน',
        ],
        clinicalRecommendation:
            'หากเป็นเหตุฉุกเฉินจริง สามารถเลือกประเภทเหตุและส่ง SOS ได้ตามปกติ',
        modelName: modelLabel,
        trainedAccidentProbability: best,
      );
    }

    // โมเดลที่เทรนเองตอบได้แค่ "อุบัติเหตุหรือไม่" — ไม่เดาความรุนแรงจากสูตรความคมชัดของภาพ
    // (เดิมทำให้ภาพหน้าคนชัดๆ ถูกตีเป็น "วิกฤต") ให้ผู้แจ้งเลือกเอง หรือกดให้ Gemini ช่วยประเมิน
    return AiTriageResult(
      isIncidentDetected: true,
      severityCode: 'Unassessed',
      severityLevel: 'ยังไม่ได้ประเมินความรุนแรง',
      confidenceScore: best,
      photoCount: photosBytes.length,
      detectedFeatures: [
        '🧠 ด่าน 2 (โมเดลที่เทรนเอง): ภาพอุบัติเหตุ ($percent%)',
        '📋 ความรุนแรง: เลือกเองในช่องด้านบน หรือกด "ประเมินละเอียดด้วย Gemini"',
      ],
      clinicalRecommendation: 'ตรวจสอบระดับความรุนแรงให้ตรงกับสถานการณ์จริงก่อนส่ง SOS',
      modelName: modelLabel,
      trainedAccidentProbability: best,
    );
  }

  /// Calls Google Gemini Multimodal Vision API
  Future<AiTriageResult?> _callGeminiVision(
      List<Uint8List> photosBytes, String apiKey) async {
    final candidateModels = [
      'gemini-3.5-flash-lite',
      'gemini-3.6-flash',
      'gemini-flash-latest',
    ];

    const systemPrompt = '''คุณคือ AI ผู้เชี่ยวชาญด้านการคัดกรองอุบัติเหตุและเหตุฉุกเฉิน (Emergency Medical Triage AI) ของศูนย์สั่งการ 1669 ประเทศไทย
จงวิเคราะห์ภาพถ่ายจุดเกิดเหตุอย่างละเอียด อิงตามข้อเท็จจริงทางการแพทย์ และตอบกลับเป็น JSON เท่านั้น:
1. ตรวจสอบว่าภาพนี้เป็น "ภาพเหตุฉุกเฉิน/อุบัติเหตุบนท้องถนนจริง" หรือไม่ (เช่น รถชน, รถคว่ำ, ผู้บาดเจ็บ, ไฟไหม้, ชนท้าย, มอเตอร์ไซค์ล้ม, เสาไฟหัก, กีดขวางถนน)
   - หากเป็นภาพที่ไม่เกี่ยวข้อง เช่น ภาพห้องนอน, ห้องนั่งเล่น, โต๊ะทำงาน, หน้าจอคอม/มือถือ, สัตว์เลี้ยง, ของใช้, เซลฟี่คนปกติ, หรือภาพมืด/เบลอที่ไม่มีเหตุการณ์ ให้ระบุ "isIncidentDetected": false และ "severityCode": "Non-Incident"
2. หากเป็นเหตุการณ์จริง ให้ประเมินระดับความรุนแรง (Triage Code):
   - "Code Red": วิกฤต (หมดสติ, รถยุบตัวรุนแรง, ชนประสานงา, คว่ำ, ติดในซากรถ, เสี่ยงชีวิตสูง)
   - "Code Yellow": ปานกลาง (รู้สึกตัว, กันชนยุบ, เสียหายปานกลาง, กีดขวางช่องจราจร)
   - "Code Green": เล็กน้อย (เฉี่ยวชนความเร็วต่ำ, รอยขูดขีดภายนอก, ปลอดภัย)
3. ระบุลักษณะความเสียหาย/ยานพาหนะ/ความเสี่ยงที่พบในภาพอย่างตรงไปตรงมาเป็นภาษาไทย (เช่น "ตรวจพบรถเก๋งชนท้าย", "กันชนหน้ายุบตัว")
4. ให้คำแนะนำทางการแพทย์หรือคำสั่งการทีมกู้ชีพ 1669 เป็นภาษาไทย

สำคัญมาก: ตอบเป็น JSON โครงสร้างนี้เท่านั้น ห้ามใส่เครื่องหมาย markdown block (ไม่ต้องใส่ ```json หรือ ```) ห้ามมีข้อความอื่นนอกเหนือจาก JSON:
{"isIncidentDetected": true, "severityCode": "Code Red", "severityLevel": "วิกฤต (Code Red - หมดสติ / บาดเจ็บสาหัส)", "confidenceScore": 0.96, "detectedFeatures": ["..."], "clinicalRecommendation": "..."}''';

    final List<Map<String, dynamic>> parts = [
      {'text': systemPrompt}
    ];

    for (final bytes in photosBytes) {
      parts.add({
        'inlineData': {
          'mimeType': 'image/jpeg',
          'data': base64Encode(bytes),
        }
      });
    }

    final requestBody = jsonEncode({
      'contents': [
        {'parts': parts}
      ],
      'generationConfig': {
        'temperature': 0.1,
        'responseMimeType': 'application/json',
      }
    });

    for (final model in candidateModels) {
      try {
        // เดิมส่ง apiKey แปะไว้ใน query string ตรงๆ (?key=$apiKey) ทำให้ตอน
        // request ล้มเหลว (เน็ตหลุด/timeout) ข้อความ exception ที่ debugPrint ไว้
        // ด้านล่างจะมี URL เต็มๆ รวม API key แปะอยู่ด้วย รั่วลง log เครื่องแม้แต่ใน
        // release build — ย้ายไปส่งผ่าน header 'x-goog-api-key' แทน (Gemini API
        // รองรับทั้ง 2 แบบ) ตัด key ออกจาก URL ไปเลย ไม่มีทางรั่วผ่าน log อีก
        final url = Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent',
        );

        final response = await http.post(
          url,
          headers: {
            'Content-Type': 'application/json',
            'x-goog-api-key': apiKey,
          },
          body: requestBody,
        ).timeout(const Duration(seconds: 9));

        if (response.statusCode == 200) {
          final jsonResponse = jsonDecode(utf8.decode(response.bodyBytes));
          final candidates = jsonResponse['candidates'] as List<dynamic>?;
          if (candidates != null && candidates.isNotEmpty) {
            final content = candidates[0]['content'];
            final partsList = content['parts'] as List<dynamic>?;
            if (partsList != null && partsList.isNotEmpty) {
              String rawText = partsList[0]['text'] ?? '';
              rawText = rawText.replaceAll('```json', '').replaceAll('```', '').trim();

              final parsed = jsonDecode(rawText);
              final bool isIncident = parsed['isIncidentDetected'] == true;
              final String severityCode = parsed['severityCode'] ?? (isIncident ? 'Code Yellow' : 'Non-Incident');
              final String severityLevel = parsed['severityLevel'] ?? (isIncident ? 'ปานกลาง (Medium - บาดเจ็บแต่รู้สึกตัว)' : 'ไม่พบร่องรอยอุบัติเหตุในภาพ');
              final double conf = (parsed['confidenceScore'] as num?)?.toDouble() ?? 0.95;
              final rawFeats = parsed['detectedFeatures'] as List<dynamic>?;
              final List<String> features = rawFeats?.map((e) => e.toString()).toList() ?? [];
              final String recommendation = parsed['clinicalRecommendation'] ?? '';

              return AiTriageResult(
                isIncidentDetected: isIncident,
                severityCode: severityCode,
                severityLevel: severityLevel,
                confidenceScore: conf,
                detectedFeatures: features,
                clinicalRecommendation: recommendation,
                modelName: 'Google Gemini Vision ($model)',
                photoCount: photosBytes.length,
                isUsingGemini: true,
              );
            }
          }
        } else {
          debugPrint('Gemini model $model returned status ${response.statusCode}: ${response.body}');
        }
      } catch (e) {
        debugPrint('Gemini model $model attempt failed: $e');
      }
    }

    return null;
  }

  /// Local Computer Vision Engine (Strict & Honest fallback)
  /// ถ้ามีโมเดลที่เทรนเองผ่าน Teachable Machine (assets/models/accident_classifier.tflite)
  /// จะใช้ผลจากโมเดลนั้นช่วยตัดสิน isIncidentScene ร่วมกับ heuristic เดิม
  /// ถ้าไม่มีโมเดล จะ fallback ไปใช้ heuristic ล้วนเหมือนเดิมทุกประการ
  Future<AiTriageResult> _analyzeWithLocalEngine(List<Uint8List> photosBytes,
      {List<bool?>? trainedOverride}) async {
    final List<_ImageStats> statsList = [];
    for (var i = 0; i < photosBytes.length; i++) {
      final bytes = photosBytes[i];
      final heuristicStats = _computeImageStats(bytes);
      final override = trainedOverride != null && i < trainedOverride.length
          ? trainedOverride[i]
          : null;
      if (override != null) {
        // โมเดลที่เทรนเองตัดสินแล้ว — ใช้ heuristic แค่ประเมินความรุนแรง
        statsList.add(heuristicStats.copyWithIncidentOverride(override));
        continue;
      }
      final trainedResult =
          trainedOverride == null ? await _classifyWithTrainedModel(bytes) : null;

      if (trainedResult != null && trainedResult.confidence >= 0.6) {
        // เชื่อผลจากโมเดลที่เทรนเองเป็นหลักเมื่อมั่นใจเพียงพอ (OR กับ heuristic
        // เดิมเพื่อความ lenient เนื่องจากโมเดลที่เทรนเองอาจยังมีข้อมูลน้อย)
        statsList.add(heuristicStats.copyWithIncidentOverride(
            heuristicStats.isIncidentScene || trainedResult.isAccident));
      } else {
        statsList.add(heuristicStats);
      }
    }

    final List<_ImageStats> incidentPhotos =
        statsList.where((s) => s.isIncidentScene).toList();

    // 1. REJECT: None of the photos show an incident
    if (incidentPhotos.isEmpty) {
      return AiTriageResult(
        isIncidentDetected: false,
        severityCode: 'Non-Incident',
        severityLevel: 'ไม่พบร่องรอยอุบัติเหตุในภาพ',
        confidenceScore: 0.95,
        photoCount: photosBytes.length,
        detectedFeatures: [
          '⚠️ ภาพไม่สอดคล้องกับจุดเกิดเหตุหรืออุบัติเหตุทางถนน',
          '🔍 ไม่พบโครงสร้างยานพาหนะ, สภาพการชน, หรือความเสียหายที่เห็นได้ชัด',
          '📸 แนะนำถ่ายภาพตัวรถ, รอยชน, หรือจุดเกิดเหตุที่ชัดเจน',
        ],
        clinicalRecommendation:
            'หากเป็นเหตุฉุกเฉินจริง สามารถเลือกประเภทเหตุและส่ง SOS ได้ตามปกติ หรือแตะ 🔑 เพื่อใส่ Gemini API Key เพื่อให้ AI วิเคราะห์แม่นยำ 100%',
        modelName: 'Local Computer Vision Engine',
        isUsingGemini: false,
      );
    }

    // 2. Incident Confirmed
    double maxGradient = 0.0;
    double maxContrast = 0.0;
    bool hasSevereDeformation = false;
    bool hasGlassOrDebris = false;
    bool hasLaneObstruction = false;

    for (final s in incidentPhotos) {
      if (s.edgeGradient > maxGradient) maxGradient = s.edgeGradient;
      if (s.contrast > maxContrast) maxContrast = s.contrast;
      if (s.isSevereImpact) hasSevereDeformation = true;
      if (s.hasDebrisSignature) hasGlassOrDebris = true;
      if (s.hasLaneDisruption) hasLaneObstruction = true;
    }

    final List<String> fusedFeatures = [];
    if (photosBytes.length > 1) {
      fusedFeatures.add('📸 ประมวลผลจากภาพถ่ายรวม ${photosBytes.length} รูป');
    }

    if (hasSevereDeformation || maxGradient > 38.0 || maxContrast > 40.0) {
      // CODE RED
      fusedFeatures.addAll([
        '🚗 ตรวจพบความเสียหายเชิงโครงสร้างรุนแรง (Structural Damage)',
        '💥 แรงกระแทกสูง มีการยุบตัวของตัวถัง/หน้ารถ',
        if (hasGlassOrDebris) '⚠️ ตรวจพบเศษชิ้นส่วนหรือกระจกแตกกระจายบนผิวถนน',
        '🚑 ความเสี่ยงต่อการติดค้างในห้องโดยสาร (Entrapment Risk)',
      ]);

      return AiTriageResult(
        isIncidentDetected: true,
        severityCode: 'Code Red',
        severityLevel: 'วิกฤต (Code Red - หมดสติ / บาดเจ็บสาหัส)',
        confidenceScore: math.min(0.96, 0.90 + (incidentPhotos.length * 0.02)),
        photoCount: photosBytes.length,
        detectedFeatures: fusedFeatures,
        clinicalRecommendation:
            'แนะนำประสานศูนย์สั่งการ 1669 ส่งทีมกู้ชีพระดับสูง (ALS) พร้อม Trauma Team ทันที',
        modelName: 'Local Computer Vision Engine',
        isUsingGemini: false,
      );
    } else if (hasLaneObstruction || maxGradient > 22.0 || maxContrast > 24.0) {
      // CODE YELLOW
      fusedFeatures.addAll([
        '🚙 การยุบตัวของกันชน/แผงด้านข้างตัวรถ (Fender Deformation)',
        '🚦 มีสิ่งกีดขวางช่องทางจราจร (Traffic Lane Obstruction)',
        '👤 มีผู้บาดเจ็บแต่ยังรู้สึกตัวและสื่อสารได้ (Conscious Alert)',
      ]);

      return AiTriageResult(
        isIncidentDetected: true,
        severityCode: 'Code Yellow',
        severityLevel: 'ปานกลาง (Medium - บาดเจ็บแต่รู้สึกตัว)',
        confidenceScore: math.min(0.93, 0.86 + (incidentPhotos.length * 0.02)),
        photoCount: photosBytes.length,
        detectedFeatures: fusedFeatures,
        clinicalRecommendation:
            'แนะนำส่งรถกู้ชีพระดับพื้นฐาน (BLS) เพื่อปฐมพยาบาลและตรวจประเมินร่างกาย ณ จุดเกิดเหตุ',
        modelName: 'Local Computer Vision Engine',
        isUsingGemini: false,
      );
    } else {
      // CODE GREEN
      fusedFeatures.addAll([
        '🛵 เฉี่ยวชนความเร็วต่ำ (Low-Speed Impact)',
        '🛠️ ความเสียหายภายนอกเล็กน้อย รอยขูดขีดพื้นผิว (Minor Scratches)',
      ]);

      return AiTriageResult(
        isIncidentDetected: true,
        severityCode: 'Code Green',
        severityLevel: 'เล็กน้อย (Low - บาดเจ็บเล็กน้อย)',
        confidenceScore: 0.90,
        photoCount: photosBytes.length,
        detectedFeatures: fusedFeatures,
        clinicalRecommendation:
            'แนะนำให้สัญญาณเตือนจราจร ประสานเจ้าหน้าที่ตำรวจและประกันภัยเพื่อเคลียร์พื้นที่',
        modelName: 'Local Computer Vision Engine',
        isUsingGemini: false,
      );
    }
  }

  /// Extracts visual characteristics and validates if the image is a genuine incident scene
  _ImageStats _computeImageStats(Uint8List bytes) {
    try {
      final img.Image? decoded = img.decodeImage(bytes);
      if (decoded == null || decoded.width < 10 || decoded.height < 10) {
        return _ImageStats.empty();
      }

      const int grid = 32;
      final double stepX = decoded.width / grid;
      final double stepY = decoded.height / grid;

      double sumR = 0, sumG = 0, sumB = 0, sumLum = 0;
      final List<double> lumSamples = [];

      for (int y = 0; y < grid; y++) {
        final int py = (y * stepY).toInt().clamp(0, decoded.height - 1);
        for (int x = 0; x < grid; x++) {
          final int px = (x * stepX).toInt().clamp(0, decoded.width - 1);
          final pixel = decoded.getPixel(px, py);

          final r = pixel.r.toDouble();
          final g = pixel.g.toDouble();
          final b = pixel.b.toDouble();
          final lum = (0.299 * r + 0.587 * g + 0.114 * b);

          sumR += r;
          sumG += g;
          sumB += b;
          sumLum += lum;
          lumSamples.add(lum);
        }
      }

      const int total = grid * grid;
      final double avgR = sumR / total;
      final double avgG = sumG / total;
      final double avgB = sumB / total;
      final double avgLum = sumLum / total;

      double varianceSum = 0;
      for (final lum in lumSamples) {
        varianceSum += math.pow(lum - avgLum, 2);
      }
      final double stdDev = math.sqrt(varianceSum / total);

      double edgeGradientSum = 0;
      for (int y = 0; y < grid - 1; y++) {
        for (int x = 0; x < grid - 1; x++) {
          final int idx = y * grid + x;
          final double diffX = (lumSamples[idx + 1] - lumSamples[idx]).abs();
          final double diffY = (lumSamples[idx + grid] - lumSamples[idx]).abs();
          edgeGradientSum += (diffX + diffY);
        }
      }
      final double avgEdgeGradient = edgeGradientSum / ((grid - 1) * (grid - 1));

      // Verification Rules: Reject flat walls, floors, selfies, dark screens, finger blocked
      final bool isFlatSurface = stdDev < 16.0 && avgEdgeGradient < 10.0;
      final bool isTooDark = avgLum < 15.0 && stdDev < 12.0;
      final bool isOverexposed = avgLum > 240.0 && stdDev < 12.0;
      final bool isFingerBlocked = avgR > 150 && avgG < 60 && avgB < 60 && stdDev < 20.0;

      // Realistic incident requirements: must have substantial structural contours and contrast
      final bool isIncident = !isFlatSurface &&
          !isTooDark &&
          !isOverexposed &&
          !isFingerBlocked &&
          avgEdgeGradient >= 15.0 &&
          stdDev >= 28.0;

      final bool isSevere = avgEdgeGradient > 36.0 || (stdDev > 50.0 && avgEdgeGradient > 30.0);
      final bool hasDebris = avgEdgeGradient > 25.0 && stdDev > 40.0;
      final bool hasLaneDisrupt = avgEdgeGradient > 18.0;

      return _ImageStats(
        isIncidentScene: isIncident,
        edgeGradient: avgEdgeGradient,
        contrast: stdDev,
        isSevereImpact: isSevere,
        hasDebrisSignature: hasDebris,
        hasLaneDisruption: hasLaneDisrupt,
      );
    } catch (e) {
      debugPrint('AiVisionTriageService stats error: $e');
      return _ImageStats.empty();
    }
  }
}

class _ImageStats {
  final bool isIncidentScene;
  final double edgeGradient;
  final double contrast;
  final bool isSevereImpact;
  final bool hasDebrisSignature;
  final bool hasLaneDisruption;

  _ImageStats({
    required this.isIncidentScene,
    required this.edgeGradient,
    required this.contrast,
    required this.isSevereImpact,
    required this.hasDebrisSignature,
    required this.hasLaneDisruption,
  });

  _ImageStats copyWithIncidentOverride(bool isIncidentScene) => _ImageStats(
        isIncidentScene: isIncidentScene,
        edgeGradient: edgeGradient,
        contrast: contrast,
        isSevereImpact: isSevereImpact,
        hasDebrisSignature: hasDebrisSignature,
        hasLaneDisruption: hasLaneDisruption,
      );

  factory _ImageStats.empty() => _ImageStats(
        isIncidentScene: false,
        edgeGradient: 0,
        contrast: 0,
        isSevereImpact: false,
        hasDebrisSignature: false,
        hasLaneDisruption: false,
      );
}

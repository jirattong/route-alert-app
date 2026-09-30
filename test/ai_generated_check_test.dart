import 'package:flutter_test/flutter_test.dart';
import 'package:route_alert/core/services/ai_vision_triage_service.dart';

void main() {
  test('stage 1 blocks only confident AI-generated verdicts', () {
    expect(const AiGeneratedCheck(checked: true, isAiGenerated: true, confidence: 0.9).blocks, isTrue);
    expect(const AiGeneratedCheck(checked: true, isAiGenerated: true, confidence: 0.6).blocks, isFalse);
    expect(const AiGeneratedCheck(checked: true, isAiGenerated: false, confidence: 0.99).blocks, isFalse);
    expect(AiGeneratedCheck.skipped.blocks, isFalse);
  });

  test('summary line tells the user what stage 1 did', () {
    expect(AiGeneratedCheck.skipped.summaryLine, contains('ข้ามการตรวจภาพ AI'));
    expect(const AiGeneratedCheck(checked: true, isAiGenerated: true, confidence: 0.92).summaryLine,
        contains('น่าจะสร้างด้วย AI (92%)'));
    expect(const AiGeneratedCheck(checked: true, confidence: 0.9).summaryLine, contains('ภาพถ่ายจริง'));
  });

  test('result exposes the AI-generated flag through copyWith', () {
    final r = AiTriageResult(
      isIncidentDetected: true,
      severityLevel: 'x',
      severityCode: 'Unassessed',
      confidenceScore: 0.9,
      detectedFeatures: const [],
      clinicalRecommendation: '',
    );
    expect(r.isAiGenerated, isFalse);
    final flagged = r.copyWith(
        aiGeneratedCheck: const AiGeneratedCheck(checked: true, isAiGenerated: true, confidence: 0.8));
    expect(flagged.isAiGenerated, isTrue);
  });
}

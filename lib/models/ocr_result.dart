// lib/models/ocr_result.dart  (UPDATED — replaces your existing file)

import 'prescription_result.dart';

class OcrBlock {
  final String text;
  final double confidence;
  final int left;
  final int top;
  final int width;
  final int height;

  OcrBlock({
    required this.text,
    required this.confidence,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  @override
  String toString() => 'OcrBlock("$text", conf: $confidence)';
}

class OcrResult {
  final String rawText;
  final List<OcrBlock> blocks;
  final double imageQualityScore;
  final int processingMs;
  final String? warningMessage;

  // Layer 2 output
  final PrescriptionResult? prescriptionResult;
  final String? aiError;

  OcrResult({
    required this.rawText,
    required this.blocks,
    required this.imageQualityScore,
    required this.processingMs,
    this.warningMessage,
    this.prescriptionResult,
    this.aiError,
  });

  bool get isUsable =>
      imageQualityScore > 0.3 && rawText.trim().isNotEmpty;
  bool get hasAiResult => prescriptionResult != null;
}
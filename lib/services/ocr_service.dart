// lib/services/ocr_service.dart
// FIXED: Removed Devanagari recognizer — ML Kit Devanagari model is not
// bundled by default and throws ClassNotFoundException at runtime on Android.
// Latin script handles printed English medicine names well enough.

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import '../models/ocr_result.dart';
import '../models/prescription_result.dart';
import 'image_preprocessor.dart';
import 'ai_interpretation_service.dart';

class OcrService {
  // Latin only — covers all printed English/Roman-script prescriptions.
  // Devanagari requires a separately downloaded ML Kit model that is NOT
  // included in the default google_mlkit_text_recognition package on Android.
  final _recognizer = TextRecognizer(script: TextRecognitionScript.latin);
  final _aiService = AiInterpretationService();

  /// Full pipeline: preprocess → OCR → AI interpretation
  Future<OcrResult> processImage(File rawImageFile) async {
    final stopwatch = Stopwatch()..start();

    // ── Layer 1a: Image preprocessing ────────────────────────────────
    PreprocessResult preprocessed;
    try {
      preprocessed = await ImagePreprocessor.process(rawImageFile);
    } catch (e) {
      debugPrint('Preprocessing failed, using original: $e');
      preprocessed = PreprocessResult(
        processedFile: rawImageFile,
        qualityScore: 0.5,
        warning: 'Image preprocessing failed. Results may be less accurate.',
      );
    }

    // ── Layer 1b: OCR ─────────────────────────────────────────────────
    final inputImage = InputImage.fromFile(preprocessed.processedFile);

    RecognizedText ocrResult;
    try {
      ocrResult = await _recognizer.processImage(inputImage);
    } catch (e) {
      debugPrint('OCR failed: $e');
      stopwatch.stop();
      return OcrResult(
        rawText: '',
        blocks: [],
        imageQualityScore: preprocessed.qualityScore,
        processingMs: stopwatch.elapsedMilliseconds,
        warningMessage: 'OCR failed: $e',
      );
    }

    // ── Build block list ──────────────────────────────────────────────
    final allBlocks = <OcrBlock>[];

    for (final block in ocrResult.blocks) {
      allBlocks.add(OcrBlock(
        text: block.text,
        confidence: _avgConfidence(block),
        left: block.boundingBox.left.round(),
        top: block.boundingBox.top.round(),
        width: block.boundingBox.width.round(),
        height: block.boundingBox.height.round(),
      ));
    }

    // Sort top-to-bottom, left-to-right
    allBlocks.sort((a, b) {
      final rowDiff = a.top - b.top;
      if (rowDiff.abs() > 20) return rowDiff;
      return a.left - b.left;
    });

    final rawText = allBlocks.map((b) => b.text).join('\n');

    // ── Layer 2: AI interpretation ────────────────────────────────────
    PrescriptionResult? prescriptionResult;
    String? aiError;

    if (rawText.trim().isNotEmpty) {
      try {
        prescriptionResult = await _aiService.interpret(rawText);
      } catch (e) {
        aiError = e.toString();
        debugPrint('AI interpretation error: $e');
      }
    } else {
      aiError = 'No text detected in image';
    }

    stopwatch.stop();

    // Clean up temp file
    try {
      if (preprocessed.processedFile.path != rawImageFile.path) {
        await preprocessed.processedFile.delete();
      }
    } catch (_) {}

    return OcrResult(
      rawText: rawText,
      blocks: allBlocks,
      imageQualityScore: preprocessed.qualityScore,
      processingMs: stopwatch.elapsedMilliseconds,
      warningMessage: preprocessed.warning,
      prescriptionResult: prescriptionResult,
      aiError: aiError,
    );
  }

  double _avgConfidence(TextBlock block) {
    if (block.lines.isEmpty) return 0.0;
    double total = 0;
    int count = 0;
    for (final line in block.lines) {
      for (final element in line.elements) {
        total += element.confidence ?? 0.0;
        count++;
      }
    }
    return count > 0 ? total / count : 0.0;
  }

  Future<void> dispose() async {
    await _recognizer.close();
  }
}
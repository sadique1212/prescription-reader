// lib/services/ai_interpretation_service.dart
// Layer 2 — AI Interpretation (Claude API)
// Pipeline: pre-processing → context analysis → fuzzy DB match → abbreviation decode → structured output

import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../models/prescription_result.dart';
import 'medicine_database.dart';

class AiInterpretationService {
  // ── Replace with your actual Anthropic API key ────────────────────────
  // IMPORTANT: In production, load from flutter_dotenv or a secure store.
  static const String _apiKey = 'YOUR_ANTHROPIC_API_KEY';
  static const String _apiUrl = 'https://api.anthropic.com/v1/messages';
  static const String _model = 'claude-opus-4-6'; // or claude-sonnet-4-6

  /// Full Layer 2 pipeline.
  ///
  /// [rawOcrText]  — multi-line raw OCR output from Layer 1.
  /// Returns a [PrescriptionResult] with structured medicines + warnings.
  Future<PrescriptionResult> interpret(String rawOcrText) async {
    // Step 1 — Pre-processing (clean OCR noise, split lines, token list)
    final preprocessed = _preprocess(rawOcrText);

    // Step 2 — Local fuzzy DB pass (fast, offline, catches common medicines)
    final localMatches = _localFuzzyPass(preprocessed.tokenLines);

    // Step 3 — AI context analysis (handles handwriting errors, multi-medicine)
    final aiResult = await _claudeInterpret(
      rawOcrText: rawOcrText,
      preprocessed: preprocessed,
      localHints: localMatches,
    );

    return aiResult;
  }

  // ════════════════════════════════════════════════════════════════════════
  // STAGE 1 — Pre-processing
  // ════════════════════════════════════════════════════════════════════════

  _PreprocessedText _preprocess(String raw) {
    // 1. Normalize Unicode, collapse multiple spaces
    var text = raw
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll(RegExp(r'[ \t]{2,}'), ' ');

    // 2. Strip common OCR noise characters that aren't meaningful
    text = text.replaceAll(RegExp(r'[|\\~`]'), ' ');

    // 3. Fix common OCR character substitutions in medical context
    text = _fixOcrSubstitutions(text);

    // 4. Split into lines, remove empty/noise-only lines
    final rawLines = text.split('\n');
    final lines = rawLines
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty && l.length > 1)
        .toList();

    // 5. Per-line token extraction (preserves dosage patterns)
    final tokenLines = lines.map((line) {
      // Keep alphanumeric, dots, slashes, hyphens (dosage needs them)
      final tokens = line
          .split(RegExp(r'[,;\s]+'))
          .map((t) => t.trim())
          .where((t) => t.isNotEmpty)
          .toList();
      return TokenLine(raw: line, tokens: tokens);
    }).toList();

    return _PreprocessedText(
      cleanedText: lines.join('\n'),
      tokenLines: tokenLines,
    );
  }

  String _fixOcrSubstitutions(String text) {
    // Common handwriting OCR errors in medical context
    return text
    // 0 ↔ O confusion in drug names
        .replaceAllMapped(RegExp(r'\b0(\w{3,})'), (m) => 'O${m[1]}')
    // l ↔ 1 at start of word
        .replaceAllMapped(RegExp(r'\b1([a-z]{2,})'), (m) => 'l${m[1]}')
    // 5 → S in drug names (Salbuta5ol → Salbutamol won't help but prevents noise)
    // Common prefix repairs
        .replaceAll('Arnox', 'Amox')
        .replaceAll('Paracetarno', 'Paracetamo')
        .replaceAll('Pnocd', 'Pnocd') // keep as-is, AI handles it
    // Fix split numbers: "5 00mg" → "500mg"
        .replaceAllMapped(
      RegExp(r'(\d)\s+(\d{2,3})\s*mg', caseSensitive: false),
          (m) => '${m[1]}${m[2]}mg',
    )
    // Normalize dose formats: "500Mg" → "500mg"
        .replaceAllMapped(
      RegExp(r'(\d+)\s*(mg|mcg|ml|g|iu)\b', caseSensitive: false),
          (m) => '${m[1]}${m[2]!.toLowerCase()}',
    );
  }

  // ════════════════════════════════════════════════════════════════════════
  // STAGE 2 — Local Fuzzy DB pass (offline, fast hints for AI)
  // ════════════════════════════════════════════════════════════════════════

  List<_LocalHint> _localFuzzyPass(List<TokenLine> tokenLines) {
    final hints = <_LocalHint>[];
    for (final line in tokenLines) {
      for (final token in line.tokens) {
        // Skip pure-number tokens and very short ones
        if (token.length < 3) continue;
        if (RegExp(r'^\d+([.\/-]\d+)?$').hasMatch(token)) continue;

        final match = MedicineDatabase.findBest(token);
        if (match != null) {
          hints.add(_LocalHint(
            rawToken: token,
            canonical: match.entry.canonical,
            category: match.entry.category,
            commonDose: match.entry.commonDose,
            confidence: match.confidence,
          ));
        }
      }
    }
    // Deduplicate by canonical name, keep highest confidence
    final seen = <String, _LocalHint>{};
    for (final h in hints) {
      final existing = seen[h.canonical];
      if (existing == null || h.confidence > existing.confidence) {
        seen[h.canonical] = h;
      }
    }
    return seen.values.toList()
      ..sort((a, b) => b.confidence.compareTo(a.confidence));
  }

  // ════════════════════════════════════════════════════════════════════════
  // STAGE 3 — Claude AI interpretation
  // ════════════════════════════════════════════════════════════════════════

  Future<PrescriptionResult> _claudeInterpret({
    required String rawOcrText,
    required _PreprocessedText preprocessed,
    required List<_LocalHint> localHints,
  }) async {
    final hintsJson = localHints.isEmpty
        ? 'No strong local matches found.'
        : localHints
        .map((h) =>
    '• "${h.rawToken}" → ${h.canonical} (${h.category}, confidence: ${(h.confidence * 100).round()}%)')
        .join('\n');

    final prompt = '''
You are a medical prescription interpreter AI. Your task is to read OCR-extracted text from a handwritten doctor's prescription and extract ALL medicines with their dosages, even if the handwriting was poor and OCR produced garbled text.

## RAW OCR TEXT (may contain errors from bad handwriting):
"""
${preprocessed.cleanedText}
"""

## LOCAL FUZZY DB HINTS (pre-matched medicines to help you):
$hintsJson

## YOUR TASK:
1. Identify EVERY medicine in the prescription. Doctors write multiple medicines — find ALL of them.
2. For each medicine, extract: name, dose, frequency, duration, route (if stated), and any special instructions.
3. Correct OCR errors using medical knowledge. Common OCR errors: 0↔O, 1↔l, rn↔m, cl↔d, etc.
4. Decode all abbreviations: OD=once daily, BD=twice daily, TDS=three times daily, QDS/QID=four times daily, SOS/PRN=as needed, AC=before meals, PC=after meals, HS=at bedtime, etc.
5. If a medicine name is partially garbled, infer from context, category, and dose.
6. Medicines are usually on separate lines. Each line may have: [Medicine Name] [Dose] [Frequency] [Duration].

## OUTPUT FORMAT (respond ONLY with valid JSON, no markdown, no explanation):
{
  "medicines": [
    {
      "name": "Canonical medicine name",
      "raw_ocr": "What OCR produced for this medicine",
      "dose": "e.g. 500mg",
      "frequency": "e.g. Twice daily (BD)",
      "duration": "e.g. 5 days",
      "route": "oral / topical / etc. (omit if not stated)",
      "special_instructions": "e.g. Take after meals (omit if none)",
      "confidence": 0.0 to 1.0,
      "corrections_made": ["list of OCR corrections applied"]
    }
  ],
  "patient_instructions": "Any general instructions (omit if none)",
  "doctor_notes": "Any other notes (omit if none)",
  "interpretation_warnings": ["list of medicines with very low confidence or ambiguity"]
}
''';

    try {
      final response = await http.post(
        Uri.parse(_apiUrl),
        headers: {
          'Content-Type': 'application/json',
          'x-api-key': _apiKey,
          'anthropic-version': '2023-06-01',
        },
        body: jsonEncode({
          'model': _model,
          'max_tokens': 2048,
          'messages': [
            {'role': 'user', 'content': prompt}
          ],
        }),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        final content = decoded['content'][0]['text'] as String;
        return _parseAiResponse(content, rawOcrText, localHints);
      } else {
        // AI failed → fall back to local-only result
        return _buildLocalFallback(rawOcrText, localHints,
            error: 'AI API error ${response.statusCode}');
      }
    } catch (e) {
      return _buildLocalFallback(rawOcrText, localHints,
          error: 'Network error: $e');
    }
  }

  PrescriptionResult _parseAiResponse(
      String jsonText,
      String rawOcr,
      List<_LocalHint> localHints,
      ) {
    // Strip possible markdown code fences
    var clean = jsonText.trim();
    if (clean.startsWith('```')) {
      clean = clean.replaceAll(RegExp(r'^```[a-z]*\n?', multiLine: true), '');
      clean = clean.replaceAll(RegExp(r'```$', multiLine: true), '');
      clean = clean.trim();
    }

    try {
      final data = jsonDecode(clean) as Map<String, dynamic>;
      final medicinesJson = data['medicines'] as List<dynamic>? ?? [];

      final medicines = medicinesJson.map((m) {
        final map = m as Map<String, dynamic>;
        final rawFreq = map['frequency'] as String? ?? '';
        final decodedFreq = AbbreviationDecoder.annotateDosage(rawFreq);

        return InterpretedMedicine(
          name: map['name'] as String? ?? 'Unknown',
          rawOcr: map['raw_ocr'] as String? ?? '',
          dose: map['dose'] as String? ?? '',
          frequency: decodedFreq,
          duration: map['duration'] as String? ?? '',
          route: map['route'] as String?,
          specialInstructions: map['special_instructions'] as String?,
          confidence: (map['confidence'] as num?)?.toDouble() ?? 0.5,
          correctionsMade: List<String>.from(map['corrections_made'] ?? []),
        );
      }).toList();

      final warnings =
      List<String>.from(data['interpretation_warnings'] ?? []);
      final patientInstructions = data['patient_instructions'] as String?;
      final doctorNotes = data['doctor_notes'] as String?;

      return PrescriptionResult(
        medicines: medicines,
        patientInstructions: patientInstructions,
        doctorNotes: doctorNotes,
        interpretationWarnings: warnings,
        rawOcrText: rawOcr,
        interpretationMode: InterpretationMode.aiAssisted,
      );
    } catch (e) {
      // JSON parse failed — try to salvage with local hints
      return _buildLocalFallback(rawOcr, localHints,
          error: 'JSON parse error: $e');
    }
  }

  /// Fallback: build result purely from local DB matches (no AI).
  PrescriptionResult _buildLocalFallback(
      String rawOcr,
      List<_LocalHint> localHints, {
        String? error,
      }) {
    final medicines = localHints.map((h) {
      return InterpretedMedicine(
        name: h.canonical,
        rawOcr: h.rawToken,
        dose: h.commonDose?.split(' ').first ?? '',
        frequency: h.commonDose ?? 'See prescription',
        duration: '',
        confidence: h.confidence,
        correctionsMade: ['Matched via local medicine database'],
      );
    }).toList();

    final warnings = <String>[];
    if (error != null) warnings.add('AI interpretation unavailable: $error');
    if (medicines.isEmpty) {
      warnings.add('Could not identify any medicines. Please verify manually.');
    }

    return PrescriptionResult(
      medicines: medicines,
      interpretationWarnings: warnings,
      rawOcrText: rawOcr,
      interpretationMode: InterpretationMode.localOnly,
    );
  }
}

// ── Internal data classes ────────────────────────────────────────────────

class _PreprocessedText {
  final String cleanedText;
  final List<TokenLine> tokenLines;
  _PreprocessedText({required this.cleanedText, required this.tokenLines});
}

class TokenLine {
  final String raw;
  final List<String> tokens;
  TokenLine({required this.raw, required this.tokens});
}

class _LocalHint {
  final String rawToken;
  final String canonical;
  final String category;
  final String? commonDose;
  final double confidence;
  _LocalHint({
    required this.rawToken,
    required this.canonical,
    required this.category,
    this.commonDose,
    required this.confidence,
  });
}
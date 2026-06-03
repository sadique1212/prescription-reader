// lib/services/ai_interpretation_service.dart
// FIXED: 429 rate limit handled with retry + exponential backoff
// Tries gemini-2.0-flash → gemini-1.5-flash → gemini-1.5-flash-latest → local DB

import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import '../models/prescription_result.dart';
import 'medicine_database.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/foundation.dart';

class AiInterpretationService {
  static String get _apiKey => dotenv.env['GEMINI_API_KEY'] ?? '';

  // Model list in priority order — will try each until one works
  static const List<String> _models = [
    'gemini-2.0-flash',
    'gemini-1.5-flash',
    'gemini-1.5-flash-latest',
    'gemini-1.5-flash-8b',
  ];

  static String _modelUrl(String model) =>
      'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent';

  Future<PrescriptionResult> interpret(String rawOcrText) async {
    final preprocessed = _preprocess(rawOcrText);
    final localHints = _localFuzzyPass(preprocessed.tokenLines);

    if (_apiKey.isEmpty) {
      return _buildLocalFallback(rawOcrText, localHints,
          error: 'No GEMINI_API_KEY found in .env file');
    }

    final prompt = _buildPrompt(preprocessed.cleanedText, localHints);

    // Try each model with retry on 429
    for (final model in _models) {
      final result = await _tryModelWithRetry(
        model: model,
        prompt: prompt,
        rawOcrText: rawOcrText,
        localHints: localHints,
      );
      if (result != null) return result;
    }

    // All models failed — use local DB
    return _buildLocalFallback(rawOcrText, localHints,
        error: 'All Gemini models rate limited. Try again in 1 minute.');
  }

  // ── Try a model with up to 3 retries on 429 ───────────────────────────
  Future<PrescriptionResult?> _tryModelWithRetry({
    required String model,
    required String prompt,
    required String rawOcrText,
    required List<_LocalHint> localHints,
  }) async {
    const maxRetries = 3;
    const baseDelayMs = 5000; // 5 seconds

    for (int attempt = 0; attempt < maxRetries; attempt++) {
      try {
        final response = await http
            .post(
          Uri.parse('${_modelUrl(model)}?key=$_apiKey'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'contents': [
              {
                'parts': [
                  {'text': prompt}
                ]
              }
            ],
            'generationConfig': {
              'temperature': 0.1,
              'maxOutputTokens': 2048,
            },
          }),
        )
            .timeout(const Duration(seconds: 30));

        debugPrint('Gemini [$model] attempt ${attempt + 1}: ${response.statusCode}');

        if (response.statusCode == 200) {
          final decoded = jsonDecode(response.body);
          final text =
          decoded['candidates'][0]['content']['parts'][0]['text'] as String;
          return _parseResponse(text, rawOcrText, localHints);
        } else if (response.statusCode == 429) {
          // Rate limited — wait and retry
          if (attempt < maxRetries - 1) {
            final waitMs = baseDelayMs * (attempt + 1); // 5s, 10s, 15s
            debugPrint('Rate limited on $model, waiting ${waitMs}ms before retry...');
            await Future.delayed(Duration(milliseconds: waitMs));
            continue;
          } else {
            // Exhausted retries for this model
            debugPrint('Rate limit exhausted for $model, trying next model');
            return null; // Signal to try next model
          }
        } else if (response.statusCode == 404) {
          // Model not available on this key
          debugPrint('Model $model not found (404), trying next');
          return null;
        } else {
          debugPrint('Gemini [$model] error ${response.statusCode}: ${response.body}');
          return null; // Try next model
        }
      } catch (e) {
        debugPrint('Gemini [$model] network error: $e');
        if (attempt < maxRetries - 1) {
          await Future.delayed(const Duration(seconds: 3));
        } else {
          return null;
        }
      }
    }
    return null;
  }

  // ── Prompt builder ─────────────────────────────────────────────────────
  String _buildPrompt(String cleanedText, List<_LocalHint> localHints) {
    final hintsText = localHints.isEmpty
        ? 'No strong local matches.'
        : localHints
        .map((h) =>
    '• "${h.rawToken}" → ${h.canonical} (${h.category}, ${(h.confidence * 100).round()}%)')
        .join('\n');

    return '''
You are a pharmacist specializing in Indian handwritten prescriptions.
OCR text from a handwritten Indian prescription is below — it will have many errors.

YOUR JOB: Identify EVERY medicine on the prescription, correcting OCR errors using medical knowledge.

COMMON INDIAN BRANDS TO KNOW:
- Oxalgin DP = Diclofenac+Paracetamol+Serratiopeptidase
- Neuforce = Methylcobalamin+Alpha Lipoic Acid
- Pan D / Pan 40 = Pantoprazole or Pantoprazole+Domperidone
- Aristozyme = Digestive enzyme syrup
- Becosules = Vitamin B Complex
- Sumo L = Nimesulide+Paracetamol
- Dolo 650 = Paracetamol 650mg
- Chymoral Forte = Trypsin+Chymotrypsin
- Zerodol SP = Aceclofenac+Paracetamol+Serratiopeptidase
- Taxim O = Cefixime 200mg
- Mox = Amoxicillin
- Augmentin 625 = Co-Amoxiclav 625mg
- Montair LC = Montelukast+Levocetirizine
- Nervijen = B1+B6+B12

PRESCRIPTION FORMAT (India):
Each line = Medicine [Dose] [Qty: 1×10, 2×15, 3×10 etc]
- 1×10 = 1 strip of 10 tablets
- OD=once daily, BD=twice daily, TDS=3x daily
- IP=after food, AC=before meals, HS=bedtime

OCR TEXT:
"""
$cleanedText
"""

DB HINTS (pre-matched):
$hintsText

OUTPUT ONLY THIS JSON (no markdown, no extra text):
{
  "medicines": [
    {
      "name": "Full correct medicine/brand name",
      "raw_ocr": "what OCR said",
      "dose": "e.g. 500mg or empty string",
      "frequency": "e.g. Twice daily (BD)",
      "duration": "e.g. 1×10 strip or 5 days",
      "route": "Oral",
      "special_instructions": "e.g. After meals or empty string",
      "confidence": 0.85,
      "corrections_made": ["OCR correction note"]
    }
  ],
  "patient_instructions": "general instructions if any",
  "interpretation_warnings": ["only if truly unreadable"]
}''';
  }

  // ── Pre-processing ────────────────────────────────────────────────────
  _PreprocessedText _preprocess(String raw) {
    var text = raw
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll(RegExp(r'[ \t]{2,}'), ' ')
        .replaceAll(RegExp(r'[|\\~`]'), ' ')
        .replaceAll('PCM', 'Paracetamol')
        .replaceAll('Tab.', 'Tablet ')
        .replaceAll('Tab ', 'Tablet ')
        .replaceAll('Cap.', 'Capsule ')
        .replaceAll('Cap ', 'Capsule ')
        .replaceAll('Inj.', 'Injection ')
        .replaceAll('Syr.', 'Syrup ');
    text = text.replaceAllMapped(
      RegExp(r'(\d+)\s*(mg|mcg|ml|g|iu)\b', caseSensitive: false),
          (m) => '${m[1]}${m[2]!.toLowerCase()}',
    );
    final lines = text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty && l.length > 1)
        .toList();
    final tokenLines = lines.map((line) {
      final tokens = line
          .split(RegExp(r'[,;\s]+'))
          .map((t) => t.trim())
          .where((t) => t.isNotEmpty)
          .toList();
      return TokenLine(raw: line, tokens: tokens);
    }).toList();
    return _PreprocessedText(
        cleanedText: lines.join('\n'), tokenLines: tokenLines);
  }

  // ── Local fuzzy DB pass ───────────────────────────────────────────────
  List<_LocalHint> _localFuzzyPass(List<TokenLine> tokenLines) {
    final hints = <_LocalHint>[];
    for (final line in tokenLines) {
      for (final token in line.tokens) {
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

  // ── Response parsing ──────────────────────────────────────────────────
  PrescriptionResult _parseResponse(
      String jsonText,
      String rawOcr,
      List<_LocalHint> localHints,
      ) {
    final clean = _extractJson(jsonText);
    try {
      final data = jsonDecode(clean) as Map<String, dynamic>;
      final medicinesJson = data['medicines'] as List<dynamic>? ?? [];

      final medicines = medicinesJson.map((m) {
        final map = m as Map<String, dynamic>;
        final rawFreq = map['frequency'] as String? ?? '';
        final freq = rawFreq.contains('(')
            ? rawFreq
            : AbbreviationDecoder.annotateDosage(rawFreq);
        return InterpretedMedicine(
          name: _cleanName(map['name'] as String? ?? 'Unknown'),
          rawOcr: map['raw_ocr'] as String? ?? '',
          dose: map['dose'] as String? ?? '',
          frequency: freq,
          duration: map['duration'] as String? ?? '',
          route: map['route'] as String?,
          specialInstructions: map['special_instructions'] as String?,
          confidence: (map['confidence'] as num?)?.toDouble() ?? 0.5,
          correctionsMade: List<String>.from(map['corrections_made'] ?? []),
        );
      }).toList();

      return PrescriptionResult(
        medicines: medicines,
        patientInstructions: data['patient_instructions'] as String?,
        interpretationWarnings:
        List<String>.from(data['interpretation_warnings'] ?? []),
        rawOcrText: rawOcr,
        interpretationMode: InterpretationMode.aiAssisted,
      );
    } catch (e) {
      debugPrint('JSON parse error: $e\nRaw: $clean');
      return _buildLocalFallback(rawOcr, localHints, error: 'Parse error: $e');
    }
  }

  String _extractJson(String text) {
    text = text.trim();
    final fence =
    RegExp(r'```(?:json)?\s*([\s\S]*?)```', dotAll: true).firstMatch(text);
    if (fence != null) return fence.group(1)!.trim();
    final s = text.indexOf('{');
    final e = text.lastIndexOf('}');
    if (s != -1 && e != -1 && e > s) return text.substring(s, e + 1);
    return text;
  }

  String _cleanName(String name) {
    return name
        .replaceAll(
        RegExp(
            r'^(Tab\.?|Cap\.?|Tablet|Capsule|Syrup|Inj\.?|Injection)\s+',
            caseSensitive: false),
        '')
        .trim();
  }

  // ── Local fallback ────────────────────────────────────────────────────
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
    if (error != null) warnings.add('AI unavailable: $error');
    if (medicines.isEmpty) {
      warnings.add('No medicines identified. Please verify manually.');
    }

    return PrescriptionResult(
      medicines: medicines,
      interpretationWarnings: warnings,
      rawOcrText: rawOcr,
      interpretationMode: InterpretationMode.localOnly,
    );
  }
}

// ── Internal types ────────────────────────────────────────────────────────

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
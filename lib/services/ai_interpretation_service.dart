// lib/services/ai_interpretation_service.dart
// Gemini 2.0 Flash — improved prompt for precise medicine names + robust JSON extraction

import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/prescription_result.dart';
import 'medicine_database.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/foundation.dart';

class AiInterpretationService {
  static String get _apiKey =>
      dotenv.env['GEMINI_API_KEY'] ?? '';
  static const String _apiUrl =
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent';

  Future<PrescriptionResult> interpret(String rawOcrText) async {
    final preprocessed = _preprocess(rawOcrText);
    final localMatches = _localFuzzyPass(preprocessed.tokenLines);
    return await _geminiInterpret(
      rawOcrText: rawOcrText,
      preprocessed: preprocessed,
      localHints: localMatches,
    );
  }

  // ── Pre-processing ────────────────────────────────────────────────────
  _PreprocessedText _preprocess(String raw) {
    var text = raw
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll(RegExp(r'[ \t]{2,}'), ' ')
        .replaceAll(RegExp(r'[|\\~`]'), ' ');
    text = _fixOcrSubstitutions(text);
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

  String _fixOcrSubstitutions(String text) {
    return text
        .replaceAllMapped(RegExp(r'\b0(\w{3,})'), (m) => 'O${m[1]}')
        .replaceAllMapped(RegExp(r'\b1([a-z]{2,})'), (m) => 'l${m[1]}')
        .replaceAll('Arnox', 'Amox')
        .replaceAll('Paracetarno', 'Paracetamo')
        .replaceAll('Para ', 'Paracetamol ')
        .replaceAll('PCM', 'Paracetamol')
        .replaceAll('Pcm', 'Paracetamol')
        .replaceAll('Tab.', 'Tablet ')
        .replaceAll('Tab ', 'Tablet ')
        .replaceAll('Cap.', 'Capsule ')
        .replaceAll('Cap ', 'Capsule ')
        .replaceAll('Inj.', 'Injection ')
        .replaceAll('Syr.', 'Syrup ')
        .replaceAllMapped(
      RegExp(r'(\d)\s+(\d{2,3})\s*mg', caseSensitive: false),
          (m) => '${m[1]}${m[2]}mg',
    )
        .replaceAllMapped(
      RegExp(r'(\d+)\s*(mg|mcg|ml|g|iu)\b', caseSensitive: false),
          (m) => '${m[1]}${m[2]!.toLowerCase()}',
    );
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

  // ── Gemini API call ───────────────────────────────────────────────────
  Future<PrescriptionResult> _geminiInterpret({
    required String rawOcrText,
    required _PreprocessedText preprocessed,
    required List<_LocalHint> localHints,
  }) async {
    final hintsText = localHints.isEmpty
        ? 'No strong local matches.'
        : localHints
        .map((h) =>
    '• "${h.rawToken}" → ${h.canonical} (${h.category}, ${(h.confidence * 100).round()}%)')
        .join('\n');

    // ── Precision-focused prompt ─────────────────────────────────────
    final prompt = '''
You are a highly accurate medical prescription interpreter used by pharmacists.
Your job: extract every medicine from this OCR text with COMPLETE, CORRECT names.

CRITICAL RULES FOR MEDICINE NAMES:
- Always write the FULL generic name: "Amoxicillin" not "Amox", "Paracetamol" not "PCM"
- Correct OCR errors using your medical knowledge
- Common OCR errors: rn→m (arnoxicillin→amoxicillin), cl→d, 0→O, 1→l, vv→w
- If you see "Tab" or "Cap" before a name, that is the dosage form, not the name
- Brand names: convert to generic (Crocin→Paracetamol, Augmentin→Co-Amoxiclav, Ventolin→Salbutamol)
- Confidence: 0.9+ if name is clear, 0.7 if minor correction made, 0.5 if uncertain

FREQUENCY DECODING (always spell out):
OD/od = "Once daily", BD/bd = "Twice daily", TDS/tds = "Three times daily",
QDS/QID = "Four times daily", SOS/PRN = "As needed", HS = "At bedtime",
AC = "Before meals", PC = "After meals", STAT = "Immediately"

RAW OCR TEXT FROM PRESCRIPTION:
"""
${preprocessed.cleanedText}
"""

LOCAL DATABASE HINTS (pre-matched, use these to help):
$hintsText

TASK: Extract ALL medicines. Each line in the prescription usually = one medicine.
Format: [Medicine Name] [Dose] [Frequency] [Duration] [Special instructions]

RESPOND WITH ONLY THIS JSON (no markdown, no explanation, no code blocks):
{
  "medicines": [
    {
      "name": "Full correct generic medicine name",
      "raw_ocr": "exactly what OCR said",
      "dose": "e.g. 500mg or 5ml",
      "frequency": "spelled out e.g. Twice daily (BD)",
      "duration": "e.g. 5 days or 1 month",
      "route": "Oral / Topical / Inhaled (omit if not stated)",
      "special_instructions": "e.g. After meals, With water (omit if none)",
      "confidence": 0.85,
      "corrections_made": ["arnox → Amoxicillin (OCR error rn→m)"]
    }
  ],
  "patient_instructions": "Any general instructions written on prescription (omit if none)",
  "interpretation_warnings": ["Only add if a medicine name is very unclear"]
}
''';

    try {
      final response = await http
          .post(
        Uri.parse('$_apiUrl?key=$_apiKey'),
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
            'temperature': 0.1, // low = more deterministic/accurate
            'maxOutputTokens': 2048,
            'responseMimeType': 'application/json', // force JSON response
          },
        }),
      )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        final text =
        decoded['candidates'][0]['content']['parts'][0]['text'] as String;
        return _parseResponse(text, rawOcrText, localHints);
      } else {
        debugPrint('Gemini API error: ${response.statusCode}\n${response.body}');
        return _buildLocalFallback(rawOcrText, localHints,
            error: 'API error ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Gemini network error: $e');
      return _buildLocalFallback(rawOcrText, localHints,
          error: 'Network error: $e');
    }
  }

  // ── Robust JSON parser ────────────────────────────────────────────────
  PrescriptionResult _parseResponse(
      String jsonText,
      String rawOcr,
      List<_LocalHint> localHints,
      ) {
    // Extract JSON from response — handles markdown fences, extra text
    String clean = _extractJson(jsonText);

    try {
      final data = jsonDecode(clean) as Map<String, dynamic>;
      final medicinesJson = data['medicines'] as List<dynamic>? ?? [];

      final medicines = medicinesJson.map((m) {
        final map = m as Map<String, dynamic>;
        final rawFreq = map['frequency'] as String? ?? '';
        // Don't double-annotate if Gemini already spelled it out
        final freq = rawFreq.contains('(')
            ? rawFreq
            : AbbreviationDecoder.annotateDosage(rawFreq);
        return InterpretedMedicine(
          name: _cleanMedicineName(map['name'] as String? ?? 'Unknown'),
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
      return _buildLocalFallback(rawOcr, localHints,
          error: 'Parse error: $e');
    }
  }

  // ── Extract JSON even if surrounded by markdown/text ─────────────────
  String _extractJson(String text) {
    text = text.trim();

    // Try removing ```json ... ``` or ``` ... ```
    final fenceMatch =
    RegExp(r'```(?:json)?\s*([\s\S]*?)```', dotAll: true).firstMatch(text);
    if (fenceMatch != null) {
      return fenceMatch.group(1)!.trim();
    }

    // Try finding raw { ... } block
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start != -1 && end != -1 && end > start) {
      return text.substring(start, end + 1);
    }

    return text;
  }

  // ── Clean medicine name — remove dosage form prefix if present ────────
  String _cleanMedicineName(String name) {
    return name
        .replaceAll(RegExp(r'^(Tab\.?|Cap\.?|Tablet|Capsule|Syrup|Inj\.?|Injection)\s+', caseSensitive: false), '')
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

// ── Internal classes ──────────────────────────────────────────────────────

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
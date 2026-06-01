// lib/services/ai_interpretation_service.dart
// FIXED: Correct Gemini model (gemini-1.5-flash → gemini-2.0-flash),
// improved prompt for Indian handwritten prescriptions with combo drugs

import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/prescription_result.dart';
import 'medicine_database.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/foundation.dart';

class AiInterpretationService {
  static String get _apiKey => dotenv.env['GEMINI_API_KEY'] ?? '';

  // FIXED: Use gemini-2.0-flash (gemini-1.5-flash endpoint was returning 404)
  static const String _model = 'gemini-2.0-flash';
  static String get _apiUrl =>
      'https://generativelanguage.googleapis.com/v1beta/models/$_model:generateContent';

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
        .replaceAll('Tab.', 'Tablet ')
        .replaceAll('Tab ', 'Tablet ')
        .replaceAll('Cap.', 'Capsule ')
        .replaceAll('Cap ', 'Capsule ')
        .replaceAll('Inj.', 'Injection ')
        .replaceAll('Syr.', 'Syrup ')
        .replaceAll('PCM', 'Paracetamol')
        .replaceAll('Para ', 'Paracetamol ')
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

    final prompt = '''
You are a pharmacist's assistant specializing in Indian handwritten prescriptions.
The OCR text below came from a handwritten Indian prescription and will have many errors.

YOUR MOST IMPORTANT JOB: Identify the correct medicine brand/generic name even when OCR has mangled it badly.

COMMON INDIAN PRESCRIPTION MEDICINES AND BRAND NAMES YOU MUST KNOW:
- Oxalgin DP = Diclofenac + Paracetamol + Serratiopeptidase (combo NSAID)
- Neuforce = Methylcobalamin + Alpha Lipoic Acid (nerve supplement)  
- Pan 40 / Pan D = Pantoprazole or Pantoprazole + Domperidone
- Aristozyme = Digestive enzyme syrup
- Becosules = Vitamin B complex capsule
- Sumo / Sumo L = Nimesulide + Paracetamol
- Dolo 650 = Paracetamol 650mg
- Chymoral Forte = Trypsin + Chymotrypsin (enzyme)
- Zerodol SP / Zerodol P = Aceclofenac + Paracetamol (+Serratiopeptidase)
- Nervijen = B1+B6+B12 nerve vitamin
- Calpol / Crocin = Paracetamol
- Mox = Amoxicillin
- Taxim / Cefixime = Cefixime antibiotic
- Cifran = Ciprofloxacin
- Omnacortil = Prednisolone
- Montair LC = Montelukast + Levocetirizine
- Sinarest / Cetcip = Cetirizine antihistamine

PRESCRIPTION FORMAT USED IN INDIA:
Each line = [Medicine Name] [Dose] [Qty e.g. 1×10, 2×15, 3×10]
- 1×10 means 1 strip of 10 tablets
- 2×15 means 2 strips of 15 tablets  
- 5d / 7d / 10d = 5/7/10 days course
- OD = once daily, BD = twice daily, TDS = 3 times daily
- HS = at bedtime, AC = before meals, PC = after meals
- IP = after food (Indian usage)
- SOS = as needed

OCR TEXT (has errors — decode carefully using your medical knowledge):
"""
${preprocessed.cleanedText}
"""

LOCAL DB HINTS (pre-matched tokens):
$hintsText

TASK: For EACH line in the prescription, identify the medicine. 
Use your knowledge of Indian brand names to correct OCR errors.
Example: "Oxalgin DP 2×15" → name="Oxalgin DP", dose="", frequency="Twice daily", duration="2 strips × 15 tabs"

RESPOND WITH ONLY THIS JSON (no markdown, no code blocks, no extra text):
{
  "medicines": [
    {
      "name": "Correct medicine/brand name",
      "raw_ocr": "what OCR said for this line",
      "dose": "e.g. 500mg or empty string",
      "frequency": "spelled out e.g. Twice daily (BD)",
      "duration": "e.g. 5 days or 1x10 strip",
      "route": "Oral",
      "special_instructions": "e.g. After meals (IP) or empty string",
      "confidence": 0.85,
      "corrections_made": ["brief note on what OCR error was fixed"]
    }
  ],
  "patient_instructions": "any general instructions if visible",
  "interpretation_warnings": ["only if a name is truly unreadable"]
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
            'temperature': 0.1,
            'maxOutputTokens': 2048,
          },
        }),
      )
          .timeout(const Duration(seconds: 30));

      debugPrint('Gemini status: ${response.statusCode}');
      if (response.statusCode != 200) {
        debugPrint('Gemini error body: ${response.body}');
      }

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        final text =
        decoded['candidates'][0]['content']['parts'][0]['text'] as String;
        return _parseResponse(text, rawOcrText, localHints);
      } else {
        // Try fallback model if primary fails
        return await _tryFallbackModel(
            prompt, rawOcrText, localHints,
            error: 'API error ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Gemini network error: $e');
      return _buildLocalFallback(rawOcrText, localHints,
          error: 'Network error: $e');
    }
  }

  // ── Fallback to gemini-1.5-flash if 2.0 fails ─────────────────────────
  Future<PrescriptionResult> _tryFallbackModel(
      String prompt,
      String rawOcr,
      List<_LocalHint> localHints, {
        String? error,
      }) async {
    const fallbackUrl =
        'https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash-latest:generateContent';
    try {
      final response = await http
          .post(
        Uri.parse('$fallbackUrl?key=$_apiKey'),
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

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        final text =
        decoded['candidates'][0]['content']['parts'][0]['text'] as String;
        return _parseResponse(text, rawOcr, localHints);
      }
    } catch (_) {}
    return _buildLocalFallback(rawOcr, localHints, error: error);
  }

  // ── Robust JSON parser ────────────────────────────────────────────────
  PrescriptionResult _parseResponse(
      String jsonText,
      String rawOcr,
      List<_LocalHint> localHints,
      ) {
    String clean = _extractJson(jsonText);
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
      return _buildLocalFallback(rawOcr, localHints, error: 'Parse error: $e');
    }
  }

  String _extractJson(String text) {
    text = text.trim();
    final fenceMatch =
    RegExp(r'```(?:json)?\s*([\s\S]*?)```', dotAll: true).firstMatch(text);
    if (fenceMatch != null) return fenceMatch.group(1)!.trim();
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start != -1 && end != -1 && end > start) {
      return text.substring(start, end + 1);
    }
    return text;
  }

  String _cleanMedicineName(String name) {
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
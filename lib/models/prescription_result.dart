// lib/models/prescription_result.dart
// Data models for Layer 2 structured output

enum InterpretationMode { aiAssisted, localOnly }

/// A single interpreted medicine from the prescription.
class InterpretedMedicine {
  final String name;
  final String rawOcr; // what OCR originally produced
  final String dose;
  final String frequency; // already decoded abbreviations
  final String duration;
  final String? route;
  final String? specialInstructions;
  final double confidence; // 0.0 – 1.0
  final List<String> correctionsMade;

  InterpretedMedicine({
    required this.name,
    required this.rawOcr,
    required this.dose,
    required this.frequency,
    required this.duration,
    this.route,
    this.specialInstructions,
    required this.confidence,
    this.correctionsMade = const [],
  });

  /// Human-readable full dosage string.
  String get fullDosage {
    final parts = <String>[];
    if (dose.isNotEmpty) parts.add(dose);
    if (frequency.isNotEmpty) parts.add(frequency);
    if (duration.isNotEmpty) parts.add('× $duration');
    return parts.join(' — ');
  }

  bool get isHighConfidence => confidence >= 0.75;
  bool get isMediumConfidence => confidence >= 0.5 && confidence < 0.75;
  bool get isLowConfidence => confidence < 0.5;
}

/// The full structured result of interpreting a prescription.
class PrescriptionResult {
  final List<InterpretedMedicine> medicines;
  final String? patientInstructions;
  final String? doctorNotes;
  final List<String> interpretationWarnings;
  final String rawOcrText;
  final InterpretationMode interpretationMode;

  PrescriptionResult({
    required this.medicines,
    this.patientInstructions,
    this.doctorNotes,
    this.interpretationWarnings = const [],
    required this.rawOcrText,
    required this.interpretationMode,
  });

  bool get hasWarnings => interpretationWarnings.isNotEmpty;
  bool get isAiAssisted => interpretationMode == InterpretationMode.aiAssisted;
}
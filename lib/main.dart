// lib/main.dart  (UPDATED — full Layer 1 + Layer 2 UI)
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'services/ocr_service.dart';
import 'models/ocr_result.dart';
import 'models/prescription_result.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');
  runApp(const PrescriptionApp());
}


class PrescriptionApp extends StatelessWidget {
  const PrescriptionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        colorScheme: ColorScheme.dark(
          primary: const Color(0xFF4A90D9),
          surface: const Color(0xFF1A1A2E),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF4A90D9),
            foregroundColor: Colors.white,
            shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _picker = ImagePicker();
  final _ocrService = OcrService();

  File? _originalImage;
  OcrResult? _result;
  bool _isProcessing = false;
  String _processingStep = '';

  @override
  void dispose() {
    _ocrService.dispose();
    super.dispose();
  }

  Future<void> _pickAndProcess(ImageSource source) async {
    final picked = await _picker.pickImage(
      source: source,
      imageQuality: 95,
      preferredCameraDevice: CameraDevice.rear,
    );
    if (picked == null) return;

    final cropped = await ImageCropper().cropImage(
      sourcePath: picked.path,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Align prescription',
          toolbarColor: const Color(0xFF1A1A2E),
          toolbarWidgetColor: Colors.white,
          activeControlsWidgetColor: const Color(0xFF4A90D9),
          initAspectRatio: CropAspectRatioPreset.original,
          lockAspectRatio: false,
        ),
      ],
    );
    if (cropped == null) return;

    setState(() {
      _originalImage = File(cropped.path);
      _result = null;
      _isProcessing = true;
      _processingStep = 'Enhancing image…';
    });

    await Future.delayed(const Duration(milliseconds: 80));
    setState(() => _processingStep = 'Layer 1 — OCR text extraction…');
    await Future.delayed(const Duration(milliseconds: 50));

    try {
      final result = await _ocrService.processImage(_originalImage!);
      if (result.hasAiResult) {
        setState(() => _processingStep = 'Layer 2 — AI interpretation…');
      }
      setState(() {
        _result = result;
        _isProcessing = false;
      });
    } catch (e) {
      setState(() => _isProcessing = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Processing failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 12),
              const Text(
                'Prescription Reader',
                style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: Colors.white),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              const Text(
                'AI-powered handwriting interpretation',
                style: TextStyle(color: Colors.white60, fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),

              // Image preview
              if (_originalImage != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.file(_originalImage!,
                      height: 220, fit: BoxFit.cover),
                )
              else
                Container(
                  height: 160,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A2E),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: const Center(
                    child: Icon(Icons.medication_rounded,
                        size: 64, color: Color(0xFF4A90D9)),
                  ),
                ),

              const SizedBox(height: 20),

              // Action buttons
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isProcessing
                          ? null
                          : () => _pickAndProcess(ImageSource.camera),
                      icon: const Icon(Icons.camera_alt),
                      label: const Text('Take Photo'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isProcessing
                          ? null
                          : () => _pickAndProcess(ImageSource.gallery),
                      icon: const Icon(Icons.upload),
                      label: const Text('Upload'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF4A90D9),
                        side: const BorderSide(color: Color(0xFF4A90D9)),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // Processing indicator
              if (_isProcessing)
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A2E),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Color(0xFF4A90D9)),
                      ),
                      const SizedBox(width: 16),
                      Text(_processingStep,
                          style:
                          const TextStyle(color: Colors.white70)),
                    ],
                  ),
                ),

              // Results
              if (_result != null) ...[
                _QualityBadge(score: _result!.imageQualityScore),
                if (_result!.warningMessage != null) ...[
                  const SizedBox(height: 8),
                  _WarningBanner(message: _result!.warningMessage!),
                ],
                const SizedBox(height: 12),

                // ── LAYER 2: AI interpreted medicines ──────────────────
                if (_result!.hasAiResult) ...[
                  _PrescriptionCard(result: _result!.prescriptionResult!),
                  const SizedBox(height: 12),
                ],

                // ── LAYER 1: Raw OCR text (collapsible) ────────────────
                _RawTextCard(result: _result!),
                const SizedBox(height: 8),
                _BlocksDebugView(blocks: _result!.blocks),
              ],

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
// LAYER 2 UI — Prescription Card
// ══════════════════════════════════════════════════════════════════════════

class _PrescriptionCard extends StatelessWidget {
  final PrescriptionResult result;
  const _PrescriptionCard({required this.result});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header row
        Row(
          children: [
            const Icon(Icons.auto_awesome, color: Color(0xFF4A90D9), size: 18),
            const SizedBox(width: 8),
            const Text(
              'AI Interpretation',
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16),
            ),
            const Spacer(),
            Container(
              padding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: result.isAiAssisted
                    ? const Color(0xFF4A90D9).withOpacity(0.2)
                    : Colors.orange.withOpacity(0.2),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: result.isAiAssisted
                        ? const Color(0xFF4A90D9).withOpacity(0.5)
                        : Colors.orange.withOpacity(0.5)),
              ),
              child: Text(
                result.isAiAssisted ? 'AI + DB' : 'DB only',
                style: TextStyle(
                    fontSize: 11,
                    color: result.isAiAssisted
                        ? const Color(0xFF4A90D9)
                        : Colors.orange,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Medicines
        if (result.medicines.isEmpty)
          _emptyState()
        else
          ...result.medicines.map((m) => _MedicineCard(medicine: m)),

        // Patient instructions
        if (result.patientInstructions != null) ...[
          const SizedBox(height: 8),
          _InfoBox(
            icon: Icons.info_outline,
            label: 'Instructions',
            text: result.patientInstructions!,
            color: Colors.blue,
          ),
        ],

        // Interpretation warnings
        if (result.hasWarnings) ...[
          const SizedBox(height: 8),
          ...result.interpretationWarnings.map((w) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: _InfoBox(
              icon: Icons.warning_amber,
              label: 'Warning',
              text: w,
              color: Colors.orange,
            ),
          )),
        ],
      ],
    );
  }

  Widget _emptyState() => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: const Color(0xFF1A1A2E),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.white10),
    ),
    child: const Center(
      child: Text(
        'No medicines identified. Try a clearer photo.',
        style: TextStyle(color: Colors.white54),
        textAlign: TextAlign.center,
      ),
    ),
  );
}

class _MedicineCard extends StatefulWidget {
  final InterpretedMedicine medicine;
  const _MedicineCard({required this.medicine});

  @override
  State<_MedicineCard> createState() => _MedicineCardState();
}

class _MedicineCardState extends State<_MedicineCard> {
  bool _expanded = false;

  Color get _confidenceColor {
    if (widget.medicine.isHighConfidence) return Colors.green;
    if (widget.medicine.isMediumConfidence) return Colors.orange;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.medicine;
    return GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A2E),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: _confidenceColor.withOpacity(0.3), width: 1.2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Medicine name
                Expanded(
                  child: Text(
                    m.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                // Confidence badge
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _confidenceColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: _confidenceColor.withOpacity(0.4)),
                  ),
                  child: Text(
                    '${(m.confidence * 100).round()}%',
                    style: TextStyle(
                        color: _confidenceColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                    _expanded
                        ? Icons.expand_less
                        : Icons.expand_more,
                    color: Colors.white38,
                    size: 18),
              ],
            ),

            if (m.fullDosage.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                m.fullDosage,
                style: const TextStyle(
                    color: Color(0xFF4A90D9), fontSize: 13),
              ),
            ],

            if (m.specialInstructions != null) ...[
              const SizedBox(height: 4),
              Text(
                m.specialInstructions!,
                style:
                const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],

            // Expanded detail
            if (_expanded) ...[
              const Divider(color: Colors.white10, height: 16),
              if (m.rawOcr.isNotEmpty)
                _DetailRow('OCR read', m.rawOcr),
              if (m.dose.isNotEmpty) _DetailRow('Dose', m.dose),
              if (m.frequency.isNotEmpty)
                _DetailRow('Frequency', m.frequency),
              if (m.duration.isNotEmpty)
                _DetailRow('Duration', m.duration),
              if (m.route != null) _DetailRow('Route', m.route!),
              if (m.correctionsMade.isNotEmpty) ...[
                const SizedBox(height: 4),
                const Text('Corrections made:',
                    style: TextStyle(
                        color: Colors.white38, fontSize: 11)),
                ...m.correctionsMade.map((c) => Text(
                  '• $c',
                  style: const TextStyle(
                      color: Colors.white38, fontSize: 11),
                )),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _DetailRow(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(label,
              style: const TextStyle(
                  color: Colors.white38, fontSize: 12)),
        ),
        Expanded(
          child: Text(value,
              style: const TextStyle(
                  color: Colors.white70, fontSize: 12)),
        ),
      ],
    ),
  );
}

class _InfoBox extends StatelessWidget {
  final IconData icon;
  final String label;
  final String text;
  final Color color;
  const _InfoBox(
      {required this.icon,
        required this.label,
        required this.text,
        required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style:
                TextStyle(color: color.withOpacity(0.9), fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
// LAYER 1 UI — Quality, Raw Text, Blocks (unchanged from your original)
// ══════════════════════════════════════════════════════════════════════════

class _QualityBadge extends StatelessWidget {
  final double score;
  const _QualityBadge({required this.score});

  @override
  Widget build(BuildContext context) {
    final pct = (score * 100).round();
    final color =
    score > 0.7 ? Colors.green : score > 0.4 ? Colors.orange : Colors.red;
    final label = score > 0.7
        ? 'Good quality'
        : score > 0.4
        ? 'Acceptable'
        : 'Poor quality';
    return Row(
      children: [
        Container(
          padding:
          const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withOpacity(0.4)),
          ),
          child: Text(
            '$label  $pct%',
            style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

class _WarningBanner extends StatelessWidget {
  final String message;
  const _WarningBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.orange.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded,
              color: Colors.orange, size: 18),
          const SizedBox(width: 10),
          Expanded(
              child: Text(message,
                  style: const TextStyle(
                      color: Colors.orange, fontSize: 13))),
        ],
      ),
    );
  }
}

class _RawTextCard extends StatefulWidget {
  final OcrResult result;
  const _RawTextCard({required this.result});

  @override
  State<_RawTextCard> createState() => _RawTextCardState();
}

class _RawTextCardState extends State<_RawTextCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A2E),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Layer 1 — Raw OCR text',
                    style: TextStyle(color: Colors.white60, fontSize: 12)),
                Row(
                  children: [
                    Text('${widget.result.processingMs}ms',
                        style: const TextStyle(
                            color: Colors.white30, fontSize: 11)),
                    const SizedBox(width: 6),
                    Icon(_expanded ? Icons.expand_less : Icons.expand_more,
                        color: Colors.white30, size: 16),
                  ],
                ),
              ],
            ),
            if (_expanded) ...[
              const SizedBox(height: 8),
              Text(
                widget.result.rawText.isEmpty
                    ? '(no text detected)'
                    : widget.result.rawText,
                style: const TextStyle(
                    color: Colors.white, fontSize: 13, height: 1.6),
              ),
            ] else
              const SizedBox(height: 4),
            if (!_expanded)
              Text(
                widget.result.rawText.isEmpty
                    ? '(no text)'
                    : widget.result.rawText
                    .split('\n')
                    .take(2)
                    .join(' ')
                    .substring(0,
                    widget.result.rawText.length > 60 ? 60 : widget.result.rawText.length) +
                    '…',
                style: const TextStyle(
                    color: Colors.white54, fontSize: 12),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
      ),
    );
  }
}

class _BlocksDebugView extends StatefulWidget {
  final List<OcrBlock> blocks;
  const _BlocksDebugView({required this.blocks});

  @override
  State<_BlocksDebugView> createState() => _BlocksDebugViewState();
}

class _BlocksDebugViewState extends State<_BlocksDebugView> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Text(
                  '${widget.blocks.length} text blocks detected',
                  style: const TextStyle(
                      color: Colors.white30, fontSize: 12),
                ),
                const Spacer(),
                Icon(_expanded ? Icons.expand_less : Icons.expand_more,
                    color: Colors.white30, size: 16),
              ],
            ),
          ),
        ),
        if (_expanded)
          ...widget.blocks.map((b) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 38,
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    '${(b.confidence * 100).round()}%',
                    style: TextStyle(
                      fontSize: 11,
                      color: b.confidence > 0.7
                          ? Colors.green
                          : b.confidence > 0.4
                          ? Colors.orange
                          : Colors.red,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(b.text,
                      style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                          height: 1.4)),
                ),
              ],
            ),
          )),
      ],
    );
  }
}
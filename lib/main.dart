// lib/main.dart — Redesigned UI with fixed image cropper settings
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'services/ocr_service.dart';
import 'models/ocr_result.dart';
import 'models/prescription_result.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
  ));
  runApp(const PrescriptionApp());
}

// ── Design tokens ──────────────────────────────────────────────────────────
class AppColors {
  static const bg = Color(0xFF0A0E1A);
  static const surface = Color(0xFF111827);
  static const card = Color(0xFF1A2235);
  static const border = Color(0xFF2A3550);
  static const accent = Color(0xFF3B82F6);
  static const accentLight = Color(0xFF60A5FA);
  static const accentGlow = Color(0x303B82F6);
  static const success = Color(0xFF10B981);
  static const warning = Color(0xFFF59E0B);
  static const error = Color(0xFFEF4444);
  static const textPrimary = Color(0xFFF1F5F9);
  static const textSecondary = Color(0xFF94A3B8);
  static const textMuted = Color(0xFF475569);
}

class PrescriptionApp extends StatelessWidget {
  const PrescriptionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Medicine Reader',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: AppColors.bg,
        colorScheme: const ColorScheme.dark(
          primary: AppColors.accent,
          surface: AppColors.surface,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.accent,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
            textStyle: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
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

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  final _picker = ImagePicker();
  final _ocrService = OcrService();

  File? _originalImage;
  OcrResult? _result;
  bool _isProcessing = false;
  String _processingStep = '';

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.97, end: 1.03).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ocrService.dispose();
    _pulseController.dispose();
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
          toolbarTitle: 'Crop Prescription',
          toolbarColor: AppColors.surface,
          toolbarWidgetColor: AppColors.textPrimary,
          statusBarColor: AppColors.bg,
          backgroundColor: AppColors.bg,
          activeControlsWidgetColor: AppColors.accent,
          dimmedLayerColor: const Color(0xCC0A0E1A),
          cropFrameColor: AppColors.accent,
          cropGridColor: AppColors.accentLight,
          cropFrameStrokeWidth: 3,
          cropGridRowCount: 2,
          cropGridColumnCount: 2,
          initAspectRatio: CropAspectRatioPreset.original,
          lockAspectRatio: false,
          showCropGrid: true,
          hideBottomControls: false,
        ),
        IOSUiSettings(
          title: 'Crop Prescription',
          cancelButtonTitle: 'Cancel',
          doneButtonTitle: 'Done',
          resetAspectRatioEnabled: true,
          rotateButtonsHidden: false,
          hidesNavigationBar: false,
        ),
      ],
    );
    if (cropped == null) return;

    setState(() {
      _originalImage = File(cropped.path);
      _result = null;
      _isProcessing = true;
      _processingStep = 'Enhancing image quality…';
    });

    await Future.delayed(const Duration(milliseconds: 80));
    setState(() => _processingStep = 'Extracting text (OCR)…');
    await Future.delayed(const Duration(milliseconds: 50));

    try {
      final result = await _ocrService.processImage(_originalImage!);
      if (result.hasAiResult) {
        setState(() => _processingStep = 'AI interpretation…');
      }
      setState(() {
        _result = result;
        _isProcessing = false;
      });
    } catch (e) {
      setState(() => _isProcessing = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Processing failed: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: CustomScrollView(
        slivers: [
          _buildAppBar(context),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                const SizedBox(height: 20),
                _buildImageSection(),
                const SizedBox(height: 20),
                _buildActionButtons(),
                const SizedBox(height: 16),
                if (_isProcessing) _buildProcessingCard(),
                if (_result != null) ..._buildResults(),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppBar(BuildContext context) {
    final statusBarHeight = MediaQuery.of(context).padding.top;
    // expandedHeight = status bar + top row (~52px) + divider + credit row (~32px) + vertical padding
    final expandedHeight = statusBarHeight + 108.0;

    return SliverAppBar(
      expandedHeight: expandedHeight,
      floating: false,
      pinned: true,
      backgroundColor: AppColors.bg,
      elevation: 0,
      toolbarHeight: 0,
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF0F172A), Color(0xFF0A0E1A)],
            ),
          ),
          padding: EdgeInsets.fromLTRB(20, statusBarHeight + 12, 20, 10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Row 1: icon  +  title  +  quality pill ──────────────
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: AppColors.accentGlow,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: AppColors.accent.withOpacity(0.4)),
                    ),
                    child: const Icon(Icons.medication_rounded,
                        color: AppColors.accentLight, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Medicine Reader',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.5,
                          ),
                        ),
                        Text(
                          'AI-Powered Prescription Reader',
                          style: TextStyle(
                            color: AppColors.textSecondary.withOpacity(0.65),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_result != null) ...[
                    const SizedBox(width: 8),
                    _StatusPill(score: _result!.imageQualityScore),
                  ],
                ],
              ),

              const SizedBox(height: 10),

              // ── Row 2: thin divider + "Made by MD SADIQUE" credit ───
              Container(
                height: 1,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppColors.accent.withOpacity(0.35),
                      AppColors.border.withOpacity(0.0),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.code_rounded,
                    size: 12,
                    color: AppColors.accent.withOpacity(0.7),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Made by',
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'MD SADIQUE',
                    style: TextStyle(
                      color: AppColors.accentLight.withOpacity(0.9),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImageSection() {
    if (_originalImage != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          children: [
            Image.file(_originalImage!,
                height: 230, width: double.infinity, fit: BoxFit.cover),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      AppColors.bg.withOpacity(0.6),
                    ],
                    stops: const [0.5, 1.0],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return ScaleTransition(
      scale: _pulseAnimation,
      child: Container(
        height: 200,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.border, width: 1.5),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.accentGlow,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.document_scanner_rounded,
                  size: 32, color: AppColors.accentLight),
            ),
            const SizedBox(height: 14),
            const Text(
              'Scan or Upload Prescription',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Supports handwritten prescriptions',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed:
            _isProcessing ? null : () => _pickAndProcess(ImageSource.camera),
            icon: const Icon(Icons.camera_alt_rounded, size: 18),
            label: const Text('Camera'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _OutlineBtn(
            onPressed: _isProcessing
                ? null
                : () => _pickAndProcess(ImageSource.gallery),
            icon: Icons.photo_library_rounded,
            label: 'Gallery',
          ),
        ),
      ],
    );
  }

  Widget _buildProcessingCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.accent.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: AppColors.accent.withOpacity(0.08),
            blurRadius: 16,
          ),
        ],
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: AppColors.accent,
              backgroundColor: AppColors.border,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              _processingStep,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildResults() {
    return [
      if (_result!.warningMessage != null) ...[
        _WarningBanner(message: _result!.warningMessage!),
        const SizedBox(height: 12),
      ],
      if (_result!.hasAiResult) ...[
        _PrescriptionCard(result: _result!.prescriptionResult!),
        const SizedBox(height: 12),
      ],
      _RawTextCard(result: _result!),
      const SizedBox(height: 10),
      _BlocksDebugView(blocks: _result!.blocks),
    ];
  }
}

// ── Shared Widgets ─────────────────────────────────────────────────────────

class _OutlineBtn extends StatelessWidget {
  final VoidCallback? onPressed;
  final IconData icon;
  final String label;
  const _OutlineBtn(
      {required this.onPressed, required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.accentLight,
        side: const BorderSide(color: AppColors.accent, width: 1.5),
        shape:
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        padding: const EdgeInsets.symmetric(vertical: 16),
        textStyle: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final double score;
  const _StatusPill({required this.score});

  @override
  Widget build(BuildContext context) {
    final pct = (score * 100).round();
    final color = score > 0.7
        ? AppColors.success
        : score > 0.4
        ? AppColors.warning
        : AppColors.error;
    final label = score > 0.7 ? 'Good' : score > 0.4 ? 'Fair' : 'Poor';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            '$label $pct%',
            style: TextStyle(
                color: color, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _WarningBanner extends StatelessWidget {
  final String message;
  const _WarningBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.warning.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.warning.withOpacity(0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded,
              color: AppColors.warning, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message,
                style: const TextStyle(
                    color: AppColors.warning, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

// ── LAYER 2: Prescription Card ─────────────────────────────────────────────

class _PrescriptionCard extends StatelessWidget {
  final PrescriptionResult result;
  const _PrescriptionCard({required this.result});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppColors.accentGlow,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.auto_awesome_rounded,
                  color: AppColors.accentLight, size: 16),
            ),
            const SizedBox(width: 10),
            const Text(
              'AI Interpretation',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 16,
                letterSpacing: -0.3,
              ),
            ),
            const Spacer(),
            _ModeBadge(isAi: result.isAiAssisted),
          ],
        ),
        const SizedBox(height: 14),
        if (result.medicines.isEmpty)
          _EmptyMedicines()
        else
          ...result.medicines.map((m) => _MedicineCard(medicine: m)),
        if (result.patientInstructions != null) ...[
          const SizedBox(height: 8),
          _InfoChip(
            icon: Icons.info_outline_rounded,
            label: 'Instructions',
            text: result.patientInstructions!,
            color: AppColors.accent,
          ),
        ],
        if (result.hasWarnings) ...[
          const SizedBox(height: 8),
          ...result.interpretationWarnings.map((w) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: _InfoChip(
              icon: Icons.warning_amber_rounded,
              label: 'Note',
              text: w,
              color: AppColors.warning,
            ),
          )),
        ],
      ],
    );
  }
}

class _ModeBadge extends StatelessWidget {
  final bool isAi;
  const _ModeBadge({required this.isAi});

  @override
  Widget build(BuildContext context) {
    final color = isAi ? AppColors.accent : AppColors.warning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(
        isAi ? '✦ AI + DB' : 'DB only',
        style: TextStyle(
            fontSize: 11, color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _EmptyMedicines extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: const Center(
        child: Text(
          'No medicines identified.\nTry a clearer photo.',
          style: TextStyle(color: AppColors.textMuted, fontSize: 13),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
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
    if (widget.medicine.isHighConfidence) return AppColors.success;
    if (widget.medicine.isMediumConfidence) return AppColors.warning;
    return AppColors.error;
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.medicine;
    return GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: _confidenceColor.withOpacity(0.25), width: 1.2),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        margin: const EdgeInsets.only(right: 10, top: 2),
                        decoration: BoxDecoration(
                          color: _confidenceColor,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: _confidenceColor.withOpacity(0.4),
                              blurRadius: 6,
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Text(
                          m.name,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.3,
                          ),
                        ),
                      ),
                      Text(
                        '${(m.confidence * 100).round()}%',
                        style: TextStyle(
                          color: _confidenceColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        _expanded
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        color: AppColors.textMuted,
                        size: 18,
                      ),
                    ],
                  ),
                  if (m.fullDosage.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      m.fullDosage,
                      style: const TextStyle(
                        color: AppColors.accentLight,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                  if (m.specialInstructions != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      m.specialInstructions!,
                      style: const TextStyle(
                          color: AppColors.textMuted, fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
            if (_expanded) ...[
              Container(height: 1, color: AppColors.border),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                child: Column(
                  children: [
                    if (m.rawOcr.isNotEmpty) _DetailRow('OCR text', m.rawOcr),
                    if (m.dose.isNotEmpty) _DetailRow('Dose', m.dose),
                    if (m.frequency.isNotEmpty)
                      _DetailRow('Frequency', m.frequency),
                    if (m.duration.isNotEmpty)
                      _DetailRow('Duration', m.duration),
                    if (m.route != null) _DetailRow('Route', m.route!),
                    if (m.correctionsMade.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(
                            width: 84,
                            child: Text('Corrections',
                                style: TextStyle(
                                    color: AppColors.textMuted,
                                    fontSize: 12)),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: m.correctionsMade
                                  .map((c) => Text('• $c',
                                  style: const TextStyle(
                                      color: AppColors.textMuted,
                                      fontSize: 12)))
                                  .toList(),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _DetailRow(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 84,
          child: Text(label,
              style: const TextStyle(
                  color: AppColors.textMuted, fontSize: 12)),
        ),
        Expanded(
          child: Text(value,
              style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500)),
        ),
      ],
    ),
  );
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String text;
  final Color color;
  const _InfoChip(
      {required this.icon,
        required this.label,
        required this.text,
        required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: TextStyle(
                    color: color.withOpacity(0.85), fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

// ── LAYER 1: Raw OCR + Blocks ──────────────────────────────────────────────

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
    final raw = widget.result.rawText;
    final preview = raw.isEmpty
        ? '(no text detected)'
        : raw.split('\n').take(2).join(' ').substring(
        0, raw.length > 55 ? 55 : raw.length);

    return GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.text_fields_rounded,
                    size: 15, color: AppColors.textMuted),
                const SizedBox(width: 8),
                const Text(
                  'Raw OCR Text',
                  style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3),
                ),
                const Spacer(),
                Text(
                  '${widget.result.processingMs}ms',
                  style: const TextStyle(
                      color: AppColors.textMuted, fontSize: 11),
                ),
                const SizedBox(width: 6),
                Icon(
                  _expanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  color: AppColors.textMuted,
                  size: 16,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _expanded
                  ? (raw.isEmpty ? '(no text detected)' : raw)
                  : '$preview…',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                height: 1.5,
                fontFamily: 'monospace',
              ),
              maxLines: _expanded ? null : 2,
              overflow:
              _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
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
    if (widget.blocks.isEmpty) return const SizedBox();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Text(
                  '${widget.blocks.length} text blocks detected',
                  style: const TextStyle(
                      color: AppColors.textMuted, fontSize: 12),
                ),
                const Spacer(),
                Icon(
                  _expanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  color: AppColors.textMuted,
                  size: 16,
                ),
              ],
            ),
          ),
        ),
        if (_expanded)
          Container(
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            padding: const EdgeInsets.all(12),
            child: Column(
              children: widget.blocks.map((b) {
                final conf = (b.confidence * 100).round();
                final color = b.confidence > 0.7
                    ? AppColors.success
                    : b.confidence > 0.4
                    ? AppColors.warning : AppColors.error;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 36,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '$conf%',
                          style: TextStyle(
                              fontSize: 10,
                              color: color,
                              fontWeight: FontWeight.w600),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(b.text,
                            style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12,
                                height: 1.4)),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
      ],
    );
  }
}
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'services/ocr_service.dart';
import 'models/ocr_result.dart';

void main() {
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
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
      imageQuality: 95,        // Keep high quality for OCR accuracy
      preferredCameraDevice: CameraDevice.rear,
    );
    if (picked == null) return;

    // Show crop UI so user can straighten the prescription
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
          hideBottomControls: false,
        ),
      ],
    );
    if (cropped == null) return;

    setState(() {
      _originalImage = File(cropped.path);
      _result = null;
      _isProcessing = true;
      _processingStep = 'Enhancing image...';
    });

    // Small delay so the UI updates before we start heavy processing
    await Future.delayed(const Duration(milliseconds: 80));

    setState(() => _processingStep = 'Recognising text...');

    try {
      final result = await _ocrService.processImage(_originalImage!);
      setState(() {
        _result = result;
        _isProcessing = false;
      });
    } catch (e) {
      setState(() {
        _isProcessing = false;
      });
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
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              const Text(
                'Scan doctor handwriting with AI assistance',
                style: TextStyle(color: Colors.white60, fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),

              // Image preview
              if (_originalImage != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.file(_originalImage!, height: 220, fit: BoxFit.cover),
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
                    child: Icon(Icons.medication_rounded, size: 64, color: Color(0xFF4A90D9)),
                  ),
                ),

              const SizedBox(height: 20),

              // Action buttons
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isProcessing ? null : () => _pickAndProcess(ImageSource.camera),
                      icon: const Icon(Icons.camera_alt),
                      label: const Text('Take Photo'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isProcessing ? null : () => _pickAndProcess(ImageSource.gallery),
                      icon: const Icon(Icons.upload),
                      label: const Text('Upload'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF4A90D9),
                        side: const BorderSide(color: Color(0xFF4A90D9)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                        width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF4A90D9)),
                      ),
                      const SizedBox(width: 16),
                      Text(_processingStep, style: const TextStyle(color: Colors.white70)),
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

// ── Quality badge ──────────────────────────────────────────────────────────

class _QualityBadge extends StatelessWidget {
  final double score;
  const _QualityBadge({required this.score});

  @override
  Widget build(BuildContext context) {
    final pct = (score * 100).round();
    final color = score > 0.7 ? Colors.green : score > 0.4 ? Colors.orange : Colors.red;
    final label = score > 0.7 ? 'Good quality' : score > 0.4 ? 'Acceptable' : 'Poor quality';
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withOpacity(0.4)),
          ),
          child: Text(
            '$label  $pct%',
            style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

// ── Warning banner ─────────────────────────────────────────────────────────

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
          const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: const TextStyle(color: Colors.orange, fontSize: 13))),
        ],
      ),
    );
  }
}

// ── Raw text card ──────────────────────────────────────────────────────────

class _RawTextCard extends StatelessWidget {
  final OcrResult result;
  const _RawTextCard({required this.result});

  @override
  Widget build(BuildContext context) {
    return Container(
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
              const Text('Raw OCR text', style: TextStyle(color: Colors.white60, fontSize: 12)),
              Text('${result.processingMs}ms', style: const TextStyle(color: Colors.white30, fontSize: 11)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            result.rawText.isEmpty ? '(no text detected)' : result.rawText,
            style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.6),
          ),
        ],
      ),
    );
  }
}

// ── Blocks debug view (shows per-block confidence) ─────────────────────────

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
                  style: const TextStyle(color: Colors.white30, fontSize: 12),
                ),
                const Spacer(),
                Icon(_expanded ? Icons.expand_less : Icons.expand_more, color: Colors.white30, size: 16),
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
                      color: b.confidence > 0.7 ? Colors.green : b.confidence > 0.4 ? Colors.orange : Colors.red,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(b.text, style: const TextStyle(color: Colors.white54, fontSize: 12, height: 1.4)),
                ),
              ],
            ),
          )),
      ],
    );
  }
}
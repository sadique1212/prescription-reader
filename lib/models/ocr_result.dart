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
  final double imageQualityScore; // 0.0 to 1.0
  final int processingMs;
  final String? warningMessage; // shown to user if quality is low

  OcrResult({
    required this.rawText,
    required this.blocks,
    required this.imageQualityScore,
    required this.processingMs,
    this.warningMessage,
  });

  bool get isUsable => imageQualityScore > 0.3 && rawText.trim().isNotEmpty;
}
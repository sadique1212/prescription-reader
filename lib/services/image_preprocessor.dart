// lib/services/image_preprocessor.dart
// FIXED: dart:ui decode runs on main isolate first,
// then heavy CPU work (CLAHE + Sauvola) runs in compute() isolate.

import 'dart:io';
import 'dart:typed_data';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';

class PreprocessResult {
  final File processedFile;
  final double qualityScore;
  final String? warning;

  PreprocessResult({
    required this.processedFile,
    required this.qualityScore,
    this.warning,
  });
}

// Data passed into the compute() isolate — plain Dart types only, no dart:ui
class _IsolatePayload {
  final Uint8List pixels;
  final int width;
  final int height;
  final String outputPath;

  _IsolatePayload({
    required this.pixels,
    required this.width,
    required this.height,
    required this.outputPath,
  });
}

class _IsolateResult {
  final double qualityScore;
  final String? warning;

  _IsolateResult({required this.qualityScore, this.warning});
}

class ImagePreprocessor {
  /// Full pipeline. dart:ui decode happens here (main isolate),
  /// then heavy CPU work is offloaded via compute().
  static Future<PreprocessResult> process(File inputFile) async {
    final bytes = await inputFile.readAsBytes();

    // ── Step 1: Decode image on main isolate (dart:ui is available here) ──
    final decoded = await _decodeImage(bytes);
    if (decoded == null) {
      return PreprocessResult(
        processedFile: inputFile,
        qualityScore: 0.3,
        warning: 'Could not decode image. Using original.',
      );
    }

    // ── Step 2: Prepare output path ────────────────────────────────────
    final tempDir = Directory.systemTemp;
    final outPath =
        '${tempDir.path}/rx_${DateTime.now().millisecondsSinceEpoch}.bmp';

    // ── Step 3: Offload CPU-heavy work to isolate ──────────────────────
    final payload = _IsolatePayload(
      pixels: decoded.pixels,
      width: decoded.width,
      height: decoded.height,
      outputPath: outPath,
    );

    final result = await compute(_heavyProcessing, payload);

    return PreprocessResult(
      processedFile: File(outPath),
      qualityScore: result.qualityScore,
      warning: result.warning,
    );
  }

  // ── Runs in compute() isolate — NO dart:ui allowed here ───────────────
  static Future<_IsolateResult> _heavyProcessing(_IsolatePayload p) async {
    final pixels = p.pixels;
    final w = p.width;
    final h = p.height;

    // Quality scoring
    final blurScore = _computeBlurScore(pixels, w, h);
    final brightnessScore = _computeBrightnessScore(pixels, w, h);
    final qualityScore =
    (blurScore * 0.6 + brightnessScore * 0.4).clamp(0.0, 1.0);

    String? warning;
    if (blurScore < 0.3) {
      warning = 'Image appears blurry. Hold camera steady and retake.';
    } else if (brightnessScore < 0.25) {
      warning = 'Image too dark. Move to better light and retake.';
    } else if (brightnessScore > 0.92) {
      warning = 'Image overexposed. Avoid direct flash on white paper.';
    }

    // Grayscale
    final gray = _toGrayscale(pixels, w, h);

    // Adaptive contrast (CLAHE-style)
    final enhanced = _adaptiveContrastEnhance(gray, w, h);

    // Adaptive threshold (Sauvola) — window size adaptive to image resolution
    final windowSize = _adaptiveWindowSize(w, h);
    final thresholded = _adaptiveThreshold(enhanced, w, h, windowSize);

    // Write BMP
    final rgba = _grayscaleToRgba(thresholded, w, h);
    final bmpBytes = _encodeBmp(rgba, w, h);
    await File(p.outputPath).writeAsBytes(bmpBytes);

    return _IsolateResult(qualityScore: qualityScore, warning: warning);
  }

  // ── Adaptive window size based on resolution ──────────────────────────
  // Small images need smaller windows to avoid blurring thin text strokes
  static int _adaptiveWindowSize(int w, int h) {
    final megapixels = (w * h) / 1000000.0;
    if (megapixels > 8) return 35;
    if (megapixels > 4) return 25;
    if (megapixels > 1) return 17;
    return 11;
  }

  // ── Grayscale ─────────────────────────────────────────────────────────
  static Uint8List _toGrayscale(Uint8List rgba, int w, int h) {
    final gray = Uint8List(w * h);
    for (int i = 0; i < w * h; i++) {
      final r = rgba[i * 4];
      final g = rgba[i * 4 + 1];
      final b = rgba[i * 4 + 2];
      gray[i] = (0.299 * r + 0.587 * g + 0.114 * b).round().clamp(0, 255);
    }
    return gray;
  }

  // ── CLAHE-style adaptive contrast ────────────────────────────────────
  static Uint8List _adaptiveContrastEnhance(Uint8List gray, int w, int h) {
    const tileSize = 64;
    final out = Uint8List.fromList(gray);
    final tilesX = (w / tileSize).ceil();
    final tilesY = (h / tileSize).ceil();

    for (int ty = 0; ty < tilesY; ty++) {
      for (int tx = 0; tx < tilesX; tx++) {
        final x0 = tx * tileSize;
        final y0 = ty * tileSize;
        final x1 = math.min(x0 + tileSize, w);
        final y1 = math.min(y0 + tileSize, h);

        final hist = List<int>.filled(256, 0);
        for (int y = y0; y < y1; y++) {
          for (int x = x0; x < x1; x++) {
            hist[gray[y * w + x]]++;
          }
        }

        final clipLimit = ((x1 - x0) * (y1 - y0) * 0.02).round();
        int excess = 0;
        for (int i = 0; i < 256; i++) {
          if (hist[i] > clipLimit) {
            excess += hist[i] - clipLimit;
            hist[i] = clipLimit;
          }
        }
        final redistrib = excess ~/ 256;
        for (int i = 0; i < 256; i++) hist[i] += redistrib;

        final lut = List<int>.filled(256, 0);
        int cdf = 0;
        final tilePixels = (x1 - x0) * (y1 - y0);
        for (int i = 0; i < 256; i++) {
          cdf += hist[i];
          lut[i] = ((cdf / tilePixels) * 255).round().clamp(0, 255);
        }

        for (int y = y0; y < y1; y++) {
          for (int x = x0; x < x1; x++) {
            out[y * w + x] = lut[gray[y * w + x]];
          }
        }
      }
    }
    return out;
  }

  // ── Sauvola adaptive threshold ────────────────────────────────────────
  static Uint8List _adaptiveThreshold(
      Uint8List gray, int w, int h, int windowSize) {
    const k = 0.15;
    const r = 128.0;
    final out = Uint8List(w * h);
    final half = windowSize ~/ 2;

    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final x0 = math.max(0, x - half);
        final y0 = math.max(0, y - half);
        final x1 = math.min(w - 1, x + half);
        final y1 = math.min(h - 1, y + half);

        double sum = 0;
        double sumSq = 0;
        int count = 0;

        for (int ny = y0; ny <= y1; ny++) {
          for (int nx = x0; nx <= x1; nx++) {
            final v = gray[ny * w + nx].toDouble();
            sum += v;
            sumSq += v * v;
            count++;
          }
        }

        final mean = sum / count;
        final variance = (sumSq / count) - (mean * mean);
        final stddev = variance > 0 ? math.sqrt(variance) : 0.0;
        final threshold = mean * (1.0 + k * ((stddev / r) - 1.0));
        out[y * w + x] = gray[y * w + x] > threshold ? 255 : 0;
      }
    }
    return out;
  }

  // ── Quality scoring ───────────────────────────────────────────────────
  static double _computeBlurScore(Uint8List rgba, int w, int h) {
    if (w < 3 || h < 3) return 0.0;
    double variance = 0;
    int count = 0;
    for (int y = 1; y < h - 1; y++) {
      for (int x = 1; x < w - 1; x++) {
        final i = (y * w + x) * 4;
        final center = rgba[i].toDouble();
        final lap = (4 * center
            - rgba[((y - 1) * w + x) * 4]
            - rgba[((y + 1) * w + x) * 4]
            - rgba[(y * w + (x - 1)) * 4]
            - rgba[(y * w + (x + 1)) * 4]);
        variance += lap * lap;
        count++;
      }
    }
    variance /= count;
    return (variance / 500.0).clamp(0.0, 1.0);
  }

  static double _computeBrightnessScore(Uint8List rgba, int w, int h) {
    double total = 0;
    final pixels = w * h;
    for (int i = 0; i < pixels; i++) {
      total += (0.299 * rgba[i * 4] +
          0.587 * rgba[i * 4 + 1] +
          0.114 * rgba[i * 4 + 2]);
    }
    return ((total / pixels) / 255.0).clamp(0.0, 1.0);
  }

  // ── Helpers ───────────────────────────────────────────────────────────
  static Uint8List _grayscaleToRgba(Uint8List gray, int w, int h) {
    final rgba = Uint8List(w * h * 4);
    for (int i = 0; i < w * h; i++) {
      rgba[i * 4] = gray[i];
      rgba[i * 4 + 1] = gray[i];
      rgba[i * 4 + 2] = gray[i];
      rgba[i * 4 + 3] = 255;
    }
    return rgba;
  }

  static Uint8List _encodeBmp(Uint8List rgba, int w, int h) {
    final rowSize = ((w * 3 + 3) ~/ 4) * 4;
    final dataSize = rowSize * h;
    final fileSize = 54 + dataSize;
    final bmp = Uint8List(fileSize);

    void writeInt16(int offset, int v) {
      bmp[offset] = v & 0xff;
      bmp[offset + 1] = (v >> 8) & 0xff;
    }

    void writeInt32(int offset, int v) {
      bmp[offset] = v & 0xff;
      bmp[offset + 1] = (v >> 8) & 0xff;
      bmp[offset + 2] = (v >> 16) & 0xff;
      bmp[offset + 3] = (v >> 24) & 0xff;
    }

    bmp[0] = 0x42;
    bmp[1] = 0x4D;
    writeInt32(2, fileSize);
    writeInt32(10, 54);
    writeInt32(14, 40);
    writeInt32(18, w);
    writeInt32(22, -h);
    writeInt16(26, 1);
    writeInt16(28, 24);
    writeInt32(34, dataSize);

    int outIdx = 54;
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final i = (y * w + x) * 4;
        final a = rgba[i + 3] / 255.0;
        bmp[outIdx++] = (rgba[i + 2] * a + 255 * (1 - a)).round();
        bmp[outIdx++] = (rgba[i + 1] * a + 255 * (1 - a)).round();
        bmp[outIdx++] = (rgba[i] * a + 255 * (1 - a)).round();
      }
      outIdx += rowSize - w * 3;
    }
    return bmp;
  }
}

// ── dart:ui image decoder — runs on main isolate only ────────────────────
class _DecodedImage {
  final Uint8List pixels;
  final int width;
  final int height;
  _DecodedImage(this.pixels, this.width, this.height);
}

Future<_DecodedImage?> _decodeImage(Uint8List bytes) async {
  try {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final byteData =
    await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (byteData == null) return null;
    return _DecodedImage(
      byteData.buffer.asUint8List(),
      frame.image.width,
      frame.image.height,
    );
  } catch (_) {
    return null;
  }
}
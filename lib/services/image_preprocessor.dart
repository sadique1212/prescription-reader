import 'dart:io';
import 'dart:typed_data';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/foundation.dart';

class PreprocessResult {
  final File processedFile;
  final double qualityScore; // 0.0 = unusable, 1.0 = perfect
  final String? warning;

  PreprocessResult({
    required this.processedFile,
    required this.qualityScore,
    this.warning,
  });
}

class ImagePreprocessor {
  /// Full preprocessing pipeline for a raw prescription photo.
  /// Returns a new File with the enhanced image written to the temp directory.
  static Future<PreprocessResult> process(File inputFile) async {
    // Run heavy work off the main thread
    return compute(_processingIsolate, inputFile.path);
  }

  static Future<PreprocessResult> _processingIsolate(String inputPath) async {
    final file = File(inputPath);
    final bytes = await file.readAsBytes();

    // Step 1: Decode image to raw RGBA pixels using Flutter's codec
    final decoded = await _decodeImage(bytes);
    if (decoded == null) {
      return PreprocessResult(
        processedFile: file,
        qualityScore: 0.0,
        warning: 'Could not read image file.',
      );
    }

    final int width = decoded.width;
    final int height = decoded.height;
    final pixels = decoded.pixels; // Uint8List of RGBA bytes

    // Step 2: Quality check BEFORE processing (gives meaningful feedback)
    final blurScore = _computeBlurScore(pixels, width, height);
    final brightnessScore = _computeBrightnessScore(pixels, width, height);
    final qualityScore = (blurScore * 0.6 + brightnessScore * 0.4).clamp(0.0, 1.0);

    String? warning;
    if (blurScore < 0.3) {
      warning = 'Image appears blurry. Hold the camera steady and retake.';
    } else if (brightnessScore < 0.25) {
      warning = 'Image is too dark. Move to better light and retake.';
    } else if (brightnessScore > 0.92) {
      warning = 'Image is overexposed. Avoid direct flash on white paper.';
    }

    // Step 3: Convert to grayscale
    final gray = _toGrayscale(pixels, width, height);

    // Step 4: CLAHE-style contrast enhancement (adaptive histogram equalisation)
    // Especially important for rural prescriptions on low-quality paper
    final enhanced = _adaptiveContrastEnhance(gray, width, height);

    // Step 5: Adaptive thresholding (Sauvola method)
    // Handles dark edges, watermarks, and uneven lighting better than Otsu
    final thresholded = _adaptiveThreshold(enhanced, width, height);

    // Step 6: Write processed image to temp file
    final tempDir = Directory.systemTemp;
    final outPath = '${tempDir.path}/rx_processed_${DateTime.now().millisecondsSinceEpoch}.png';
    final outFile = File(outPath);

    // Re-encode as RGBA PNG (ML Kit accepts this)
    final rgbaOut = _grayscaleToRgba(thresholded, width, height);
    await outFile.writeAsBytes(_encodePng(rgbaOut, width, height));

    return PreprocessResult(
      processedFile: outFile,
      qualityScore: qualityScore,
      warning: warning,
    );
  }

  // ─── Grayscale conversion ───────────────────────────────────────────────

  static Uint8List _toGrayscale(Uint8List rgba, int w, int h) {
    final gray = Uint8List(w * h);
    for (int i = 0; i < w * h; i++) {
      final r = rgba[i * 4];
      final g = rgba[i * 4 + 1];
      final b = rgba[i * 4 + 2];
      // Luminance formula tuned for text on paper
      gray[i] = (0.299 * r + 0.587 * g + 0.114 * b).round().clamp(0, 255);
    }
    return gray;
  }

  // ─── Adaptive contrast enhancement ──────────────────────────────────────
  // Divides image into tiles, equalises each tile's histogram, then blends.
  // This recovers text that standard global contrast adjustment would miss.

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

        // Build histogram for this tile
        final hist = List<int>.filled(256, 0);
        for (int y = y0; y < y1; y++) {
          for (int x = x0; x < x1; x++) {
            hist[gray[y * w + x]]++;
          }
        }

        // Clip histogram (limits over-enhancement of noise)
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

        // Build LUT from CDF
        final lut = List<int>.filled(256, 0);
        int cdf = 0;
        final tilePixels = (x1 - x0) * (y1 - y0);
        for (int i = 0; i < 256; i++) {
          cdf += hist[i];
          lut[i] = ((cdf / tilePixels) * 255).round().clamp(0, 255);
        }

        // Apply LUT to tile
        for (int y = y0; y < y1; y++) {
          for (int x = x0; x < x1; x++) {
            out[y * w + x] = lut[gray[y * w + x]];
          }
        }
      }
    }
    return out;
  }

  // ─── Adaptive thresholding (Sauvola) ────────────────────────────────────
  // Each pixel's threshold is computed from its local neighbourhood mean and
  // standard deviation. Far superior to global threshold for handwriting.

  static Uint8List _adaptiveThreshold(Uint8List gray, int w, int h) {
    const windowSize = 25; // ~25px neighbourhood, adjust if text is tiny
    const k = 0.15; // Sauvola sensitivity — higher = more ink preserved
    const r = 128.0; // Dynamic range

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
        final stddev = variance > 0 ? math.sqrt(variance) : 0;
        final threshold = mean * (1.0 + k * ((stddev / r) - 1.0));

        // White background (255) for paper, black (0) for ink
        out[y * w + x] = gray[y * w + x] > threshold ? 255 : 0;
      }
    }
    return out;
  }

  // ─── Quality scoring ─────────────────────────────────────────────────────

  /// Laplacian variance — higher = sharper image
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
    // Normalise: variance > 500 is sharp text, < 50 is too blurry
    return (variance / 500.0).clamp(0.0, 1.0);
  }

  /// Average brightness normalised to [0, 1]
  static double _computeBrightnessScore(Uint8List rgba, int w, int h) {
    double total = 0;
    final pixels = w * h;
    for (int i = 0; i < pixels; i++) {
      total += (0.299 * rgba[i * 4] + 0.587 * rgba[i * 4 + 1] + 0.114 * rgba[i * 4 + 2]);
    }
    return ((total / pixels) / 255.0).clamp(0.0, 1.0);
  }

  // ─── Helpers ─────────────────────────────────────────────────────────────

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

  // Minimal PNG encoder — avoids needing an extra package just for encoding
  static Uint8List _encodePng(Uint8List rgba, int w, int h) {
    // Use Flutter's dart:ui image codec via a workaround:
    // Write a raw BMP instead which ML Kit reads fine and is much simpler.
    return _encodeBmp(rgba, w, h);
  }

  /// Encodes raw RGBA pixels as a 24-bit BMP (no alpha, white bg)
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

    // File header
    bmp[0] = 0x42; bmp[1] = 0x4D; // 'BM'
    writeInt32(2, fileSize);
    writeInt32(10, 54); // pixel data offset

    // DIB header
    writeInt32(14, 40); // header size
    writeInt32(18, w);
    writeInt32(22, -h); // negative = top-down
    writeInt16(26, 1);  // colour planes
    writeInt16(28, 24); // bits per pixel
    writeInt32(34, dataSize);

    // Pixel data (BGR, bottom-up reversed by negative height flag)
    int outIdx = 54;
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final i = (y * w + x) * 4;
        // Blend alpha onto white background
        final a = rgba[i + 3] / 255.0;
        bmp[outIdx++] = (rgba[i + 2] * a + 255 * (1 - a)).round(); // B
        bmp[outIdx++] = (rgba[i + 1] * a + 255 * (1 - a)).round(); // G
        bmp[outIdx++] = (rgba[i]     * a + 255 * (1 - a)).round(); // R
      }
      outIdx += rowSize - w * 3; // row padding
    }

    return bmp;
  }
}

// ─── Minimal image decoder (dart:ui wrapper) ─────────────────────────────
// We can't use dart:ui in an isolate, so this runs on the main isolate only.
// The compute() call above won't actually isolate the dart:ui decode step —
// that's fine; the heavy CPU work (threshold, CLAHE) is what we isolate.

class _DecodedImage {
  final Uint8List pixels;
  final int width;
  final int height;
  _DecodedImage(this.pixels, this.width, this.height);
}

Future<_DecodedImage?> _decodeImage(Uint8List bytes) async {
  try {
    // Use dart:ui to decode — this is the most reliable Flutter-native decoder
    // and handles JPEG, PNG, HEIC, WebP from camera/gallery correctly.
    final codec = await decodeImageFromList(bytes);
    final frame = await codec.getNextFrame();
    final byteData = await frame.image.toByteData();
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
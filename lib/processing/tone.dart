import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'stack_engine.dart';

/// Brightens a stacked night frame. Stacking has already removed most of
/// the noise, so we can safely push exposure: the 99th percentile of
/// luminance is mapped to near white (gain capped at [maxGain]) and a
/// gentle gamma lifts the shadows.
RgbImage nightTone(RgbImage src, {double maxGain = 4.0, double gamma = 0.85}) {
  final d = src.data;
  final hist = List<int>.filled(256, 0);
  for (var i = 0; i < d.length; i += 3) {
    hist[(d[i] * 77 + d[i + 1] * 150 + d[i + 2] * 29) >> 8]++;
  }
  final total = d.length ~/ 3;
  var acc = 0;
  var p99 = 255;
  for (var v = 0; v < 256; v++) {
    acc += hist[v];
    if (acc >= total * 0.99) {
      p99 = v;
      break;
    }
  }
  final gain = math.min(maxGain, 245 / math.max(p99, 1));
  final lut = Uint8List(256);
  for (var v = 0; v < 256; v++) {
    final x = math.min(1.0, v * gain / 255);
    lut[v] = (math.pow(x, gamma) * 255).round().clamp(0, 255);
  }
  final out = Uint8List(d.length);
  for (var i = 0; i < d.length; i++) {
    out[i] = lut[d[i]];
  }
  return RgbImage(src.width, src.height, out);
}

/// Converts to an `image` package picture, rotated upright.
img.Image toImage(RgbImage src, int rotationDegrees) {
  final im = img.Image.fromBytes(
    width: src.width,
    height: src.height,
    bytes: src.data.buffer,
    numChannels: 3,
  );
  if (rotationDegrees % 360 == 0) return im;
  return img.copyRotate(im, angle: rotationDegrees);
}

/// Small RGBA copy for on-screen live preview.
(Uint8List, int, int) previewRgba(RgbImage src, int maxWidth) {
  final step = math.max(1, (src.width / maxWidth).ceil());
  final w = src.width ~/ step, h = src.height ~/ step;
  final out = Uint8List(w * h * 4);
  var o = 0;
  for (var y = 0; y < h; y++) {
    var p = (y * step * src.width) * 3;
    for (var x = 0; x < w; x++) {
      out[o++] = src.data[p];
      out[o++] = src.data[p + 1];
      out[o++] = src.data[p + 2];
      out[o++] = 255;
      p += step * 3;
    }
  }
  return (out, w, h);
}

import 'dart:math' as math;
import 'dart:typed_data';

/// How successive camera frames are combined into one picture.
///
/// These are the building blocks behind the creative modes. Each one is a
/// classic "computational photography" trick:
///
/// * [lighten] keeps the brightest value each pixel has ever seen. A light
///   moved through a dark scene leaves a permanent trail while the dark
///   background stays put. Used for light painting, car light trails and
///   star trails.
/// * [average] is a mean of all frames: a digital long exposure. Moving
///   water turns silky, crowds blur away, and sensor noise is averaged out
///   (night mode).
/// * [median] takes the per pixel median, which removes anything that is
///   only present in a minority of frames (people walking through a
///   landscape).
/// * [echo] is a decaying multiple exposure: motion leaves a fading trail of
///   ghosts behind it.
/// * [slitScan] builds the picture from a narrow vertical slit of each frame
///   placed side by side (a "photo finish" or time-slice image).
enum StackBlend { lighten, average, median, echo, slitScan }

/// A single camera frame in 8-bit, 4 bytes per pixel layout.
class RawFrame {
  RawFrame({
    required this.bytes,
    required this.width,
    required this.height,
    required this.bytesPerRow,
    required this.isBgra,
  });

  final Uint8List bytes;
  final int width;
  final int height;
  final int bytesPerRow;

  /// iOS delivers BGRA, Android (CameraX) delivers RGBA.
  final bool isBgra;
}

/// Options that shape a stacking session.
class StackOptions {
  const StackOptions({
    required this.blend,
    this.align = false,
    this.maxFrames = 0,
    this.echoDecay = 0.85,
    this.slitWidth = 4,
    this.lightenThreshold = 0,
    this.slitDisplayVertical = true,
  });

  final StackBlend blend;

  /// Register each frame to the first one before blending. Helps handheld
  /// night shots, costs CPU.
  final bool align;

  /// Stop accepting frames after this many. 0 means unlimited.
  final int maxFrames;

  /// For [StackBlend.echo]: how much of the previous result survives each
  /// new frame (0..1).
  final double echoDecay;

  /// For [StackBlend.slitScan]: how many columns each frame contributes.
  final int slitWidth;

  /// For [StackBlend.lighten]: luminance (0..255) a pixel must exceed to
  /// be allowed to brighten the result. Raising it stops the background
  /// from slowly brightening and keeps only real light sources.
  final int lightenThreshold;

  /// For [StackBlend.slitScan]: true takes a vertical slit as the user sees
  /// the screen and sweeps it left to right; false takes a horizontal slit
  /// and sweeps it top to bottom. The engine maps this onto the sensor's
  /// own axes using the frame rotation.
  final bool slitDisplayVertical;

  Map<String, Object> toMap() => {
    'blend': blend.index,
    'align': align,
    'maxFrames': maxFrames,
    'echoDecay': echoDecay,
    'slitWidth': slitWidth,
    'lightenThreshold': lightenThreshold,
    'slitDisplayVertical': slitDisplayVertical,
  };

  static StackOptions fromMap(Map<dynamic, dynamic> m) => StackOptions(
    blend: StackBlend.values[m['blend'] as int],
    align: m['align'] as bool,
    maxFrames: m['maxFrames'] as int,
    echoDecay: (m['echoDecay'] as num).toDouble(),
    slitWidth: m['slitWidth'] as int,
    lightenThreshold: m['lightenThreshold'] as int,
    slitDisplayVertical: m['slitDisplayVertical'] as bool? ?? true,
  );
}

/// An 8-bit RGB picture, row major, 3 bytes per pixel.
class RgbImage {
  RgbImage(this.width, this.height, [Uint8List? data])
    : data = data ?? Uint8List(width * height * 3);

  final int width;
  final int height;
  final Uint8List data;
}

/// Accumulates frames according to [StackOptions]. Pure Dart, no Flutter,
/// so it can run inside a background isolate and be unit tested.
class StackEngine {
  StackEngine(this.options);

  final StackOptions options;

  int _w = 0;
  int _h = 0;
  int _count = 0;

  // Per mode buffers. Only the ones the blend needs are allocated.
  Uint8List? _max; // lighten
  Uint32List? _sum; // average
  Float32List? _echo; // echo
  final List<Uint8List> _frames = []; // median
  Uint8List? _slit; // slit scan
  int _slitCursor = 0;

  // Alignment reference.
  Uint8List? _refThumb;
  int _thumbW = 0;
  int _thumbH = 0;

  /// Clockwise rotation (degrees) that turns sensor frames upright. Set
  /// before the first frame; slit-scan uses it to pick its axis.
  int rotationDegrees = 0;
  bool _slitRows = false;
  bool _slitReverse = false;

  int get frameCount => _count;
  int get width => _w;
  int get height => _h;

  bool get isFull =>
      options.maxFrames > 0 && _count >= options.maxFrames ||
      options.blend == StackBlend.slitScan &&
          _w > 0 &&
          _slitCursor >= (_slitRows ? _h : _w);

  /// Adds one frame. Frames with a different size than the first are
  /// ignored (the camera changed resolution mid capture).
  void add(RawFrame f) {
    if (isFull) return;
    if (_count == 0) _allocate(f.width, f.height);
    if (f.width != _w || f.height != _h) return;

    final rgb = _toRgb(f);
    var dx = 0, dy = 0;
    if (options.align) {
      final thumb = _thumbnail(rgb, _w, _h);
      if (_refThumb == null) {
        _refThumb = thumb;
      } else {
        final s = estimateShift(_refThumb!, thumb, _thumbW, _thumbH, 6);
        dx = s.$1 * _thumbScale;
        dy = s.$2 * _thumbScale;
      }
    }
    final src = (dx == 0 && dy == 0) ? rgb : shiftRgb(rgb, _w, _h, dx, dy);

    switch (options.blend) {
      case StackBlend.lighten:
        _addLighten(src);
      case StackBlend.average:
        final sum = _sum!;
        for (var i = 0; i < src.length; i++) {
          sum[i] += src[i];
        }
      case StackBlend.median:
        _frames.add(src);
      case StackBlend.echo:
        final e = _echo!;
        final d = options.echoDecay;
        if (_count == 0) {
          for (var i = 0; i < src.length; i++) {
            e[i] = src[i].toDouble();
          }
        } else {
          // Blend toward the brighter of (faded history, new frame) so
          // moving subjects leave fading copies of themselves.
          for (var i = 0; i < src.length; i++) {
            final faded = e[i] * d + src[i] * (1 - d);
            final v = src[i].toDouble();
            e[i] = faded > v ? faded : v;
          }
        }
      case StackBlend.slitScan:
        _addSlit(src);
    }
    _count++;
  }

  void _allocate(int w, int h) {
    _w = w;
    _h = h;
    final n = w * h * 3;
    switch (options.blend) {
      case StackBlend.lighten:
        _max = Uint8List(n);
      case StackBlend.average:
        _sum = Uint32List(n);
      case StackBlend.median:
        break;
      case StackBlend.echo:
        _echo = Float32List(n);
      case StackBlend.slitScan:
        _slit = Uint8List(n);
        final r = rotationDegrees % 360;
        final quarter = r == 90 || r == 270;
        // A slit that looks vertical on screen is a sensor row when the
        // frame is rotated a quarter turn.
        _slitRows = options.slitDisplayVertical == quarter;
        _slitReverse = r == 180 || (_slitRows && r == 90);
    }
  }

  void _addLighten(Uint8List src) {
    final m = _max!;
    final t = options.lightenThreshold;
    if (_count == 0 || t == 0) {
      for (var i = 0; i < src.length; i++) {
        if (src[i] > m[i]) m[i] = src[i];
      }
      return;
    }
    for (var i = 0; i < src.length; i += 3) {
      final r = src[i], g = src[i + 1], b = src[i + 2];
      final y = (r * 77 + g * 150 + b * 29) >> 8;
      if (y < t) continue;
      if (r > m[i]) m[i] = r;
      if (g > m[i + 1]) m[i + 1] = g;
      if (b > m[i + 2]) m[i + 2] = b;
    }
  }

  void _addSlit(Uint8List src) {
    final out = _slit!;
    final sw = options.slitWidth;
    final length = _slitRows ? _h : _w;
    final centre = length ~/ 2 - sw ~/ 2;
    for (var k = 0; k < sw && _slitCursor + k < length; k++) {
      final from = centre + k;
      final pos = _slitCursor + k;
      final to = _slitReverse ? length - 1 - pos : pos;
      if (_slitRows) {
        // Copy a whole sensor row.
        final s0 = from * _w * 3, d0 = to * _w * 3;
        out.setRange(d0, d0 + _w * 3, src, s0);
      } else {
        for (var y = 0; y < _h; y++) {
          final row = y * _w * 3;
          final s = row + from * 3, d = row + to * 3;
          out[d] = src[s];
          out[d + 1] = src[s + 1];
          out[d + 2] = src[s + 2];
        }
      }
    }
    _slitCursor += sw;
  }

  Uint8List _toRgb(RawFrame f) {
    final out = Uint8List(f.width * f.height * 3);
    final b = f.bytes;
    final rOff = f.isBgra ? 2 : 0;
    final bOff = f.isBgra ? 0 : 2;
    var o = 0;
    for (var y = 0; y < f.height; y++) {
      var p = y * f.bytesPerRow;
      for (var x = 0; x < f.width; x++) {
        out[o++] = b[p + rOff];
        out[o++] = b[p + 1];
        out[o++] = b[p + bOff];
        p += 4;
      }
    }
    return out;
  }

  int get _thumbScale => 8;

  Uint8List _thumbnail(Uint8List rgb, int w, int h) {
    final s = _thumbScale;
    _thumbW = w ~/ s;
    _thumbH = h ~/ s;
    return downsampleLuma(rgb, w, h, s);
  }

  /// Returns the current result. Cheap enough to call for live previews
  /// on small frames; the screen asks for a downscaled copy instead.
  RgbImage result() {
    if (_count == 0) return RgbImage(0, 0);
    switch (options.blend) {
      case StackBlend.lighten:
        return RgbImage(_w, _h, Uint8List.fromList(_max!));
      case StackBlend.average:
        final sum = _sum!;
        final out = Uint8List(sum.length);
        for (var i = 0; i < sum.length; i++) {
          out[i] = sum[i] ~/ _count;
        }
        return RgbImage(_w, _h, out);
      case StackBlend.median:
        return RgbImage(_w, _h, medianOf(_frames));
      case StackBlend.echo:
        final e = _echo!;
        final out = Uint8List(e.length);
        for (var i = 0; i < e.length; i++) {
          out[i] = e[i].round().clamp(0, 255);
        }
        return RgbImage(_w, _h, out);
      case StackBlend.slitScan:
        return RgbImage(_w, _h, Uint8List.fromList(_slit!));
    }
  }
}

/// Per pixel median across [frames]. All frames must have the same length.
Uint8List medianOf(List<Uint8List> frames) {
  final n = frames.length;
  final len = frames.first.length;
  final out = Uint8List(len);
  final tmp = Uint8List(n);
  for (var i = 0; i < len; i++) {
    for (var k = 0; k < n; k++) {
      tmp[k] = frames[k][i];
    }
    // Insertion sort: n is small (a few dozen frames at most).
    for (var a = 1; a < n; a++) {
      final v = tmp[a];
      var b = a - 1;
      while (b >= 0 && tmp[b] > v) {
        tmp[b + 1] = tmp[b];
        b--;
      }
      tmp[b + 1] = v;
    }
    out[i] = tmp[n >> 1];
  }
  return out;
}

/// Box-averaged luminance thumbnail, [scale] times smaller on each side.
Uint8List downsampleLuma(Uint8List rgb, int w, int h, int scale) {
  final tw = w ~/ scale, th = h ~/ scale;
  final out = Uint8List(tw * th);
  final area = scale * scale;
  for (var ty = 0; ty < th; ty++) {
    for (var tx = 0; tx < tw; tx++) {
      var acc = 0;
      for (var y = ty * scale; y < (ty + 1) * scale; y++) {
        var p = (y * w + tx * scale) * 3;
        for (var x = 0; x < scale; x++) {
          acc += (rgb[p] * 77 + rgb[p + 1] * 150 + rgb[p + 2] * 29) >> 8;
          p += 3;
        }
      }
      out[ty * tw + tx] = acc ~/ area;
    }
  }
  return out;
}

/// Finds the integer (dx, dy) that best maps [moving] onto [ref] by
/// minimising the mean absolute difference over a +/-[radius] window.
/// Returned shift is how far to move [moving] so it lines up with [ref].
(int, int) estimateShift(
  Uint8List ref,
  Uint8List moving,
  int w,
  int h,
  int radius,
) {
  var best = double.infinity;
  var bx = 0, by = 0;
  for (var dy = -radius; dy <= radius; dy++) {
    for (var dx = -radius; dx <= radius; dx++) {
      var err = 0;
      var n = 0;
      final y0 = math.max(0, dy), y1 = math.min(h, h + dy);
      final x0 = math.max(0, dx), x1 = math.min(w, w + dx);
      for (var y = y0; y < y1; y++) {
        final ro = y * w;
        final mo = (y - dy) * w - dx;
        for (var x = x0; x < x1; x++) {
          final d = ref[ro + x] - moving[mo + x];
          err += d < 0 ? -d : d;
        }
        n += x1 - x0;
      }
      if (n == 0) continue;
      final e = err / n;
      if (e < best) {
        best = e;
        bx = dx;
        by = dy;
      }
    }
  }
  return (bx, by);
}

/// Moves an RGB image by (dx, dy), repeating edge pixels into the gap.
Uint8List shiftRgb(Uint8List src, int w, int h, int dx, int dy) {
  final out = Uint8List(src.length);
  for (var y = 0; y < h; y++) {
    final sy = (y - dy).clamp(0, h - 1);
    for (var x = 0; x < w; x++) {
      final sx = (x - dx).clamp(0, w - 1);
      final s = (sy * w + sx) * 3;
      final d = (y * w + x) * 3;
      out[d] = src[s];
      out[d + 1] = src[s + 1];
      out[d + 2] = src[s + 2];
    }
  }
  return out;
}

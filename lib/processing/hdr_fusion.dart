import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'stack_engine.dart';

/// Exposure fusion (Mertens, Kautz & Van Reeth 2007).
///
/// Takes several pictures of the same scene shot at different exposures and
/// blends them so every region comes from the frame that exposed it best.
/// Blending happens in a Laplacian pyramid so the transitions are seamless,
/// with no tone mapping or radiance map needed. This is the landscape
/// mode's "HDR".
class HdrFusion {
  /// Fuses the JPEGs at [paths] into [outPath]. Runs in a background
  /// isolate. [maxSide] bounds the working resolution to keep memory sane
  /// on phones.
  static Future<String> fuseFiles(
    List<String> paths,
    String outPath, {
    int maxSide = 2048,
  }) {
    return Isolate.run(() {
      final images = <RgbImage>[];
      for (final p in paths) {
        var im = img.decodeJpg(File(p).readAsBytesSync())!;
        im = img.bakeOrientation(im);
        final long = math.max(im.width, im.height);
        if (long > maxSide) {
          im = im.width >= im.height
              ? img.copyResize(im, width: maxSide)
              : img.copyResize(im, height: maxSide);
        }
        images.add(_toRgb(im));
      }
      final aligned = alignAll(images);
      final fused = fuse(aligned);
      final out = img.Image.fromBytes(
        width: fused.width,
        height: fused.height,
        bytes: fused.data.buffer,
        numChannels: 3,
      );
      File(outPath).writeAsBytesSync(img.encodeJpg(out, quality: 95));
      return outPath;
    });
  }

  static RgbImage _toRgb(img.Image im) {
    final rgb = im.convert(numChannels: 3, format: img.Format.uint8);
    return RgbImage(
      rgb.width,
      rgb.height,
      Uint8List.fromList(rgb.getBytes(order: img.ChannelOrder.rgb)),
    );
  }

  /// Aligns every image to the middle (normally the 0 EV) one, compensating
  /// for small hand shake between bracketed shots.
  static List<RgbImage> alignAll(List<RgbImage> images) {
    final ref = images[images.length ~/ 2];
    const s = 8;
    final tw = ref.width ~/ s, th = ref.height ~/ s;
    final refThumb = _normalised(
      downsampleLuma(ref.data, ref.width, ref.height, s),
    );
    return [
      for (final im in images)
        if (identical(im, ref) ||
            im.width != ref.width ||
            im.height != ref.height)
          im
        else
          () {
            final t = _normalised(
              downsampleLuma(im.data, im.width, im.height, s),
            );
            final (dx, dy) = estimateShift(refThumb, t, tw, th, 5);
            return RgbImage(
              im.width,
              im.height,
              shiftRgb(im.data, im.width, im.height, dx * s, dy * s),
            );
          }(),
    ];
  }

  /// Bracketed frames differ in brightness, so compare them after
  /// stretching each thumbnail to the full 0..255 range.
  static Uint8List _normalised(Uint8List t) {
    var lo = 255, hi = 0;
    for (final v in t) {
      if (v < lo) lo = v;
      if (v > hi) hi = v;
    }
    final span = math.max(1, hi - lo);
    return Uint8List.fromList([for (final v in t) (v - lo) * 255 ~/ span]);
  }

  /// Core fusion. All [images] must be the same size.
  static RgbImage fuse(List<RgbImage> images) {
    final w = images.first.width, h = images.first.height;
    final n = w * h;

    // 1. Quality weight per pixel per image.
    final weights = [for (final im in images) _weight(im, w, h)];
    for (var i = 0; i < n; i++) {
      var sum = 1e-12;
      for (final wt in weights) {
        sum += wt[i];
      }
      for (final wt in weights) {
        wt[i] /= sum;
      }
    }

    final levels = math.max(
      1,
      (math.log(math.min(w, h)) / math.ln2).floor() - 3,
    );

    // 2. Blend Laplacian pyramids of the images, weighted by Gaussian
    // pyramids of the weights.
    List<_Plane>? acc;
    for (var k = 0; k < images.length; k++) {
      final wp = _gaussianPyramid(_Plane(w, h, weights[k]), levels);
      for (var c = 0; c < 3; c++) {
        final ch = Float32List(n);
        final d = images[k].data;
        for (var i = 0; i < n; i++) {
          ch[i] = d[i * 3 + c] / 255.0;
        }
        final lp = _laplacianPyramid(_Plane(w, h, ch), levels);
        acc ??= [
          for (var cc = 0; cc < 3; cc++)
            for (final l in lp) _Plane(l.w, l.h, Float32List(l.w * l.h)),
        ];
        for (var l = 0; l < levels; l++) {
          final dst = acc[c * levels + l].d;
          final src = lp[l].d;
          final wt = wp[l].d;
          for (var i = 0; i < dst.length; i++) {
            dst[i] += src[i] * wt[i];
          }
        }
      }
    }

    // 3. Collapse.
    final out = Uint8List(n * 3);
    for (var c = 0; c < 3; c++) {
      final pyr = acc!.sublist(c * levels, (c + 1) * levels);
      var cur = pyr.last;
      for (var l = levels - 2; l >= 0; l--) {
        final up = _upsample(cur, pyr[l].w, pyr[l].h);
        for (var i = 0; i < up.d.length; i++) {
          up.d[i] += pyr[l].d[i];
        }
        cur = up;
      }
      for (var i = 0; i < n; i++) {
        out[i * 3 + c] = (cur.d[i] * 255).round().clamp(0, 255);
      }
    }
    return RgbImage(w, h, out);
  }

  /// contrast x saturation x well-exposedness, as in the paper.
  static Float32List _weight(RgbImage im, int w, int h) {
    final d = im.data;
    final n = w * h;
    final gray = Float32List(n);
    for (var i = 0; i < n; i++) {
      gray[i] =
          (d[i * 3] * 0.299 + d[i * 3 + 1] * 0.587 + d[i * 3 + 2] * 0.114) /
          255.0;
    }
    final out = Float32List(n);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final i = y * w + x;
        final up = gray[(y > 0 ? y - 1 : y) * w + x];
        final dn = gray[(y < h - 1 ? y + 1 : y) * w + x];
        final lf = gray[y * w + (x > 0 ? x - 1 : x)];
        final rt = gray[y * w + (x < w - 1 ? x + 1 : x)];
        final contrast = (up + dn + lf + rt - 4 * gray[i]).abs() + 1e-3;

        final r = d[i * 3] / 255.0,
            g = d[i * 3 + 1] / 255.0,
            b = d[i * 3 + 2] / 255.0;
        final mu = (r + g + b) / 3;
        final sat =
            math.sqrt(
              ((r - mu) * (r - mu) +
                      (g - mu) * (g - mu) +
                      (b - mu) * (b - mu)) /
                  3,
            ) +
            1e-3;

        double we(double v) => math.exp(-((v - 0.5) * (v - 0.5)) / 0.08);
        final well = we(r) * we(g) * we(b);
        out[i] = contrast * sat * well;
      }
    }
    return out;
  }

  static List<_Plane> _gaussianPyramid(_Plane p, int levels) {
    final out = [p];
    for (var l = 1; l < levels; l++) {
      out.add(_downsample(out.last));
    }
    return out;
  }

  static List<_Plane> _laplacianPyramid(_Plane p, int levels) {
    final g = _gaussianPyramid(p, levels);
    final out = <_Plane>[];
    for (var l = 0; l < levels - 1; l++) {
      final up = _upsample(g[l + 1], g[l].w, g[l].h);
      final d = Float32List(g[l].d.length);
      for (var i = 0; i < d.length; i++) {
        d[i] = g[l].d[i] - up.d[i];
      }
      out.add(_Plane(g[l].w, g[l].h, d));
    }
    out.add(g.last);
    return out;
  }

  /// Blur with a [1 4 6 4 1]/16 kernel and keep every second pixel.
  static _Plane _downsample(_Plane p) {
    final w = p.w, h = p.h;
    final tmp = Float32List(w * h);
    for (var y = 0; y < h; y++) {
      final r = y * w;
      for (var x = 0; x < w; x++) {
        double at(int xx) => p.d[r + xx.clamp(0, w - 1)];
        tmp[r + x] =
            (at(x - 2) +
                4 * at(x - 1) +
                6 * at(x) +
                4 * at(x + 1) +
                at(x + 2)) /
            16;
      }
    }
    final nw = (w + 1) ~/ 2, nh = (h + 1) ~/ 2;
    final out = Float32List(nw * nh);
    for (var y = 0; y < nh; y++) {
      final sy = y * 2;
      for (var x = 0; x < nw; x++) {
        final sx = x * 2;
        double at(int yy) => tmp[yy.clamp(0, h - 1) * w + sx];
        out[y * nw + x] =
            (at(sy - 2) +
                4 * at(sy - 1) +
                6 * at(sy) +
                4 * at(sy + 1) +
                at(sy + 2)) /
            16;
      }
    }
    return _Plane(nw, nh, out);
  }

  /// Bilinear upsample to (w, h).
  static _Plane _upsample(_Plane p, int w, int h) {
    final out = Float32List(w * h);
    final sx = p.w / w, sy = p.h / h;
    for (var y = 0; y < h; y++) {
      final fy = math.max(0.0, (y + 0.5) * sy - 0.5);
      final y0 = math.min(fy.floor(), p.h - 1);
      final y1 = math.min(y0 + 1, p.h - 1);
      final ty = fy - y0;
      for (var x = 0; x < w; x++) {
        final fx = math.max(0.0, (x + 0.5) * sx - 0.5);
        final x0 = math.min(fx.floor(), p.w - 1);
        final x1 = math.min(x0 + 1, p.w - 1);
        final tx = fx - x0;
        final a = p.d[y0 * p.w + x0], b = p.d[y0 * p.w + x1];
        final c = p.d[y1 * p.w + x0], d = p.d[y1 * p.w + x1];
        out[y * w + x] =
            (a * (1 - tx) + b * tx) * (1 - ty) + (c * (1 - tx) + d * tx) * ty;
      }
    }
    return _Plane(w, h, out);
  }
}

class _Plane {
  _Plane(this.w, this.h, this.d);
  final int w;
  final int h;
  final Float32List d;
}

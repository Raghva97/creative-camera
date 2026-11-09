import 'dart:typed_data';

import 'package:creative_camera/processing/hdr_fusion.dart';
import 'package:creative_camera/processing/stack_engine.dart';
import 'package:creative_camera/processing/tone.dart';
import 'package:flutter_test/flutter_test.dart';

/// Builds a w x h RGBA frame where [pixel] returns (r, g, b).
RawFrame frame(
  int w,
  int h,
  (int, int, int) Function(int x, int y) pixel, {
  bool bgra = false,
  int padding = 0,
}) {
  final stride = w * 4 + padding;
  final b = Uint8List(stride * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final (r, g, bl) = pixel(x, y);
      final o = y * stride + x * 4;
      b[o] = bgra ? bl : r;
      b[o + 1] = g;
      b[o + 2] = bgra ? r : bl;
      b[o + 3] = 255;
    }
  }
  return RawFrame(
    bytes: b,
    width: w,
    height: h,
    bytesPerRow: stride,
    isBgra: bgra,
  );
}

(int, int, int) px(RgbImage im, int x, int y) {
  final o = (y * im.width + x) * 3;
  return (im.data[o], im.data[o + 1], im.data[o + 2]);
}

void main() {
  group('StackEngine', () {
    test('lighten keeps the path of a moving light on a dark scene', () {
      final e = StackEngine(const StackOptions(blend: StackBlend.lighten));
      for (var i = 0; i < 8; i++) {
        e.add(
          frame(
            8,
            4,
            (x, y) => x == i && y == 1 ? (255, 200, 50) : (10, 10, 10),
          ),
        );
      }
      final r = e.result();
      for (var x = 0; x < 8; x++) {
        expect(px(r, x, 1), (255, 200, 50));
        expect(px(r, x, 0), (10, 10, 10));
      }
    });

    test('lighten threshold ignores dim flicker', () {
      final e = StackEngine(
        const StackOptions(blend: StackBlend.lighten, lightenThreshold: 100),
      );
      e.add(frame(2, 1, (x, y) => (20, 20, 20)));
      e.add(frame(2, 1, (x, y) => x == 0 ? (60, 60, 60) : (250, 250, 250)));
      final r = e.result();
      expect(px(r, 0, 0), (20, 20, 20));
      expect(px(r, 1, 0), (250, 250, 250));
    });

    test('average is the mean and handles BGRA and row padding', () {
      final e = StackEngine(const StackOptions(blend: StackBlend.average));
      e.add(frame(3, 2, (x, y) => (100, 0, 200), bgra: true, padding: 8));
      e.add(frame(3, 2, (x, y) => (200, 50, 0), bgra: true, padding: 8));
      expect(px(e.result(), 2, 1), (150, 25, 100));
    });

    test('median removes something present in a minority of frames', () {
      final e = StackEngine(const StackOptions(blend: StackBlend.median));
      for (var i = 0; i < 5; i++) {
        e.add(frame(4, 1, (x, y) => x == i ? (255, 0, 0) : (0, 128, 0)));
      }
      for (var x = 0; x < 4; x++) {
        expect(px(e.result(), x, 0), (0, 128, 0));
      }
    });

    test('maxFrames makes the engine report full', () {
      final e = StackEngine(
        const StackOptions(blend: StackBlend.average, maxFrames: 3),
      );
      for (var i = 0; i < 5; i++) {
        e.add(frame(2, 2, (x, y) => (1, 1, 1)));
      }
      expect(e.frameCount, 3);
      expect(e.isFull, isTrue);
    });

    test('slit scan writes the centre column of each frame left to right', () {
      final e = StackEngine(
        const StackOptions(blend: StackBlend.slitScan, slitWidth: 1),
      );
      for (var i = 0; i < 6; i++) {
        e.add(frame(6, 2, (x, y) => (i * 40, 0, 0)));
      }
      expect(e.isFull, isTrue);
      for (var x = 0; x < 6; x++) {
        expect(px(e.result(), x, 0).$1, x * 40);
      }
    });

    test('echo leaves a fading copy of a moving subject', () {
      final e = StackEngine(
        const StackOptions(blend: StackBlend.echo, echoDecay: 0.5),
      );
      e.add(frame(3, 1, (x, y) => x == 0 ? (200, 200, 200) : (0, 0, 0)));
      e.add(frame(3, 1, (x, y) => x == 2 ? (200, 200, 200) : (0, 0, 0)));
      final r = e.result();
      expect(px(r, 0, 0).$1, 100); // faded ghost
      expect(px(r, 2, 0).$1, 200); // current position
      expect(px(r, 1, 0).$1, 0);
    });

    test('alignment undoes camera shake before averaging', () {
      (int, int, int) scene(int x, int y) =>
          ((x * 7 + y * 13) % 256, (x * x + y) % 256, (x ^ y) % 256);
      final e = StackEngine(
        const StackOptions(blend: StackBlend.average, align: true),
      );
      e.add(frame(128, 96, scene));
      // Same scene moved 8 px right and 16 px down.
      e.add(frame(128, 96, (x, y) => scene(x - 8, y - 16)));
      final r = e.result();
      // Away from the borders the average equals the scene itself.
      expect(px(r, 60, 50), scene(60, 50));
    });
  });

  test('estimateShift finds a known translation', () {
    const w = 40, h = 30;
    final ref = Uint8List(w * h);
    for (var i = 0; i < ref.length; i++) {
      ref[i] = (i * 37) % 251;
    }
    final moved = Uint8List(w * h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final sx = (x + 3).clamp(0, w - 1), sy = (y - 2).clamp(0, h - 1);
        moved[y * w + x] = ref[sy * w + sx];
      }
    }
    // moved(x, y) = ref(x + 3, y - 2), so moving it by (+3, -2) restores ref.
    expect(estimateShift(ref, moved, w, h, 5), (3, -2));
  });

  test('nightTone brightens a dark image without clipping it all', () {
    final d = Uint8List(100 * 3);
    for (var i = 0; i < 100; i++) {
      d.fillRange(i * 3, i * 3 + 3, i ~/ 2);
    }
    final out = nightTone(RgbImage(100, 1, d));
    expect(out.data[150], greaterThan(d[150]));
    expect(out.data[0], 0);
  });

  test('HDR fusion picks the well exposed parts of each bracket', () {
    const w = 64, h = 64;
    // Left half: detail only visible in the dark frame (bright area).
    // Right half: detail only visible in the bright frame (shadow area).
    RgbImage make(int Function(int x, int y) f) {
      final im = RgbImage(w, h);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          final v = f(x, y).clamp(0, 255);
          im.data.fillRange((y * w + x) * 3, (y * w + x) * 3 + 3, v);
        }
      }
      return im;
    }

    int texture(int x, int y) => ((x + y) % 4) * 20;
    final dark = make((x, y) => x < 32 ? 110 + texture(x, y) : 2);
    final mid = make((x, y) => x < 32 ? 250 : 20);
    final bright = make((x, y) => x < 32 ? 255 : 100 + texture(x, y));
    final out = HdrFusion.fuse([dark, mid, bright]);

    // Both halves come out mid-toned rather than clipped or crushed.
    final left = px(out, 10, 32).$1, right = px(out, 50, 32).$1;
    expect(left, inInclusiveRange(60, 235));
    expect(right, inInclusiveRange(40, 220));
  });
}

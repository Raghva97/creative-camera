import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// Composition guide styles, cycled from the top bar.
enum GridStyle {
  thirds('Thirds', Icons.grid_3x3),
  golden('Golden', Icons.grid_4x4),
  cross('Centre', Icons.center_focus_strong),
  off('Off', Icons.grid_off);

  const GridStyle(this.label, this.icon);
  final String label;
  final IconData icon;

  GridStyle get next => GridStyle.values[(index + 1) % GridStyle.values.length];
}

class CompositionGrid extends StatelessWidget {
  const CompositionGrid({super.key, required this.style});
  final GridStyle style;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: CustomPaint(painter: _GridPainter(style), size: Size.infinite),
  );
}

class _GridPainter extends CustomPainter {
  _GridPainter(this.style);
  final GridStyle style;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..strokeWidth = 1;
    void v(double f) => canvas.drawLine(
      Offset(size.width * f, 0),
      Offset(size.width * f, size.height),
      p,
    );
    void h(double f) => canvas.drawLine(
      Offset(0, size.height * f),
      Offset(size.width, size.height * f),
      p,
    );
    switch (style) {
      case GridStyle.thirds:
        for (final f in [1 / 3, 2 / 3]) {
          v(f);
          h(f);
        }
      case GridStyle.golden:
        // Phi grid: lines at 0.382 and 0.618.
        for (final f in [0.382, 0.618]) {
          v(f);
          h(f);
        }
      case GridStyle.cross:
        final c = size.center(Offset.zero);
        canvas.drawLine(c - const Offset(18, 0), c + const Offset(18, 0), p);
        canvas.drawLine(c - const Offset(0, 18), c + const Offset(0, 18), p);
        canvas.drawRect(
          Rect.fromCenter(
            center: c,
            width: size.width * 0.5,
            height: size.width * 0.5,
          ),
          p..style = PaintingStyle.stroke,
        );
      case GridStyle.off:
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter old) => old.style != style;
}

/// Horizon level: a line that tilts with the phone and turns green when the
/// phone is level.
class LevelIndicator extends StatefulWidget {
  const LevelIndicator({super.key});

  @override
  State<LevelIndicator> createState() => _LevelIndicatorState();
}

class _LevelIndicatorState extends State<LevelIndicator> {
  StreamSubscription<AccelerometerEvent>? _sub;
  double _roll = 0;

  @override
  void initState() {
    super.initState();
    _sub = accelerometerEventStream(samplingPeriod: SensorInterval.uiInterval)
        .listen((e) {
          // Portrait: gravity along +y. Roll is the tilt around the lens axis.
          final roll = math.atan2(e.x, e.y) * 180 / math.pi;
          if (mounted) setState(() => _roll = _roll * 0.7 + roll * 0.3);
        }, onError: (_) {});
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final level = _roll.abs() < 1.0;
    final color = level ? Colors.greenAccent : Colors.white;
    return IgnorePointer(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Transform.rotate(
              angle: -_roll * math.pi / 180,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 70, height: 2, color: color),
                  Container(
                    width: 10,
                    height: 10,
                    margin: const EdgeInsets.symmetric(horizontal: 6),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: color, width: 2),
                    ),
                  ),
                  Container(width: 70, height: 2, color: color),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              level ? 'Level' : '${_roll.abs().toStringAsFixed(1)}°',
              style: TextStyle(color: color, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shows how steady the phone is (for handheld night shots).
class ShakeMeter extends StatefulWidget {
  const ShakeMeter({super.key});

  @override
  State<ShakeMeter> createState() => _ShakeMeterState();
}

class _ShakeMeterState extends State<ShakeMeter> {
  StreamSubscription<UserAccelerometerEvent>? _sub;
  double _shake = 0;

  @override
  void initState() {
    super.initState();
    _sub =
        userAccelerometerEventStream(samplingPeriod: SensorInterval.uiInterval)
            .listen((e) {
              final m = math.sqrt(e.x * e.x + e.y * e.y + e.z * e.z);
              if (mounted) setState(() => _shake = _shake * 0.8 + m * 0.2);
            }, onError: (_) {});
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final steady = _shake < 0.15;
    final ok = _shake < 0.4;
    final color = steady
        ? Colors.greenAccent
        : (ok ? Colors.amber : Colors.redAccent);
    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.vibration, color: color, size: 16),
            const SizedBox(width: 6),
            Text(
              steady ? 'Steady' : (ok ? 'Slight shake' : 'Hold still'),
              style: TextStyle(color: color),
            ),
          ],
        ),
      ),
    );
  }
}

/// The line that a time-slice capture records.
class SlitLine extends StatelessWidget {
  const SlitLine({super.key, required this.vertical, required this.color});
  final bool vertical;
  final Color color;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Center(
      child: Container(
        width: vertical ? 3 : double.infinity,
        height: vertical ? double.infinity : 3,
        decoration: BoxDecoration(
          color: color,
          boxShadow: [BoxShadow(color: color, blurRadius: 8)],
        ),
      ),
    ),
  );
}

import 'package:flutter/material.dart';

/// Rule-of-thirds grid drawn over the preview.
class ThirdsGrid extends StatelessWidget {
  const ThirdsGrid({super.key});

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: CustomPaint(painter: _GridPainter(), size: Size.infinite),
  );
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..strokeWidth = 1;
    for (var i = 1; i < 3; i++) {
      final x = size.width * i / 3, y = size.height * i / 3;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Bottom sheet listing shooting advice for a mode.
Future<void> showTips(BuildContext context, String title, List<String> tips) {
  return showModalBottomSheet(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'How to shoot: $title',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            for (final t in tips)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('•  ', style: TextStyle(fontSize: 16)),
                    Expanded(
                      child: Text(t, style: const TextStyle(fontSize: 15)),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

/// Round translucent icon button used on top of the camera preview.
class OverlayButton extends StatelessWidget {
  const OverlayButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.label,
    this.active = false,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final btn = Material(
      color: active ? Colors.amber.withValues(alpha: 0.9) : Colors.black45,
      shape: const CircleBorder(),
      child: IconButton(
        icon: Icon(icon, color: active ? Colors.black : Colors.white),
        onPressed: onPressed,
      ),
    );
    if (label == null) return btn;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        btn,
        const SizedBox(height: 2),
        Text(label!, style: const TextStyle(color: Colors.white, fontSize: 11)),
      ],
    );
  }
}

/// Large circular shutter button.
class ShutterButton extends StatelessWidget {
  const ShutterButton({
    super.key,
    required this.onTap,
    this.recording = false,
    this.busy = false,
    this.color = Colors.white,
  });

  final VoidCallback? onTap;
  final bool recording;
  final bool busy;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: busy ? null : onTap,
      child: Container(
        width: 78,
        height: 78,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 4),
        ),
        padding: const EdgeInsets.all(5),
        child: busy
            ? const CircularProgressIndicator(color: Colors.white)
            : AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  color: recording ? Colors.red : color,
                  shape: recording ? BoxShape.rectangle : BoxShape.circle,
                  borderRadius: recording ? BorderRadius.circular(8) : null,
                ),
                margin: recording ? const EdgeInsets.all(14) : EdgeInsets.zero,
              ),
      ),
    );
  }
}

/// Big centred countdown number.
class CountdownOverlay extends StatelessWidget {
  const CountdownOverlay({super.key, required this.value});
  final int value;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Center(
      child: Text(
        '$value',
        style: const TextStyle(
          fontSize: 120,
          color: Colors.white,
          fontWeight: FontWeight.w700,
          shadows: [Shadow(blurRadius: 12)],
        ),
      ),
    ),
  );
}

String formatDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}

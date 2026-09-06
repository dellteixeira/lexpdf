import 'dart:math' as math;

import 'package:flutter/material.dart';

class NotebookRulerOverlay extends StatefulWidget {
  const NotebookRulerOverlay({
    required this.enabled,
    this.snapDegrees = 15,
    super.key,
  });

  final bool enabled;
  final double snapDegrees;

  @override
  State<NotebookRulerOverlay> createState() => _NotebookRulerOverlayState();
}

class _NotebookRulerOverlayState extends State<NotebookRulerOverlay> {
  Offset _center = const Offset(220, 220);
  double _angle = 0;

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return const SizedBox.shrink();
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: false,
        child: Stack(
          children: [
            Positioned(
              left: _center.dx - 180,
              top: _center.dy - 24,
              width: 360,
              height: 48,
              child: Transform.rotate(
                angle: _angle,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanUpdate: (details) {
                    setState(() => _center += details.delta);
                  },
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0x33FFC107),
                      border: Border.all(color: const Color(0xAA8A6D00)),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: CustomPaint(
                      painter: const _RulerTicksPainter(),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 8,
              bottom: 8,
              child: Material(
                color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Girar régua à esquerda',
                      onPressed: () => _rotate(-widget.snapDegrees),
                      icon: const Icon(Icons.rotate_left),
                    ),
                    Text('${(_angle * 180 / math.pi).round()}°'),
                    IconButton(
                      tooltip: 'Girar régua à direita',
                      onPressed: () => _rotate(widget.snapDegrees),
                      icon: const Icon(Icons.rotate_right),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _rotate(double degrees) {
    final next = _angle + degrees * math.pi / 180;
    setState(() => _angle = _snap(next));
  }

  double _snap(double radians) {
    final step = widget.snapDegrees * math.pi / 180;
    if (step <= 0) return radians;
    return (radians / step).round() * step;
  }
}

class _RulerTicksPainter extends CustomPainter {
  const _RulerTicksPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xAA6D5700)
      ..strokeWidth = 1;
    for (double x = 8; x < size.width; x += 8) {
      final major = x % 40 == 0;
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, major ? 16 : 9),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RulerTicksPainter oldDelegate) => false;
}

import 'package:flutter/material.dart';

import '../core/ink/ink_models.dart';

class NotebookPageBackground extends StatelessWidget {
  const NotebookPageBackground({
    required this.background,
    super.key,
  });

  final InkPageBackground background;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _NotebookBackgroundPainter(background),
      child: const SizedBox.expand(),
    );
  }
}

class _NotebookBackgroundPainter extends CustomPainter {
  const _NotebookBackgroundPainter(this.background);

  final InkPageBackground background;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    final linePaint = Paint()
      ..color = const Color(0x1F5F6B7A)
      ..strokeWidth = 1;
    final accentPaint = Paint()
      ..color = const Color(0x305F6B7A)
      ..strokeWidth = 1.3;

    switch (background) {
      case InkPageBackground.blank:
        return;
      case InkPageBackground.ruled:
        for (double y = 36; y < size.height; y += 36) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
        }
      case InkPageBackground.grid:
        for (double y = 32; y < size.height; y += 32) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
        }
        for (double x = 32; x < size.width; x += 32) {
          canvas.drawLine(Offset(x, 0), Offset(x, size.height), linePaint);
        }
      case InkPageBackground.dotted:
        final dotPaint = Paint()..color = const Color(0x405F6B7A);
        for (double y = 28; y < size.height; y += 28) {
          for (double x = 28; x < size.width; x += 28) {
            canvas.drawCircle(Offset(x, y), 1.15, dotPaint);
          }
        }
      case InkPageBackground.cornell:
        final cueX = size.width * 0.28;
        final summaryY = size.height * 0.82;
        canvas.drawLine(Offset(cueX, 0), Offset(cueX, summaryY), accentPaint);
        canvas.drawLine(
          Offset(0, summaryY),
          Offset(size.width, summaryY),
          accentPaint,
        );
        for (double y = 36; y < summaryY; y += 36) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
        }
      case InkPageBackground.planner:
        const margin = 28.0;
        final headerHeight = size.height * 0.12;
        final columnWidth = (size.width - margin * 2) / 3;
        canvas.drawRect(
          Rect.fromLTWH(margin, margin, size.width - margin * 2, headerHeight),
          accentPaint..style = PaintingStyle.stroke,
        );
        for (var column = 0; column <= 3; column++) {
          final x = margin + columnWidth * column;
          canvas.drawLine(
            Offset(x, margin + headerHeight + 16),
            Offset(x, size.height - margin),
            accentPaint,
          );
        }
        for (double y = margin + headerHeight + 52; y < size.height - margin; y += 44) {
          canvas.drawLine(
            Offset(margin, y),
            Offset(size.width - margin, y),
            linePaint,
          );
        }
    }
  }

  @override
  bool shouldRepaint(covariant _NotebookBackgroundPainter oldDelegate) =>
      oldDelegate.background != background;
}

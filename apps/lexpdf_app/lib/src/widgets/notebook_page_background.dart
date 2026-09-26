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
        return;
      case InkPageBackground.grid:
        for (double y = 32; y < size.height; y += 32) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
        }
        for (double x = 32; x < size.width; x += 32) {
          canvas.drawLine(Offset(x, 0), Offset(x, size.height), linePaint);
        }
        return;
      case InkPageBackground.dotted:
        final dotPaint = Paint()..color = const Color(0x405F6B7A);
        for (double y = 28; y < size.height; y += 28) {
          for (double x = 28; x < size.width; x += 28) {
            canvas.drawCircle(Offset(x, y), 1.15, dotPaint);
          }
        }
        return;
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
        return;
      case InkPageBackground.planner:
        const margin = 28.0;
        final headerHeight = size.height * 0.12;
        final columnWidth = (size.width - margin * 2) / 3;
        final plannerPaint = Paint()
          ..color = const Color(0x305F6B7A)
          ..strokeWidth = 1.3
          ..style = PaintingStyle.stroke;
        canvas.drawRect(
          Rect.fromLTWH(margin, margin, size.width - margin * 2, headerHeight),
          plannerPaint,
        );
        for (var column = 0; column <= 3; column++) {
          final x = margin + columnWidth * column;
          canvas.drawLine(
            Offset(x, margin + headerHeight + 16),
            Offset(x, size.height - margin),
            plannerPaint,
          );
        }
        for (double y = margin + headerHeight + 52;
            y < size.height - margin;
            y += 44) {
          canvas.drawLine(
            Offset(margin, y),
            Offset(size.width - margin, y),
            linePaint,
          );
        }
        return;
      case InkPageBackground.crossGrid:
        final crossPaint = Paint()
          ..color = const Color(0x405F6B7A)
          ..strokeWidth = 0.9;
        for (double y = 24; y < size.height; y += 24) {
          for (double x = 24; x < size.width; x += 24) {
            canvas.drawLine(
              Offset(x - 3, y),
              Offset(x + 3, y),
              crossPaint,
            );
            canvas.drawLine(
              Offset(x, y - 3),
              Offset(x, y + 3),
              crossPaint,
            );
          }
        }
        return;
      case InkPageBackground.isometric:
        final isoPaint = Paint()
          ..color = const Color(0x285F6B7A)
          ..strokeWidth = 0.8;
        const spacing = 32.0;
        for (double y = -size.width; y < size.height + size.width; y += spacing) {
          canvas.drawLine(
            Offset(0, y),
            Offset(size.width, y + size.width * 0.577),
            isoPaint,
          );
          canvas.drawLine(
            Offset(0, y),
            Offset(size.width, y - size.width * 0.577),
            isoPaint,
          );
        }
        for (double x = 0; x < size.width; x += spacing) {
          canvas.drawLine(Offset(x, 0), Offset(x, size.height), isoPaint);
        }
        return;
      case InkPageBackground.engineering:
        final fine = Paint()
          ..color = const Color(0x205F6B7A)
          ..strokeWidth = 0.6;
        final major = Paint()
          ..color = const Color(0x385F6B7A)
          ..strokeWidth = 1.0;
        for (double y = 10; y < size.height; y += 10) {
          final p = ((y / 10).round() % 5 == 0) ? major : fine;
          canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
        }
        for (double x = 10; x < size.width; x += 10) {
          final p = ((x / 10).round() % 5 == 0) ? major : fine;
          canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
        }
        return;
      case InkPageBackground.music:
        final staffPaint = Paint()
          ..color = const Color(0x505F6B7A)
          ..strokeWidth = 1.0;
        for (double top = 48; top < size.height - 48; top += 92) {
          for (var line = 0; line < 5; line++) {
            final y = top + line * 10;
            canvas.drawLine(
              Offset(30, y),
              Offset(size.width - 30, y),
              staffPaint,
            );
          }
        }
        return;
      case InkPageBackground.taskList:
        final taskPaint = Paint()
          ..color = const Color(0x405F6B7A)
          ..strokeWidth = 1.1
          ..style = PaintingStyle.stroke;
        for (double y = 48; y < size.height - 28; y += 42) {
          canvas.drawRect(
            Rect.fromLTWH(30, y - 11, 18, 18),
            taskPaint,
          );
          canvas.drawLine(
            Offset(62, y),
            Offset(size.width - 28, y),
            linePaint,
          );
        }
        return;
    }
  }

  @override
  bool shouldRepaint(covariant _NotebookBackgroundPainter oldDelegate) =>
      oldDelegate.background != background;
}

import 'package:flutter/material.dart';

import '../core/ink/ink_models.dart';

class NotebookLayerInkView extends StatelessWidget {
  const NotebookLayerInkView({required this.strokes, super.key});

  final List<InkStroke> strokes;

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: CustomPaint(
          painter: _NotebookLayerInkPainter(strokes),
          size: Size.infinite,
        ),
      );
}

class _NotebookLayerInkPainter extends CustomPainter {
  const _NotebookLayerInkPainter(this.strokes);

  final List<InkStroke> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    for (final stroke in strokes) {
      if (stroke.points.isEmpty) continue;
      final paint = Paint()
        ..color = Color(stroke.colorValue).withValues(alpha: stroke.opacity)
        ..strokeWidth = stroke.width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      final path = Path();
      final first = stroke.points.first;
      path.moveTo(first.x, first.y);
      for (var index = 1; index < stroke.points.length; index++) {
        final point = stroke.points[index];
        path.lineTo(point.x, point.y);
      }
      if (stroke.points.length == 1) {
        canvas.drawCircle(Offset(first.x, first.y), stroke.width / 2, paint..style = PaintingStyle.fill);
      } else {
        canvas.drawPath(path, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _NotebookLayerInkPainter oldDelegate) =>
      oldDelegate.strokes != strokes;
}

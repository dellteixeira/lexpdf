import 'dart:math' as math;

import 'ink_models.dart';
import 'pdf_ink_models.dart';

class PdfInkEraseResult {
  const PdfInkEraseResult({
    required this.original,
    required this.fragments,
  });

  final PdfInkStroke original;
  final List<PdfInkStroke> fragments;
}

class PdfInkEraser {
  const PdfInkEraser();

  PdfInkEraseResult? eraseAt({
    required PdfInkStroke stroke,
    required double localX,
    required double localY,
    required double pageWidth,
    required double pageHeight,
    required double radius,
  }) {
    if (stroke.points.length < 2 || pageWidth <= 0 || pageHeight <= 0) {
      return null;
    }

    final keep = List<bool>.filled(stroke.points.length, true);
    var touched = false;
    final radiusSquared = radius * radius;

    for (var index = 0; index < stroke.points.length; index++) {
      final point = stroke.points[index];
      final px = point.x * pageWidth;
      final py = point.y * pageHeight;
      final dx = px - localX;
      final dy = py - localY;
      if (dx * dx + dy * dy <= radiusSquared) {
        keep[index] = false;
        touched = true;
      }
    }

    for (var index = 1; index < stroke.points.length; index++) {
      final a = stroke.points[index - 1];
      final b = stroke.points[index];
      if (_distanceToSegmentSquared(
            localX,
            localY,
            a.x * pageWidth,
            a.y * pageHeight,
            b.x * pageWidth,
            b.y * pageHeight,
          ) <=
          radiusSquared) {
        keep[index - 1] = false;
        keep[index] = false;
        touched = true;
      }
    }

    if (!touched) return null;

    final fragments = <PdfInkStroke>[];
    final current = <InkPoint>[];
    var fragmentIndex = 0;

    void flush() {
      if (current.length >= 2) {
        fragments.add(
          PdfInkStroke(
            id: '${stroke.id}-e$fragmentIndex',
            documentId: stroke.documentId,
            pageNumber: stroke.pageNumber,
            tool: stroke.tool,
            colorValue: stroke.colorValue,
            opacity: stroke.opacity,
            width: stroke.width,
            points: List<InkPoint>.unmodifiable(current),
            createdAt: stroke.createdAt,
          ),
        );
        fragmentIndex++;
      }
      current.clear();
    }

    for (var index = 0; index < stroke.points.length; index++) {
      if (keep[index]) {
        current.add(stroke.points[index]);
      } else {
        flush();
      }
    }
    flush();

    return PdfInkEraseResult(
      original: stroke,
      fragments: List<PdfInkStroke>.unmodifiable(fragments),
    );
  }

  double _distanceToSegmentSquared(
    double px,
    double py,
    double ax,
    double ay,
    double bx,
    double by,
  ) {
    final abx = bx - ax;
    final aby = by - ay;
    final lengthSquared = abx * abx + aby * aby;
    if (lengthSquared == 0) {
      final dx = px - ax;
      final dy = py - ay;
      return dx * dx + dy * dy;
    }
    final t = (((px - ax) * abx + (py - ay) * aby) / lengthSquared)
        .clamp(0.0, 1.0)
        .toDouble();
    final nearestX = ax + abx * t;
    final nearestY = ay + aby * t;
    return math.pow(px - nearestX, 2).toDouble() +
        math.pow(py - nearestY, 2).toDouble();
  }
}

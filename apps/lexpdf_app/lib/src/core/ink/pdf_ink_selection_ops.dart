import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'ink_models.dart';
import 'pdf_ink_models.dart';

class PdfInkSelectionOps {
  const PdfInkSelectionOps();

  List<PdfInkStroke> move({
    required List<PdfInkStroke> strokes,
    required Set<String> selectedIds,
    required double dx,
    required double dy,
  }) {
    return _transform(strokes, selectedIds, (stroke) {
      return _copyStroke(
        stroke,
        points: stroke.points
            .map(
              (point) => _copyPoint(
                point,
                x: (point.x + dx).clamp(0.0, 1.0),
                y: (point.y + dy).clamp(0.0, 1.0),
              ),
            )
            .toList(growable: false),
      );
    });
  }

  List<PdfInkStroke> scale({
    required List<PdfInkStroke> strokes,
    required Set<String> selectedIds,
    required double factor,
  }) {
    if (factor <= 0 || factor == 1) return const [];
    final center = selectionCenter(strokes, selectedIds);
    if (center == null) return const [];
    return _transform(strokes, selectedIds, (stroke) {
      return _copyStroke(
        stroke,
        width: (stroke.width * factor).clamp(0.25, 100).toDouble(),
        points: stroke.points
            .map(
              (point) => _copyPoint(
                point,
                x: (center.dx + (point.x - center.dx) * factor).clamp(0.0, 1.0),
                y: (center.dy + (point.y - center.dy) * factor).clamp(0.0, 1.0),
              ),
            )
            .toList(growable: false),
      );
    });
  }

  List<PdfInkStroke> rotate({
    required List<PdfInkStroke> strokes,
    required Set<String> selectedIds,
    required double angleRadians,
  }) {
    if (angleRadians == 0) return const [];
    final center = selectionCenter(strokes, selectedIds);
    if (center == null) return const [];
    final cosAngle = math.cos(angleRadians);
    final sinAngle = math.sin(angleRadians);
    return _transform(strokes, selectedIds, (stroke) {
      return _copyStroke(
        stroke,
        points: stroke.points.map((point) {
          final dx = point.x - center.dx;
          final dy = point.y - center.dy;
          return _copyPoint(
            point,
            x: (center.dx + dx * cosAngle - dy * sinAngle).clamp(0.0, 1.0),
            y: (center.dy + dx * sinAngle + dy * cosAngle).clamp(0.0, 1.0),
          );
        }).toList(growable: false),
      );
    });
  }

  List<PdfInkStroke> recolor({
    required List<PdfInkStroke> strokes,
    required Set<String> selectedIds,
    required int colorValue,
  }) {
    return _transform(
      strokes,
      selectedIds,
      (stroke) => _copyStroke(stroke, colorValue: colorValue),
    );
  }

  List<PdfInkStroke> setWidth({
    required List<PdfInkStroke> strokes,
    required Set<String> selectedIds,
    required double width,
  }) {
    final safeWidth = width.clamp(0.25, 100).toDouble();
    return _transform(
      strokes,
      selectedIds,
      (stroke) => _copyStroke(stroke, width: safeWidth),
    );
  }

  Offset? selectionCenter(List<PdfInkStroke> strokes, Set<String> selectedIds) {
    final points = strokes
        .where((stroke) => selectedIds.contains(stroke.id))
        .expand((stroke) => stroke.points)
        .toList(growable: false);
    if (points.isEmpty) return null;
    var minX = points.first.x;
    var minY = points.first.y;
    var maxX = minX;
    var maxY = minY;
    for (final point in points.skip(1)) {
      minX = math.min(minX, point.x);
      minY = math.min(minY, point.y);
      maxX = math.max(maxX, point.x);
      maxY = math.max(maxY, point.y);
    }
    return Offset((minX + maxX) / 2, (minY + maxY) / 2);
  }

  List<PdfInkStroke> _transform(
    List<PdfInkStroke> strokes,
    Set<String> selectedIds,
    PdfInkStroke Function(PdfInkStroke) transform,
  ) {
    if (selectedIds.isEmpty) return const [];
    return strokes
        .where((stroke) => selectedIds.contains(stroke.id))
        .map(transform)
        .toList(growable: false);
  }

  PdfInkStroke _copyStroke(
    PdfInkStroke stroke, {
    List<InkPoint>? points,
    double? width,
    int? colorValue,
  }) {
    return PdfInkStroke(
      id: stroke.id,
      documentId: stroke.documentId,
      pageNumber: stroke.pageNumber,
      tool: stroke.tool,
      colorValue: colorValue ?? stroke.colorValue,
      opacity: stroke.opacity,
      width: width ?? stroke.width,
      points: List<InkPoint>.unmodifiable(points ?? stroke.points),
      createdAt: stroke.createdAt,
    );
  }

  InkPoint _copyPoint(
    InkPoint point, {
    required double x,
    required double y,
  }) {
    return InkPoint(
      x: x,
      y: y,
      pressure: point.pressure,
      tilt: point.tilt,
      timestampMicros: point.timestampMicros,
    );
  }
}

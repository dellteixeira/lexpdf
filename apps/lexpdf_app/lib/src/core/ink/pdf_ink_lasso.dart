import 'dart:ui' show Offset, Rect;

import 'pdf_ink_models.dart';

class PdfInkLasso {
  const PdfInkLasso();

  Set<String> selectStrokes({
    required List<PdfInkStroke> strokes,
    required List<Offset> polygon,
  }) {
    if (polygon.length < 3) return const <String>{};
    final selected = <String>{};
    for (final stroke in strokes) {
      if (stroke.points.any(
        (point) => _pointInPolygon(Offset(point.x, point.y), polygon),
      )) {
        selected.add(stroke.id);
      }
    }
    return selected;
  }

  Rect? selectionBounds({
    required List<PdfInkStroke> strokes,
    required Set<String> selectedIds,
  }) {
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
      if (point.x < minX) minX = point.x;
      if (point.y < minY) minY = point.y;
      if (point.x > maxX) maxX = point.x;
      if (point.y > maxY) maxY = point.y;
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  bool _pointInPolygon(Offset point, List<Offset> polygon) {
    var inside = false;
    var j = polygon.length - 1;
    for (var i = 0; i < polygon.length; i++) {
      final a = polygon[i];
      final b = polygon[j];
      final denominator = (b.dy - a.dy).abs() < 1e-9 ? 1e-9 : b.dy - a.dy;
      final intersects = ((a.dy > point.dy) != (b.dy > point.dy)) &&
          (point.dx <
              (b.dx - a.dx) * (point.dy - a.dy) / denominator + a.dx);
      if (intersects) inside = !inside;
      j = i;
    }
    return inside;
  }
}

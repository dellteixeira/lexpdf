import 'dart:ui' show Offset;

import 'ink_models.dart';

class InkLasso {
  const InkLasso();

  Set<String> selectStrokes({
    required List<InkStroke> strokes,
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

  bool _pointInPolygon(Offset point, List<Offset> polygon) {
    var inside = false;
    var j = polygon.length - 1;
    for (var i = 0; i < polygon.length; i++) {
      final a = polygon[i];
      final b = polygon[j];
      final intersects = ((a.dy > point.dy) != (b.dy > point.dy)) &&
          (point.dx <
              (b.dx - a.dx) * (point.dy - a.dy) /
                      ((b.dy - a.dy).abs() < 1e-9 ? 1e-9 : b.dy - a.dy) +
                  a.dx);
      if (intersects) inside = !inside;
      j = i;
    }
    return inside;
  }
}

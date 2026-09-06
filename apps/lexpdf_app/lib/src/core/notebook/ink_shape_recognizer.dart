import 'dart:math' as math;

import '../ink/ink_models.dart';
import 'notebook_object_models.dart';

class InkShapeRecognition {
  const InkShapeRecognition({
    required this.type,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  final NotebookObjectType type;
  final double x;
  final double y;
  final double width;
  final double height;
}

class InkShapeRecognizer {
  const InkShapeRecognizer();

  InkShapeRecognition? recognize(InkStroke stroke) {
    if (stroke.points.length < 2) return null;
    final bounds = _bounds(stroke.points);
    final width = math.max(1.0, bounds.maxX - bounds.minX);
    final height = math.max(1.0, bounds.maxY - bounds.minY);
    final diagonal = math.sqrt(width * width + height * height);
    if (diagonal < 12) return null;

    final lineError = _meanLineDistance(stroke.points);
    if (lineError <= math.max(4, diagonal * 0.045)) {
      return InkShapeRecognition(
        type: NotebookObjectType.line,
        x: bounds.minX,
        y: bounds.minY,
        width: width,
        height: height,
      );
    }

    final first = stroke.points.first;
    final last = stroke.points.last;
    final closingDistance = math.sqrt(
      math.pow(last.x - first.x, 2) + math.pow(last.y - first.y, 2),
    );
    if (closingDistance > diagonal * 0.22 || stroke.points.length < 6) {
      return null;
    }

    final aspect = width / height;
    final ellipseScore = _ellipseRadialVariance(stroke.points, bounds);
    final type = aspect >= 0.65 && aspect <= 1.55 && ellipseScore < 0.12
        ? NotebookObjectType.ellipse
        : NotebookObjectType.rectangle;
    return InkShapeRecognition(
      type: type,
      x: bounds.minX,
      y: bounds.minY,
      width: width,
      height: height,
    );
  }

  double _meanLineDistance(List<InkPoint> points) {
    final first = points.first;
    final last = points.last;
    final dx = last.x - first.x;
    final dy = last.y - first.y;
    final length = math.sqrt(dx * dx + dy * dy);
    if (length == 0) return double.infinity;
    var sum = 0.0;
    for (final point in points) {
      sum += ((dy * point.x - dx * point.y + last.x * first.y - last.y * first.x).abs()) / length;
    }
    return sum / points.length;
  }

  double _ellipseRadialVariance(List<InkPoint> points, _InkBounds bounds) {
    final cx = (bounds.minX + bounds.maxX) / 2;
    final cy = (bounds.minY + bounds.maxY) / 2;
    final rx = math.max(1.0, (bounds.maxX - bounds.minX) / 2);
    final ry = math.max(1.0, (bounds.maxY - bounds.minY) / 2);
    final normalized = points.map((point) {
      final nx = (point.x - cx) / rx;
      final ny = (point.y - cy) / ry;
      return math.sqrt(nx * nx + ny * ny);
    }).toList(growable: false);
    final mean = normalized.reduce((a, b) => a + b) / normalized.length;
    final variance = normalized
            .map((value) => math.pow(value - mean, 2).toDouble())
            .reduce((a, b) => a + b) /
        normalized.length;
    return variance;
  }

  _InkBounds _bounds(List<InkPoint> points) {
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
    return _InkBounds(minX, minY, maxX, maxY);
  }
}

class _InkBounds {
  const _InkBounds(this.minX, this.minY, this.maxX, this.maxY);
  final double minX;
  final double minY;
  final double maxX;
  final double maxY;
}

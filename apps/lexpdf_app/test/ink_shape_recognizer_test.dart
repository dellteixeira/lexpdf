import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:lexxpdf_app/src/core/ink/ink_models.dart';
import 'package:lexxpdf_app/src/core/notebook/ink_shape_recognizer.dart';
import 'package:lexxpdf_app/src/core/notebook/notebook_object_models.dart';

void main() {
  const recognizer = InkShapeRecognizer();

  InkStroke stroke(String id, List<InkPoint> points) => InkStroke(
        id: id,
        pageId: 'page-1',
        tool: InkTool.pen,
        colorValue: 0xFF000000,
        opacity: 1,
        width: 3,
        points: points,
        createdAt: DateTime.utc(2026, 9, 6),
      );

  InkPoint point(double x, double y, int t) => InkPoint(
        x: x,
        y: y,
        pressure: 1,
        tilt: 0,
        timestampMicros: t,
      );

  test('recognizes a nearly straight stroke as line', () {
    final result = recognizer.recognize(
      stroke('line', [
        point(10, 20, 1),
        point(40, 31, 2),
        point(70, 40, 3),
        point(100, 51, 4),
      ]),
    );

    expect(result, isNotNull);
    expect(result!.type, NotebookObjectType.line);
  });

  test('recognizes a closed circular stroke as ellipse', () {
    final points = <InkPoint>[];
    for (var index = 0; index <= 24; index++) {
      final angle = index * 2 * math.pi / 24;
      points.add(point(100 + math.cos(angle) * 50, 100 + math.sin(angle) * 45, index));
    }

    final result = recognizer.recognize(stroke('ellipse', points));
    expect(result, isNotNull);
    expect(result!.type, NotebookObjectType.ellipse);
  });

  test('recognizes a closed rectangular stroke as rectangle', () {
    final result = recognizer.recognize(
      stroke('rectangle', [
        point(10, 10, 1),
        point(60, 10, 2),
        point(110, 10, 3),
        point(110, 60, 4),
        point(110, 110, 5),
        point(60, 110, 6),
        point(10, 110, 7),
        point(10, 60, 8),
        point(10, 10, 9),
      ]),
    );

    expect(result, isNotNull);
    expect(result!.type, NotebookObjectType.rectangle);
  });

  test('does not force recognition for an open irregular stroke', () {
    final result = recognizer.recognize(
      stroke('scribble', [
        point(10, 10, 1),
        point(80, 15, 2),
        point(25, 80, 3),
        point(100, 95, 4),
      ]),
    );

    expect(result, isNull);
  });
}

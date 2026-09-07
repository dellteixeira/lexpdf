import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:lexpdf_app/src/core/ink/ink_models.dart';
import 'package:lexpdf_app/src/core/ink/pdf_ink_models.dart';
import 'package:lexpdf_app/src/core/ink/pdf_ink_selection_ops.dart';

void main() {
  const ops = PdfInkSelectionOps();

  PdfInkStroke stroke(String id, List<Offset> points, {double width = 3}) {
    return PdfInkStroke(
      id: id,
      documentId: 'doc',
      pageNumber: 1,
      tool: InkTool.pen,
      colorValue: 0xFF000000,
      opacity: 1,
      width: width,
      points: points
          .map(
            (point) => InkPoint(
              x: point.dx,
              y: point.dy,
              pressure: 0.5,
              tilt: 0.2,
              timestampMicros: 7,
            ),
          )
          .toList(growable: false),
      createdAt: DateTime.utc(2026),
    );
  }

  test('move changes only selected strokes and preserves metadata', () {
    final source = [
      stroke('a', const [Offset(0.2, 0.2), Offset(0.3, 0.3)]),
      stroke('b', const [Offset(0.7, 0.7), Offset(0.8, 0.8)]),
    ];

    final moved = ops.move(
      strokes: source,
      selectedIds: const {'a'},
      dx: 0.1,
      dy: -0.05,
    );

    expect(moved, hasLength(1));
    expect(moved.single.id, 'a');
    expect(moved.single.points.first.x, closeTo(0.3, 1e-9));
    expect(moved.single.points.first.y, closeTo(0.15, 1e-9));
    expect(moved.single.points.first.pressure, 0.5);
    expect(moved.single.points.first.tilt, 0.2);
  });

  test('scale keeps geometric center stable', () {
    final source = [
      stroke('a', const [Offset(0.2, 0.2), Offset(0.4, 0.4)]),
      stroke('b', const [Offset(0.6, 0.6), Offset(0.8, 0.8)]),
    ];
    final before = ops.selectionCenter(source, const {'a', 'b'});
    final scaled = ops.scale(
      strokes: source,
      selectedIds: const {'a', 'b'},
      factor: 1.1,
    );
    final after = ops.selectionCenter(scaled, const {'a', 'b'});

    expect(after!.dx, closeTo(before!.dx, 1e-9));
    expect(after.dy, closeTo(before.dy, 1e-9));
  });

  test('rotate by 90 degrees uses selection center', () {
    final source = [
      stroke('a', const [Offset(0.3, 0.5), Offset(0.7, 0.5)]),
    ];
    final rotated = ops.rotate(
      strokes: source,
      selectedIds: const {'a'},
      angleRadians: math.pi / 2,
    );

    expect(rotated.single.points.first.x, closeTo(0.5, 1e-9));
    expect(rotated.single.points.first.y, closeTo(0.3, 1e-9));
    expect(rotated.single.points.last.x, closeTo(0.5, 1e-9));
    expect(rotated.single.points.last.y, closeTo(0.7, 1e-9));
  });

  test('recolor and width keep ids and geometry', () {
    final source = [stroke('a', const [Offset(0.2, 0.2), Offset(0.3, 0.3)])];
    final colored = ops.recolor(
      strokes: source,
      selectedIds: const {'a'},
      colorValue: 0xFF123456,
    );
    final widened = ops.setWidth(
      strokes: colored,
      selectedIds: const {'a'},
      width: 8,
    );

    expect(widened.single.id, 'a');
    expect(widened.single.colorValue, 0xFF123456);
    expect(widened.single.width, 8);
    expect(widened.single.points.first.x, 0.2);
  });
}

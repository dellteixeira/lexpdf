import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:lexxpdf_app/src/core/ink/ink_models.dart';
import 'package:lexxpdf_app/src/core/ink/pdf_ink_lasso.dart';
import 'package:lexxpdf_app/src/core/ink/pdf_ink_models.dart';

void main() {
  const lasso = PdfInkLasso();

  PdfInkStroke stroke(String id, List<Offset> points) {
    return PdfInkStroke(
      id: id,
      documentId: 'doc-1',
      pageNumber: 1,
      tool: InkTool.pen,
      colorValue: 0xFF000000,
      opacity: 1,
      width: 3,
      points: points
          .map(
            (point) => InkPoint(
              x: point.dx,
              y: point.dy,
              pressure: 1,
              tilt: 0,
              timestampMicros: 0,
            ),
          )
          .toList(growable: false),
      createdAt: DateTime.utc(2026),
    );
  }

  test('selects only strokes intersecting normalized polygon', () {
    final selected = lasso.selectStrokes(
      strokes: [
        stroke('inside', const [Offset(0.2, 0.2), Offset(0.3, 0.3)]),
        stroke('outside', const [Offset(0.8, 0.8), Offset(0.9, 0.9)]),
      ],
      polygon: const [
        Offset(0.1, 0.1),
        Offset(0.5, 0.1),
        Offset(0.5, 0.5),
        Offset(0.1, 0.5),
      ],
    );

    expect(selected, {'inside'});
  });

  test('returns combined bounds for selected strokes', () {
    final strokes = [
      stroke('a', const [Offset(0.2, 0.3), Offset(0.4, 0.5)]),
      stroke('b', const [Offset(0.6, 0.1), Offset(0.9, 0.8)]),
    ];

    final bounds = lasso.selectionBounds(
      strokes: strokes,
      selectedIds: const {'a', 'b'},
    );

    expect(bounds, const Rect.fromLTRB(0.2, 0.1, 0.9, 0.8));
  });

  test('invalid polygon selects nothing', () {
    final selected = lasso.selectStrokes(
      strokes: [stroke('a', const [Offset(0.2, 0.2), Offset(0.3, 0.3)])],
      polygon: const [Offset(0.1, 0.1), Offset(0.5, 0.1)],
    );

    expect(selected, isEmpty);
  });
}

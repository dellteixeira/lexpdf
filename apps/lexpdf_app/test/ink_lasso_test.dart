import 'dart:ui' show Offset;

import 'package:flutter_test/flutter_test.dart';
import 'package:lexxpdf_app/src/core/ink/ink_lasso.dart';
import 'package:lexxpdf_app/src/core/ink/ink_models.dart';

void main() {
  const lasso = InkLasso();

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

  const square = <Offset>[
    Offset(10, 10),
    Offset(90, 10),
    Offset(90, 90),
    Offset(10, 90),
  ];

  test('seleciona stroke com ponto dentro do polígono', () {
    final selected = lasso.selectStrokes(
      polygon: square,
      strokes: [
        stroke('inside', const [
          InkPoint(x: 20, y: 20, pressure: 1, tilt: 0, timestampMicros: 1),
          InkPoint(x: 40, y: 40, pressure: 1, tilt: 0, timestampMicros: 2),
        ]),
      ],
    );

    expect(selected, {'inside'});
  });

  test('não seleciona stroke totalmente fora do polígono', () {
    final selected = lasso.selectStrokes(
      polygon: square,
      strokes: [
        stroke('outside', const [
          InkPoint(x: 120, y: 120, pressure: 1, tilt: 0, timestampMicros: 1),
          InkPoint(x: 140, y: 140, pressure: 1, tilt: 0, timestampMicros: 2),
        ]),
      ],
    );

    expect(selected, isEmpty);
  });

  test('seleciona múltiplos strokes e ignora os externos', () {
    final selected = lasso.selectStrokes(
      polygon: square,
      strokes: [
        stroke('a', const [
          InkPoint(x: 15, y: 15, pressure: 1, tilt: 0, timestampMicros: 1),
          InkPoint(x: 30, y: 30, pressure: 1, tilt: 0, timestampMicros: 2),
        ]),
        stroke('b', const [
          InkPoint(x: 70, y: 70, pressure: 1, tilt: 0, timestampMicros: 3),
          InkPoint(x: 85, y: 85, pressure: 1, tilt: 0, timestampMicros: 4),
        ]),
        stroke('c', const [
          InkPoint(x: 120, y: 20, pressure: 1, tilt: 0, timestampMicros: 5),
          InkPoint(x: 140, y: 20, pressure: 1, tilt: 0, timestampMicros: 6),
        ]),
      ],
    );

    expect(selected, {'a', 'b'});
  });

  test('laço com menos de três pontos não seleciona', () {
    final selected = lasso.selectStrokes(
      polygon: const [Offset(0, 0), Offset(100, 100)],
      strokes: [
        stroke('inside', const [
          InkPoint(x: 20, y: 20, pressure: 1, tilt: 0, timestampMicros: 1),
          InkPoint(x: 40, y: 40, pressure: 1, tilt: 0, timestampMicros: 2),
        ]),
      ],
    );

    expect(selected, isEmpty);
  });
}

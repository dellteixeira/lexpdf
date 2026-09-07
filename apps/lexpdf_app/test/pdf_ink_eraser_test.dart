import 'package:flutter_test/flutter_test.dart';
import 'package:lexpdf_app/src/core/ink/ink_models.dart';
import 'package:lexpdf_app/src/core/ink/pdf_ink_eraser.dart';
import 'package:lexpdf_app/src/core/ink/pdf_ink_models.dart';

void main() {
  PdfInkStroke strokeWith(List<InkPoint> points) => PdfInkStroke(
        id: 'stroke-1',
        documentId: 'doc-1',
        pageNumber: 1,
        tool: InkTool.pen,
        colorValue: 0xFF246BFD,
        opacity: 1,
        width: 3,
        points: points,
        createdAt: DateTime.utc(2026, 9, 6),
      );

  test('corta exatamente nas bordas do círculo e interpola metadados', () {
    final stroke = strokeWith(const [
      InkPoint(x: 0.30, y: 0.50, pressure: 0.2, tilt: 0.1, timestampMicros: 100),
      InkPoint(x: 0.70, y: 0.50, pressure: 1.0, tilt: 0.5, timestampMicros: 500),
    ]);

    final result = const PdfInkEraser().eraseAt(
      stroke: stroke,
      localX: 500,
      localY: 500,
      pageWidth: 1000,
      pageHeight: 1000,
      radius: 60,
    );

    expect(result, isNotNull);
    expect(result!.fragments, hasLength(2));
    final leftCut = result.fragments.first.points.last;
    final rightCut = result.fragments.last.points.first;
    expect(leftCut.x, closeTo(0.44, 1e-9));
    expect(rightCut.x, closeTo(0.56, 1e-9));
    expect(leftCut.pressure, closeTo(0.48, 1e-9));
    expect(rightCut.pressure, closeTo(0.72, 1e-9));
    expect(leftCut.tilt, closeTo(0.24, 1e-9));
    expect(rightCut.tilt, closeTo(0.36, 1e-9));
    expect(leftCut.timestampMicros, 240);
    expect(rightCut.timestampMicros, 360);
    expect(result.fragments.first.id, startsWith('stroke-1-e-'));
    expect(result.fragments.last.id, isNot(result.fragments.first.id));
  });

  test('não altera o traço quando a borracha não o alcança', () {
    final stroke = strokeWith(const [
      InkPoint(x: 0.10, y: 0.10, pressure: 1, tilt: 0, timestampMicros: 1),
      InkPoint(x: 0.20, y: 0.20, pressure: 1, tilt: 0, timestampMicros: 2),
      InkPoint(x: 0.30, y: 0.30, pressure: 1, tilt: 0, timestampMicros: 3),
    ]);

    final result = const PdfInkEraser().eraseAt(
      stroke: stroke,
      localX: 900,
      localY: 900,
      pageWidth: 1000,
      pageHeight: 1000,
      radius: 30,
    );

    expect(result, isNull);
  });

  test('remove todo o traço quando ele fica dentro da borracha', () {
    final stroke = strokeWith(const [
      InkPoint(x: 0.49, y: 0.50, pressure: 1, tilt: 0, timestampMicros: 1),
      InkPoint(x: 0.51, y: 0.50, pressure: 1, tilt: 0, timestampMicros: 2),
    ]);

    final result = const PdfInkEraser().eraseAt(
      stroke: stroke,
      localX: 500,
      localY: 500,
      pageWidth: 1000,
      pageHeight: 1000,
      radius: 30,
    );

    expect(result, isNotNull);
    expect(result!.fragments, isEmpty);
  });
}

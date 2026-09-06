import 'package:flutter_test/flutter_test.dart';
import 'package:lexxpdf_app/src/core/ink/ink_models.dart';
import 'package:lexxpdf_app/src/core/ink/pdf_ink_eraser.dart';
import 'package:lexxpdf_app/src/core/ink/pdf_ink_models.dart';

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

  test('divide um traço quando a borracha cruza seu trecho central', () {
    final stroke = strokeWith(const [
      InkPoint(x: 0.10, y: 0.50, pressure: 1, tilt: 0, timestampMicros: 1),
      InkPoint(x: 0.20, y: 0.50, pressure: 1, tilt: 0, timestampMicros: 2),
      InkPoint(x: 0.30, y: 0.50, pressure: 1, tilt: 0, timestampMicros: 3),
      InkPoint(x: 0.40, y: 0.50, pressure: 1, tilt: 0, timestampMicros: 4),
      InkPoint(x: 0.50, y: 0.50, pressure: 1, tilt: 0, timestampMicros: 5),
      InkPoint(x: 0.60, y: 0.50, pressure: 1, tilt: 0, timestampMicros: 6),
      InkPoint(x: 0.70, y: 0.50, pressure: 1, tilt: 0, timestampMicros: 7),
      InkPoint(x: 0.80, y: 0.50, pressure: 1, tilt: 0, timestampMicros: 8),
      InkPoint(x: 0.90, y: 0.50, pressure: 1, tilt: 0, timestampMicros: 9),
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
    expect(result.fragments.first.points.first.x, 0.10);
    expect(result.fragments.first.points.last.x, 0.30);
    expect(result.fragments.last.points.first.x, 0.70);
    expect(result.fragments.last.points.last.x, 0.90);
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

  test('remove todo o traço quando não sobra fragmento desenhável', () {
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

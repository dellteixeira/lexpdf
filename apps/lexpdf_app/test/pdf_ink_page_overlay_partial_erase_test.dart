import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexxpdf_app/src/core/ink/ink_models.dart';
import 'package:lexxpdf_app/src/core/ink/pdf_ink_models.dart';
import 'package:lexxpdf_app/src/widgets/pdf_ink_page_overlay.dart';

void main() {
  testWidgets(
    'borracha parcial remove original e emite fragmentos persistíveis',
    (tester) async {
      final original = PdfInkStroke(
        id: 'stroke-1',
        documentId: 'doc-1',
        pageNumber: 1,
        tool: InkTool.pen,
        colorValue: 0xFF246BFD,
        opacity: 1,
        width: 3,
        points: const [
          InkPoint(x: 0.1, y: 0.5, pressure: 1, tilt: 0, timestampMicros: 1),
          InkPoint(x: 0.3, y: 0.5, pressure: 1, tilt: 0, timestampMicros: 2),
          InkPoint(x: 0.5, y: 0.5, pressure: 1, tilt: 0, timestampMicros: 3),
          InkPoint(x: 0.7, y: 0.5, pressure: 1, tilt: 0, timestampMicros: 4),
          InkPoint(x: 0.9, y: 0.5, pressure: 1, tilt: 0, timestampMicros: 5),
        ],
        createdAt: DateTime.utc(2026, 9, 6),
      );

      PdfInkStroke? erased;
      final completed = <PdfInkStroke>[];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox.square(
                dimension: 100,
                child: PdfInkPageOverlay(
                  documentId: 'doc-1',
                  pageNumber: 1,
                  strokes: [original],
                  enabled: true,
                  tool: InkTool.pen,
                  colorValue: 0xFF246BFD,
                  strokeWidth: 3,
                  eraserMode: true,
                  eraserRadius: 8,
                  onStrokeCompleted: completed.add,
                  onStrokeErased: (stroke) => erased = stroke,
                ),
              ),
            ),
          ),
        ),
      );

      final center = tester.getCenter(find.byType(PdfInkPageOverlay));
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.down(center);
      await gesture.up();
      await tester.pump();

      expect(erased?.id, original.id);
      expect(completed, hasLength(2));
      expect(completed.every((fragment) => fragment.id.startsWith('stroke-1-e')), isTrue);
      expect(completed.every((fragment) => fragment.points.length >= 2), isTrue);
    },
  );
}

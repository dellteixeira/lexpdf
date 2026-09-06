import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexxpdf_app/src/core/ink/ink_models.dart';
import 'package:lexxpdf_app/src/widgets/ink_canvas.dart';

void main() {
  testWidgets('moveSelected desloca apenas strokes selecionados', (tester) async {
    final key = GlobalKey<InkCanvasState>();
    final updated = <InkStroke>[];
    final strokes = [
      InkStroke(
        id: 'inside',
        pageId: 'page-1',
        tool: InkTool.pen,
        colorValue: 0xFF000000,
        opacity: 1,
        width: 3,
        points: const [
          InkPoint(x: 30, y: 30, pressure: 1, tilt: 0, timestampMicros: 1),
          InkPoint(x: 50, y: 50, pressure: 1, tilt: 0, timestampMicros: 2),
        ],
        createdAt: DateTime.utc(2026, 9, 6),
      ),
      InkStroke(
        id: 'outside',
        pageId: 'page-1',
        tool: InkTool.pen,
        colorValue: 0xFF000000,
        opacity: 1,
        width: 3,
        points: const [
          InkPoint(x: 150, y: 150, pressure: 1, tilt: 0, timestampMicros: 3),
          InkPoint(x: 170, y: 170, pressure: 1, tilt: 0, timestampMicros: 4),
        ],
        createdAt: DateTime.utc(2026, 9, 6),
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 200,
            height: 200,
            child: InkCanvas(
              key: key,
              initialStrokes: strokes,
              pageId: 'page-1',
              tool: InkTool.pen,
              colorValue: 0xFF000000,
              strokeWidth: 3,
              lassoMode: true,
              stylusOnly: false,
              onStrokeCompleted: (_) {},
              onStrokeUpdated: updated.add,
            ),
          ),
        ),
      ),
    );

    final gesture = await tester.startGesture(const Offset(10, 10));
    await gesture.moveTo(const Offset(100, 10));
    await gesture.moveTo(const Offset(100, 100));
    await gesture.moveTo(const Offset(10, 100));
    await gesture.moveTo(const Offset(10, 10));
    await gesture.up();
    await tester.pump();

    expect(key.currentState!.selectedStrokeIds, {'inside'});

    final moved = key.currentState!.moveSelected(12, -8);
    expect(moved, hasLength(1));
    expect(moved.single.id, 'inside');
    expect(moved.single.points.first.x, 42);
    expect(moved.single.points.first.y, 22);
    expect(updated.single.id, 'inside');

    final outside = key.currentState!.strokes.singleWhere((s) => s.id == 'outside');
    expect(outside.points.first.x, 150);
    expect(outside.points.first.y, 150);
  });
}

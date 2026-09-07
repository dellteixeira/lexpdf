import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexpdf_app/src/core/ink/ink_models.dart';
import 'package:lexpdf_app/src/widgets/ink_canvas.dart';

void main() {
  testWidgets('cor e espessura alteram apenas strokes selecionados', (tester) async {
    final key = GlobalKey<InkCanvasState>();
    final updated = <InkStroke>[];
    final strokes = [
      InkStroke(
        id: 'inside',
        pageId: 'page-1',
        tool: InkTool.pen,
        colorValue: 0xFF000000,
        opacity: 1,
        width: 4,
        points: const [
          InkPoint(x: 30, y: 30, pressure: 0.7, tilt: 0.2, timestampMicros: 1),
          InkPoint(x: 50, y: 50, pressure: 0.8, tilt: 0.3, timestampMicros: 2),
        ],
        createdAt: DateTime.utc(2026, 9, 6),
      ),
      InkStroke(
        id: 'outside',
        pageId: 'page-1',
        tool: InkTool.pen,
        colorValue: 0xFF111111,
        opacity: 1,
        width: 7,
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

    final recolored = key.currentState!.updateSelectedColor(0xFFD32F2F);
    expect(recolored.single.colorValue, 0xFFD32F2F);
    expect(recolored.single.width, 4);

    final widened = key.currentState!.adjustSelectedWidth(1.5);
    expect(widened.single.width, 6);
    expect(widened.single.colorValue, 0xFFD32F2F);
    expect(widened.single.points.first.pressure, 0.7);
    expect(updated, hasLength(2));

    final outside = key.currentState!.strokes.singleWhere((s) => s.id == 'outside');
    expect(outside.colorValue, 0xFF111111);
    expect(outside.width, 7);
  });

  testWidgets('ajuste de espessura respeita limites seguros', (tester) async {
    final key = GlobalKey<InkCanvasState>();
    final stroke = InkStroke(
      id: 'inside',
      pageId: 'page-1',
      tool: InkTool.pen,
      colorValue: 0xFF000000,
      opacity: 1,
      width: 1,
      points: const [
        InkPoint(x: 30, y: 30, pressure: 1, tilt: 0, timestampMicros: 1),
        InkPoint(x: 50, y: 50, pressure: 1, tilt: 0, timestampMicros: 2),
      ],
      createdAt: DateTime.utc(2026, 9, 6),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 200,
            height: 200,
            child: InkCanvas(
              key: key,
              initialStrokes: [stroke],
              pageId: 'page-1',
              tool: InkTool.pen,
              colorValue: 0xFF000000,
              strokeWidth: 3,
              lassoMode: true,
              stylusOnly: false,
              onStrokeCompleted: (_) {},
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

    expect(key.currentState!.adjustSelectedWidth(0.01).single.width, 0.25);
    expect(key.currentState!.adjustSelectedWidth(1000).single.width, 100);
  });
}

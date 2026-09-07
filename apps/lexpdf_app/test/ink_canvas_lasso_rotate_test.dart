import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexpdf_app/src/core/ink/ink_models.dart';
import 'package:lexpdf_app/src/widgets/ink_canvas.dart';

void main() {
  testWidgets('rotateSelected gira apenas a seleção em torno do centro', (tester) async {
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
          InkPoint(x: 30, y: 40, pressure: 0.7, tilt: 0.2, timestampMicros: 1),
          InkPoint(x: 70, y: 40, pressure: 0.8, tilt: 0.3, timestampMicros: 2),
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

    final rotated = key.currentState!.rotateSelected(math.pi / 2);
    expect(rotated, hasLength(1));
    expect(rotated.single.id, 'inside');
    expect(rotated.single.width, 3);
    expect(rotated.single.points.first.x, closeTo(50, 0.0001));
    expect(rotated.single.points.first.y, closeTo(20, 0.0001));
    expect(rotated.single.points.last.x, closeTo(50, 0.0001));
    expect(rotated.single.points.last.y, closeTo(60, 0.0001));
    expect(rotated.single.points.first.pressure, 0.7);
    expect(rotated.single.points.first.tilt, 0.2);
    expect(updated.single.id, 'inside');

    final outside = key.currentState!.strokes.singleWhere((s) => s.id == 'outside');
    expect(outside.points.first.x, 150);
    expect(outside.points.first.y, 150);
  });
}

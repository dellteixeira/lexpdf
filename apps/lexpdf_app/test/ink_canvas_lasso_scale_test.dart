import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexxpdf_app/src/core/ink/ink_models.dart';
import 'package:lexxpdf_app/src/core/storage/local_database.dart';
import 'package:lexxpdf_app/src/core/storage/local_ink_store.dart';
import 'package:lexxpdf_app/src/widgets/ink_canvas.dart';

void main() {
  testWidgets('scaleSelected redimensiona seleção ao redor do centro', (tester) async {
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
          InkPoint(x: 30, y: 30, pressure: 0.5, tilt: 0.1, timestampMicros: 1),
          InkPoint(x: 50, y: 50, pressure: 0.9, tilt: 0.2, timestampMicros: 2),
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

    final scaled = key.currentState!.scaleSelected(2);
    expect(scaled, hasLength(1));
    expect(scaled.single.id, 'inside');
    expect(scaled.single.points.first.x, 20);
    expect(scaled.single.points.first.y, 20);
    expect(scaled.single.points.last.x, 60);
    expect(scaled.single.points.last.y, 60);
    expect(scaled.single.width, 8);
    expect(scaled.single.points.first.pressure, 0.5);
    expect(scaled.single.points.first.tilt, 0.1);
    expect(updated.single.id, 'inside');

    final outside = key.currentState!.strokes.singleWhere((s) => s.id == 'outside');
    expect(outside.points.first.x, 150);
    expect(outside.points.first.y, 150);
    expect(outside.width, 3);
  });

  test('upsert persiste escala mantendo o mesmo stroke', () async {
    final database = LocalDatabase.inMemory();
    addTearDown(database.close);
    final store = LocalInkStore(database);
    final page = await store.ensureDefaultPage();

    final original = InkStroke(
      id: 'scale-persist',
      pageId: page.id,
      tool: InkTool.pen,
      colorValue: 0xFF246BFD,
      opacity: 1,
      width: 4,
      points: const [
        InkPoint(x: 20, y: 20, pressure: 1, tilt: 0, timestampMicros: 1),
        InkPoint(x: 40, y: 40, pressure: 1, tilt: 0, timestampMicros: 2),
      ],
      createdAt: DateTime.utc(2026, 9, 6),
    );
    await store.addStroke(original);

    final scaled = InkStroke(
      id: original.id,
      pageId: original.pageId,
      tool: original.tool,
      colorValue: original.colorValue,
      opacity: original.opacity,
      width: 8,
      points: const [
        InkPoint(x: 10, y: 10, pressure: 1, tilt: 0, timestampMicros: 1),
        InkPoint(x: 50, y: 50, pressure: 1, tilt: 0, timestampMicros: 2),
      ],
      createdAt: original.createdAt,
    );
    await store.addStroke(scaled);

    final restored = await store.listStrokes(page.id);
    expect(restored, hasLength(1));
    expect(restored.single.id, original.id);
    expect(restored.single.width, 8);
    expect(restored.single.points.first.x, 10);
    expect(restored.single.points.last.x, 50);
  });
}

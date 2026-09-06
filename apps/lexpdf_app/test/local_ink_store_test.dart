import 'package:flutter_test/flutter_test.dart';
import 'package:lexxpdf_app/src/core/ink/ink_models.dart';
import 'package:lexxpdf_app/src/core/storage/local_database.dart';
import 'package:lexxpdf_app/src/core/storage/local_ink_store.dart';

void main() {
  test('persists pressure-aware vector strokes offline', () async {
    final database = LocalDatabase.inMemory();
    addTearDown(database.close);
    final store = LocalInkStore(database);
    final page = await store.ensureDefaultPage();

    final stroke = InkStroke(
      id: 'stroke-1',
      pageId: page.id,
      tool: InkTool.pen,
      colorValue: 0xFF246BFD,
      opacity: 1,
      width: 3,
      createdAt: DateTime.utc(2026, 9, 6),
      points: const [
        InkPoint(x: 10, y: 20, pressure: 0.2, tilt: 0.1, timestampMicros: 1),
        InkPoint(x: 30, y: 40, pressure: 0.8, tilt: 0.2, timestampMicros: 2),
      ],
    );

    await store.addStroke(stroke);
    final restored = await store.listStrokes(page.id);

    expect(restored, hasLength(1));
    expect(restored.single.tool, InkTool.pen);
    expect(restored.single.points, hasLength(2));
    expect(restored.single.points.last.pressure, 0.8);
    expect(restored.single.colorValue, 0xFF246BFD);
  });

  test('supports undo persistence by deleting a stroke', () async {
    final database = LocalDatabase.inMemory();
    addTearDown(database.close);
    final store = LocalInkStore(database);
    final page = await store.ensureDefaultPage();

    await store.addStroke(InkStroke(
      id: 'stroke-delete',
      pageId: page.id,
      tool: InkTool.highlighter,
      colorValue: 0xFFFFD54F,
      opacity: 0.28,
      width: 15,
      points: const [
        InkPoint(x: 0, y: 0, pressure: 1, tilt: 0, timestampMicros: 1),
        InkPoint(x: 50, y: 50, pressure: 1, tilt: 0, timestampMicros: 2),
      ],
      createdAt: DateTime.utc(2026, 9, 6),
    ));

    await store.deleteStroke('stroke-delete');
    expect(await store.listStrokes(page.id), isEmpty);
  });
}

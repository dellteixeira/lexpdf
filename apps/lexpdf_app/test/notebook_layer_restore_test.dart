import 'package:flutter_test/flutter_test.dart';
import 'package:lexxpdf_app/src/core/ink/ink_models.dart';
import 'package:lexxpdf_app/src/core/notebook/notebook_object_models.dart';
import 'package:lexxpdf_app/src/core/storage/local_database.dart';
import 'package:lexxpdf_app/src/core/storage/local_ink_store.dart';
import 'package:lexxpdf_app/src/core/storage/local_notebook_layer_store.dart';
import 'package:lexxpdf_app/src/core/storage/local_notebook_object_store.dart';

void main() {
  test('replaceAssignments restores layer memberships after content replacement', () async {
    final db = LocalDatabase.inMemory();
    addTearDown(db.close);
    final ink = LocalInkStore(db);
    final objects = LocalNotebookObjectStore(db);
    final layers = LocalNotebookLayerStore(db);
    final page = await ink.ensureDefaultPage();
    final base = await layers.ensureDefaultLayer(page.id);
    final second = await layers.createLayer(page.id, name: 'Segunda');
    final now = DateTime.utc(2026, 9, 6);

    final stroke = InkStroke(
      id: 'restore-stroke',
      pageId: page.id,
      tool: InkTool.pen,
      colorValue: 0xFF000000,
      opacity: 1,
      width: 2,
      points: const [InkPoint(x: 10, y: 10, pressure: 1, tilt: 0, timestampMicros: 1)],
      createdAt: now,
    );
    final object = NotebookObject(
      id: 'restore-object',
      pageId: page.id,
      type: NotebookObjectType.text,
      x: 5,
      y: 5,
      width: 100,
      height: 40,
      rotation: 0,
      colorValue: 0xFF000000,
      strokeWidth: 1,
      textValue: 'Camada',
      fontSize: 18,
      createdAt: now,
      updatedAt: now,
    );

    await ink.addStroke(stroke);
    await objects.upsert(object);
    await layers.assignStroke(second.id, stroke.id);
    await layers.assignObject(base.id, object.id);

    await ink.replacePageStrokes(page.id, [stroke]);
    await objects.replacePageObjects(page.id, [object]);
    expect(await layers.layerIdForItem(NotebookLayerItemType.stroke, stroke.id), isNull);
    expect(await layers.layerIdForItem(NotebookLayerItemType.object, object.id), isNull);

    await layers.replaceAssignments(
      pageId: page.id,
      strokeLayerIds: {stroke.id: second.id},
      objectLayerIds: {object.id: base.id},
    );

    expect(await layers.layerIdForItem(NotebookLayerItemType.stroke, stroke.id), second.id);
    expect(await layers.layerIdForItem(NotebookLayerItemType.object, object.id), base.id);
    expect(db.database.select('PRAGMA foreign_key_check;'), isEmpty);
  });
}

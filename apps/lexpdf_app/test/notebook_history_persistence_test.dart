import 'package:flutter_test/flutter_test.dart';
import 'package:lexxpdf_app/src/core/ink/ink_models.dart';
import 'package:lexxpdf_app/src/core/notebook/notebook_object_models.dart';
import 'package:lexxpdf_app/src/core/storage/local_database.dart';
import 'package:lexxpdf_app/src/core/storage/local_ink_store.dart';
import 'package:lexxpdf_app/src/core/storage/local_notebook_object_store.dart';

void main() {
  test('restores strokes and objects for the same notebook page', () async {
    final database = LocalDatabase.inMemory();
    addTearDown(database.close);
    final inkStore = LocalInkStore(database);
    final objectStore = LocalNotebookObjectStore(database);
    final page = await inkStore.ensureDefaultPage();
    final now = DateTime.utc(2026, 9, 6);

    final originalStroke = InkStroke(
      id: 'stroke-original',
      pageId: page.id,
      tool: InkTool.pen,
      colorValue: 0xFF246BFD,
      opacity: 1,
      width: 3,
      points: const [
        InkPoint(x: 10, y: 10, pressure: 1, tilt: 0, timestampMicros: 1),
        InkPoint(x: 30, y: 30, pressure: 1, tilt: 0, timestampMicros: 2),
      ],
      createdAt: now,
    );
    final originalObject = NotebookObject(
      id: 'object-original',
      pageId: page.id,
      type: NotebookObjectType.rectangle,
      x: 20,
      y: 20,
      width: 100,
      height: 60,
      rotation: 0,
      colorValue: 0xFF000000,
      strokeWidth: 2,
      createdAt: now,
      updatedAt: now,
    );

    await inkStore.replacePageStrokes(page.id, [originalStroke]);
    await objectStore.replacePageObjects(page.id, [originalObject]);

    await inkStore.replacePageStrokes(page.id, const []);
    await objectStore.replacePageObjects(page.id, const []);
    expect(await inkStore.listStrokes(page.id), isEmpty);
    expect(await objectStore.listObjects(page.id), isEmpty);

    await inkStore.replacePageStrokes(page.id, [originalStroke]);
    await objectStore.replacePageObjects(page.id, [originalObject]);

    final strokes = await inkStore.listStrokes(page.id);
    final objects = await objectStore.listObjects(page.id);
    expect(strokes, hasLength(1));
    expect(strokes.single.id, 'stroke-original');
    expect(objects, hasLength(1));
    expect(objects.single.id, 'object-original');
  });

  test('rejects a snapshot containing content from another page', () async {
    final database = LocalDatabase.inMemory();
    addTearDown(database.close);
    final inkStore = LocalInkStore(database);
    final objectStore = LocalNotebookObjectStore(database);
    final notebook = await inkStore.createNotebook('History');
    final first = (await inkStore.listPages(notebook.id)).single;
    final second = await inkStore.createPage(notebook.id);
    final now = DateTime.utc(2026, 9, 6);

    final foreignStroke = InkStroke(
      id: 'foreign-stroke',
      pageId: second.id,
      tool: InkTool.pen,
      colorValue: 0xFF000000,
      opacity: 1,
      width: 2,
      points: const [
        InkPoint(x: 0, y: 0, pressure: 1, tilt: 0, timestampMicros: 1),
        InkPoint(x: 1, y: 1, pressure: 1, tilt: 0, timestampMicros: 2),
      ],
      createdAt: now,
    );
    final foreignObject = NotebookObject(
      id: 'foreign-object',
      pageId: second.id,
      type: NotebookObjectType.line,
      x: 0,
      y: 0,
      width: 10,
      height: 10,
      rotation: 0,
      colorValue: 0xFF000000,
      strokeWidth: 1,
      createdAt: now,
      updatedAt: now,
    );

    await expectLater(
      inkStore.replacePageStrokes(first.id, [foreignStroke]),
      throwsStateError,
    );
    await expectLater(
      objectStore.replacePageObjects(first.id, [foreignObject]),
      throwsStateError,
    );
  });
}

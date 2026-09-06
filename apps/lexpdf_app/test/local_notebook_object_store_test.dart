import 'package:flutter_test/flutter_test.dart';
import 'package:lexxpdf_app/src/core/notebook/notebook_object_models.dart';
import 'package:lexxpdf_app/src/core/storage/local_database.dart';
import 'package:lexxpdf_app/src/core/storage/local_ink_store.dart';
import 'package:lexxpdf_app/src/core/storage/local_notebook_object_store.dart';

void main() {
  test('schema 6 persists notebook objects offline', () async {
    final database = LocalDatabase.inMemory();
    addTearDown(database.close);
    expect(database.database.userVersion, 6);

    final inkStore = LocalInkStore(database);
    final page = await inkStore.ensureDefaultPage();
    final store = LocalNotebookObjectStore(database);
    final now = DateTime.utc(2026, 9, 6);

    final object = NotebookObject(
      id: 'object-1',
      pageId: page.id,
      type: NotebookObjectType.rectangle,
      x: 20,
      y: 30,
      width: 120,
      height: 80,
      rotation: 0,
      colorValue: 0xFF246BFD,
      fillColorValue: 0x22246BFD,
      strokeWidth: 3,
      createdAt: now,
      updatedAt: now,
    );

    await store.upsert(object);
    final restored = await store.listObjects(page.id);

    expect(restored, hasLength(1));
    expect(restored.single.type, NotebookObjectType.rectangle);
    expect(restored.single.width, 120);
    expect(restored.single.fillColorValue, 0x22246BFD);
  });

  test('upsert updates object geometry without duplicating id', () async {
    final database = LocalDatabase.inMemory();
    addTearDown(database.close);
    final inkStore = LocalInkStore(database);
    final page = await inkStore.ensureDefaultPage();
    final store = LocalNotebookObjectStore(database);
    final now = DateTime.utc(2026, 9, 6);

    final original = NotebookObject(
      id: 'shape',
      pageId: page.id,
      type: NotebookObjectType.ellipse,
      x: 10,
      y: 10,
      width: 100,
      height: 80,
      rotation: 0,
      colorValue: 0xFF000000,
      strokeWidth: 2,
      createdAt: now,
      updatedAt: now,
    );
    await store.upsert(original);
    await store.upsert(
      original.copyWith(
        x: 40,
        rotation: 0.5,
        updatedAt: now.add(const Duration(seconds: 1)),
      ),
    );

    final restored = await store.listObjects(page.id);
    expect(restored, hasLength(1));
    expect(restored.single.x, 40);
    expect(restored.single.rotation, 0.5);
  });

  test('page delete cascades notebook objects', () async {
    final database = LocalDatabase.inMemory();
    addTearDown(database.close);
    final inkStore = LocalInkStore(database);
    final notebook = await inkStore.createNotebook('Objetos');
    final page = (await inkStore.listPages(notebook.id)).single;
    final store = LocalNotebookObjectStore(database);
    final now = DateTime.utc(2026, 9, 6);

    await store.upsert(NotebookObject(
      id: 'shape-delete',
      pageId: page.id,
      type: NotebookObjectType.line,
      x: 0,
      y: 0,
      width: 50,
      height: 50,
      rotation: 0,
      colorValue: 0xFF000000,
      strokeWidth: 2,
      createdAt: now,
      updatedAt: now,
    ));

    await inkStore.deletePage(page.id);
    expect(await store.listObjects(page.id), isEmpty);
  });
}

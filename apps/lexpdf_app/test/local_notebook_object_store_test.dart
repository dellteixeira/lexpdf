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

  test('persists editable text and local image metadata', () async {
    final database = LocalDatabase.inMemory();
    addTearDown(database.close);
    final inkStore = LocalInkStore(database);
    final page = await inkStore.ensureDefaultPage();
    final store = LocalNotebookObjectStore(database);
    final now = DateTime.utc(2026, 9, 6);

    await store.upsert(NotebookObject(
      id: 'text-1',
      pageId: page.id,
      type: NotebookObjectType.text,
      x: 10,
      y: 20,
      width: 220,
      height: 80,
      rotation: 0,
      colorValue: 0xFF246BFD,
      strokeWidth: 1,
      textValue: 'Texto editável',
      fontSize: 24,
      createdAt: now,
      updatedAt: now,
    ));
    await store.upsert(NotebookObject(
      id: 'image-1',
      pageId: page.id,
      type: NotebookObjectType.image,
      x: 30,
      y: 40,
      width: 260,
      height: 180,
      rotation: 0.25,
      colorValue: 0xFF000000,
      strokeWidth: 1,
      imagePath: '/local/notebook_assets/image.png',
      createdAt: now,
      updatedAt: now,
    ));

    final restored = await store.listObjects(page.id);
    expect(restored, hasLength(2));
    final text = restored.singleWhere((item) => item.id == 'text-1');
    final image = restored.singleWhere((item) => item.id == 'image-1');
    expect(text.textValue, 'Texto editável');
    expect(text.fontSize, 24);
    expect(image.imagePath, '/local/notebook_assets/image.png');
    expect(image.rotation, 0.25);
  });

  test('copies all page objects using new ids', () async {
    final database = LocalDatabase.inMemory();
    addTearDown(database.close);
    final inkStore = LocalInkStore(database);
    final notebook = await inkStore.createNotebook('Cópia de objetos');
    final source = (await inkStore.listPages(notebook.id)).single;
    final target = await inkStore.createPage(notebook.id);
    final store = LocalNotebookObjectStore(database);
    final now = DateTime.utc(2026, 9, 6);

    await store.upsert(NotebookObject(
      id: 'source-object',
      pageId: source.id,
      type: NotebookObjectType.text,
      x: 12,
      y: 24,
      width: 180,
      height: 70,
      rotation: 0,
      colorValue: 0xFF000000,
      strokeWidth: 1,
      textValue: 'Copiado',
      fontSize: 18,
      createdAt: now,
      updatedAt: now,
    ));

    final copies = await store.copyPageObjects(source.id, target.id);
    expect(copies, hasLength(1));
    expect(copies.single.id, isNot('source-object'));
    expect(copies.single.pageId, target.id);
    expect(copies.single.textValue, 'Copiado');
    expect(await store.listObjects(target.id), hasLength(1));
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

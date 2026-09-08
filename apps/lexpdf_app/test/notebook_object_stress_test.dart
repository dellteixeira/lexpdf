import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lexpdf_app/src/core/notebook/notebook_object_models.dart';
import 'package:lexpdf_app/src/core/storage/local_database.dart';
import 'package:lexpdf_app/src/core/storage/local_ink_store.dart';
import 'package:lexpdf_app/src/core/storage/local_notebook_layer_store.dart';
import 'package:lexpdf_app/src/core/storage/local_notebook_object_store.dart';

void main() {
  test('hundreds of notebook objects keep edits and layer assignments across reopen', () async {
    final directory = await Directory.systemTemp.createTemp('lexpdf-object-stress-');
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}${Platform.pathSeparator}notebook.db';

    const objectCount = 210;
    const layerCount = 10;
    final createdIds = <String>[];
    late String pageId;
    late String notebookId;

    var db = LocalDatabase.open(path);
    var ink = LocalInkStore(db);
    var objects = LocalNotebookObjectStore(db);
    var layers = LocalNotebookLayerStore(db);

    final notebook = await ink.createNotebook('Object stress');
    notebookId = notebook.id;
    final page = (await ink.listPages(notebook.id)).single;
    pageId = page.id;

    final layerList = <NotebookLayer>[await layers.ensureDefaultLayer(page.id)];
    for (var index = 1; index < layerCount; index++) {
      layerList.add(await layers.createLayer(page.id, name: 'Layer $index'));
    }

    final types = NotebookObjectType.values;
    final base = DateTime.utc(2026, 9, 8, 12);
    for (var index = 0; index < objectCount; index++) {
      final id = 'object-$index';
      createdIds.add(id);
      final type = types[index % types.length];
      await objects.upsert(
        NotebookObject(
          id: id,
          pageId: page.id,
          type: type,
          x: (index % 20) * 8.0,
          y: (index ~/ 20) * 9.0,
          width: 30 + (index % 7).toDouble(),
          height: 20 + (index % 5).toDouble(),
          rotation: (index % 12) * 5.0,
          colorValue: 0xFF000000 + index,
          fillColorValue: index.isEven ? 0x11000000 + index : null,
          strokeWidth: 1 + (index % 4).toDouble(),
          textValue: type == NotebookObjectType.text ? 'Text $index' : null,
          fontSize: type == NotebookObjectType.text ? 12 + (index % 6).toDouble() : null,
          imagePath: type == NotebookObjectType.image ? '/tmp/image-$index.png' : null,
          createdAt: base.add(Duration(seconds: index)),
          updatedAt: base.add(Duration(seconds: index)),
        ),
      );
      await layers.assignObject(layerList[index % layerCount].id, id);
    }

    expect(await objects.listObjects(page.id), hasLength(objectCount));
    expect(
      await layers.itemLayerMap(page.id, NotebookLayerItemType.object),
      hasLength(objectCount),
    );

    final beforeUpdates = await objects.listObjects(page.id);
    for (var index = 0; index < beforeUpdates.length; index += 7) {
      final current = beforeUpdates[index];
      await objects.upsert(
        current.copyWith(
          x: current.x + 100,
          y: current.y + 50,
          rotation: current.rotation + 15,
          colorValue: 0xFF246BFD,
          textValue: current.type == NotebookObjectType.text
              ? 'Edited ${current.id}'
              : current.textValue,
          updatedAt: base.add(const Duration(days: 1)),
        ),
      );
    }

    final reversedLayerIds = layerList.reversed.map((layer) => layer.id).toList();
    await layers.reorderLayers(page.id, reversedLayerIds);

    db.close();

    db = LocalDatabase.open(path);
    ink = LocalInkStore(db);
    objects = LocalNotebookObjectStore(db);
    layers = LocalNotebookLayerStore(db);
    addTearDown(db.close);

    final restoredPages = await ink.listPages(notebookId);
    expect(restoredPages.map((value) => value.id), contains(pageId));

    final restoredObjects = await objects.listObjects(pageId);
    expect(restoredObjects, hasLength(objectCount));
    expect(restoredObjects.map((value) => value.id).toSet(), createdIds.toSet());

    final edited = restoredObjects.firstWhere((value) => value.id == 'object-0');
    expect(edited.x, 100);
    expect(edited.y, 50);
    expect(edited.rotation, 15);
    expect(edited.colorValue, 0xFF246BFD);

    final restoredAssignments =
        await layers.itemLayerMap(pageId, NotebookLayerItemType.object);
    expect(restoredAssignments, hasLength(objectCount));
    for (var index = 0; index < objectCount; index++) {
      expect(restoredAssignments['object-$index'], isNotNull);
    }

    final restoredLayers = await layers.listLayers(pageId);
    expect(restoredLayers, hasLength(layerCount));
    expect(restoredLayers.map((layer) => layer.id), reversedLayerIds);
    expect(db.database.select('PRAGMA foreign_key_check;'), isEmpty);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('copying a page clones objects without reusing object ids', () async {
    final db = LocalDatabase.inMemory();
    addTearDown(db.close);
    final ink = LocalInkStore(db);
    final objects = LocalNotebookObjectStore(db);

    final notebook = await ink.createNotebook('Copy objects');
    final source = (await ink.listPages(notebook.id)).single;
    final target = await ink.createPage(notebook.id);
    final now = DateTime.utc(2026, 9, 8);

    for (var index = 0; index < 25; index++) {
      await objects.upsert(
        NotebookObject(
          id: 'source-$index',
          pageId: source.id,
          type: NotebookObjectType.rectangle,
          x: index.toDouble(),
          y: index.toDouble(),
          width: 20,
          height: 10,
          rotation: 0,
          colorValue: 0xFF000000,
          strokeWidth: 2,
          createdAt: now.add(Duration(seconds: index)),
          updatedAt: now.add(Duration(seconds: index)),
        ),
      );
    }

    final copied = await objects.copyPageObjects(source.id, target.id);
    expect(copied, hasLength(25));
    expect(copied.every((object) => object.pageId == target.id), isTrue);
    expect(
      copied.map((object) => object.id).toSet().intersection(
            (await objects.listObjects(source.id)).map((object) => object.id).toSet(),
          ),
      isEmpty,
    );
    expect(await objects.listObjects(target.id), hasLength(25));
  });
}

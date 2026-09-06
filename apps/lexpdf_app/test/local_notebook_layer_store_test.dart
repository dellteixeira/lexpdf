import 'package:flutter_test/flutter_test.dart';
import 'package:lexxpdf_app/src/core/ink/ink_models.dart';
import 'package:lexxpdf_app/src/core/storage/local_database.dart';
import 'package:lexxpdf_app/src/core/storage/local_ink_store.dart';
import 'package:lexxpdf_app/src/core/storage/local_notebook_layer_store.dart';

void main() {
  test('schema 8 creates and persists ordered notebook layers', () async {
    final database = LocalDatabase.inMemory();
    addTearDown(database.close);
    expect(database.database.userVersion, 8);

    final inkStore = LocalInkStore(database);
    final page = await inkStore.ensureDefaultPage();
    final layers = LocalNotebookLayerStore(database);

    final base = await layers.ensureDefaultLayer(page.id);
    final notes = await layers.createLayer(page.id, name: 'Notas');
    final emphasis = await layers.createLayer(page.id, name: 'Destaques');

    expect(await layers.listLayers(page.id), hasLength(3));
    await layers.renameLayer(notes.id, 'Anotações');
    await layers.setVisibility(emphasis.id, false);
    await layers.setLocked(notes.id, true);
    await layers.reorderLayers(page.id, [emphasis.id, base.id, notes.id]);

    final restored = await layers.listLayers(page.id);
    expect(restored.map((layer) => layer.id), [emphasis.id, base.id, notes.id]);
    expect(restored.first.sortOrder, 0);
    expect(restored.first.isVisible, isFalse);
    expect(restored.last.name, 'Anotações');
    expect(restored.last.isLocked, isTrue);
  });

  test('assigns strokes to layers and reassigns them on layer deletion', () async {
    final database = LocalDatabase.inMemory();
    addTearDown(database.close);
    final inkStore = LocalInkStore(database);
    final page = await inkStore.ensureDefaultPage();
    final layers = LocalNotebookLayerStore(database);
    final base = await layers.ensureDefaultLayer(page.id);
    final inkLayer = await layers.createLayer(page.id, name: 'Ink');
    final now = DateTime.utc(2026, 9, 6);

    await inkStore.addStroke(
      InkStroke(
        id: 'layered-stroke',
        pageId: page.id,
        tool: InkTool.pen,
        colorValue: 0xFF000000,
        opacity: 1,
        width: 3,
        points: const [
          InkPoint(x: 10, y: 10, pressure: 0.5, tilt: 0, timestampMicros: 1),
          InkPoint(x: 20, y: 20, pressure: 0.8, tilt: 0.1, timestampMicros: 2),
        ],
        createdAt: now,
      ),
    );

    await layers.assignStroke(inkLayer.id, 'layered-stroke');
    expect(
      await layers.layerIdForItem(NotebookLayerItemType.stroke, 'layered-stroke'),
      inkLayer.id,
    );

    await layers.deleteLayer(inkLayer.id);
    expect(
      await layers.layerIdForItem(NotebookLayerItemType.stroke, 'layered-stroke'),
      base.id,
    );
    expect(await layers.listLayers(page.id), hasLength(1));
    expect(
      () => layers.deleteLayer(base.id),
      throwsA(isA<StateError>()),
    );
  });

  test('rejects cross-page assignments and cleans deleted stroke mapping', () async {
    final database = LocalDatabase.inMemory();
    addTearDown(database.close);
    final inkStore = LocalInkStore(database);
    final notebook = await inkStore.createNotebook('Camadas');
    final firstPage = (await inkStore.listPages(notebook.id)).single;
    final secondPage = await inkStore.createPage(notebook.id);
    final layers = LocalNotebookLayerStore(database);
    final firstLayer = await layers.ensureDefaultLayer(firstPage.id);
    await layers.ensureDefaultLayer(secondPage.id);
    final now = DateTime.utc(2026, 9, 6);

    await inkStore.addStroke(
      InkStroke(
        id: 'second-page-stroke',
        pageId: secondPage.id,
        tool: InkTool.pencil,
        colorValue: 0xFF246BFD,
        opacity: 1,
        width: 2,
        points: const [
          InkPoint(x: 1, y: 1, pressure: 1, tilt: 0, timestampMicros: 1),
        ],
        createdAt: now,
      ),
    );

    expect(
      () => layers.assignStroke(firstLayer.id, 'second-page-stroke'),
      throwsA(isA<ArgumentError>()),
    );

    final secondLayer = (await layers.listLayers(secondPage.id)).single;
    await layers.assignStroke(secondLayer.id, 'second-page-stroke');
    await inkStore.deleteStroke('second-page-stroke');
    expect(
      await layers.layerIdForItem(NotebookLayerItemType.stroke, 'second-page-stroke'),
      isNull,
    );
    expect(database.database.select('PRAGMA foreign_key_check;'), isEmpty);
  });
}

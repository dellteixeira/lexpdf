import 'package:flutter_test/flutter_test.dart';
import 'package:lexpdf_app/src/core/ink/ink_models.dart';
import 'package:lexpdf_app/src/core/storage/local_database.dart';
import 'package:lexpdf_app/src/core/storage/local_ink_store.dart';

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

  test('addStroke atualiza pontos mantendo o mesmo id', () async {
    final database = LocalDatabase.inMemory();
    addTearDown(database.close);
    final store = LocalInkStore(database);
    final page = await store.ensureDefaultPage();
    final createdAt = DateTime.utc(2026, 9, 6);

    await store.addStroke(InkStroke(
      id: 'stroke-move',
      pageId: page.id,
      tool: InkTool.pen,
      colorValue: 0xFF246BFD,
      opacity: 1,
      width: 3,
      points: const [
        InkPoint(x: 10, y: 20, pressure: 1, tilt: 0, timestampMicros: 1),
        InkPoint(x: 30, y: 40, pressure: 1, tilt: 0, timestampMicros: 2),
      ],
      createdAt: createdAt,
    ));

    await store.addStroke(InkStroke(
      id: 'stroke-move',
      pageId: page.id,
      tool: InkTool.pen,
      colorValue: 0xFF246BFD,
      opacity: 1,
      width: 3,
      points: const [
        InkPoint(x: 22, y: 12, pressure: 1, tilt: 0, timestampMicros: 1),
        InkPoint(x: 42, y: 32, pressure: 1, tilt: 0, timestampMicros: 2),
      ],
      createdAt: createdAt,
    ));

    final restored = await store.listStrokes(page.id);
    expect(restored, hasLength(1));
    expect(restored.single.id, 'stroke-move');
    expect(restored.single.points.first.x, 22);
    expect(restored.single.points.first.y, 12);
  });

  test('creates multiple notebooks and pages offline', () async {
    final database = LocalDatabase.inMemory();
    addTearDown(database.close);
    final store = LocalInkStore(database);
    await store.ensureDefaultPage();

    final notebook = await store.createNotebook('Projetos');
    final secondPage = await store.createPage(
      notebook.id,
      background: InkPageBackground.grid,
    );

    final notebooks = await store.listNotebooks();
    final pages = await store.listPages(notebook.id);

    expect(notebooks.any((item) => item.id == notebook.id), isTrue);
    expect(pages, hasLength(2));
    expect(secondPage.pageNumber, 2);
    expect(secondPage.background, InkPageBackground.grid);
  });

  test('duplicates page with its strokes and template', () async {
    final database = LocalDatabase.inMemory();
    addTearDown(database.close);
    final store = LocalInkStore(database);
    final notebook = await store.createNotebook('Duplicação');
    final source = (await store.listPages(notebook.id)).single;
    await store.updatePageBackground(source.id, InkPageBackground.ruled);
    final resolvedSource = (await store.listPages(notebook.id)).single;

    await store.addStroke(InkStroke(
      id: 'source-stroke',
      pageId: source.id,
      tool: InkTool.pen,
      colorValue: 0xFF000000,
      opacity: 1,
      width: 3,
      points: const [
        InkPoint(x: 10, y: 10, pressure: 1, tilt: 0, timestampMicros: 1),
        InkPoint(x: 20, y: 20, pressure: 1, tilt: 0, timestampMicros: 2),
      ],
      createdAt: DateTime.utc(2026, 9, 6),
    ));

    final duplicate = await store.duplicatePage(resolvedSource);
    final duplicateStrokes = await store.listStrokes(duplicate.id);

    expect(duplicate.background, InkPageBackground.ruled);
    expect(duplicateStrokes, hasLength(1));
    expect(duplicateStrokes.single.id, isNot('source-stroke'));
    expect(duplicateStrokes.single.points.first.x, 10);
  });

  test('reorders notebook pages with stable sequential numbers', () async {
    final database = LocalDatabase.inMemory();
    addTearDown(database.close);
    final store = LocalInkStore(database);
    final notebook = await store.createNotebook('Ordem');
    await store.createPage(notebook.id);
    await store.createPage(notebook.id);
    final pages = await store.listPages(notebook.id);

    await store.reorderPages(
      notebook.id,
      [pages[2].id, pages[0].id, pages[1].id],
    );

    final reordered = await store.listPages(notebook.id);
    expect(reordered.map((page) => page.id).toList(), [
      pages[2].id,
      pages[0].id,
      pages[1].id,
    ]);
    expect(reordered.map((page) => page.pageNumber).toList(), [1, 2, 3]);
  });

  test('renames and deletes notebooks with cascading pages', () async {
    final database = LocalDatabase.inMemory();
    addTearDown(database.close);
    final store = LocalInkStore(database);
    final notebook = await store.createNotebook('Temporário');
    final page = (await store.listPages(notebook.id)).single;

    await store.renameNotebook(notebook.id, 'Renomeado');
    expect(
      (await store.listNotebooks()).singleWhere((item) => item.id == notebook.id).title,
      'Renomeado',
    );

    await store.deleteNotebook(notebook.id);
    expect((await store.listNotebooks()).any((item) => item.id == notebook.id), isFalse);
    expect(await store.listStrokes(page.id), isEmpty);
  });
}

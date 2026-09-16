import 'package:flutter_test/flutter_test.dart';
import 'package:lexpdf_app/src/core/documents/document_provider.dart';
import 'package:lexpdf_app/src/core/ink/ink_models.dart';
import 'package:lexpdf_app/src/core/ink/pdf_ink_models.dart';
import 'package:lexpdf_app/src/core/storage/local_database.dart';
import 'package:lexpdf_app/src/core/storage/local_document_catalog.dart';
import 'package:lexpdf_app/src/core/storage/local_pdf_ink_store.dart';

void main() {
  Future<LocalPdfInkStore> setup(LocalDatabase db, String id) async {
    await LocalDocumentCatalog(db).upsert(
      DocumentRef(
        id: id,
        name: '$id.pdf',
        provider: DocumentProviderKind.local,
        localPath: '/tmp/$id.pdf',
        availableOffline: true,
      ),
    );
    return LocalPdfInkStore(db);
  }

  PdfInkStroke stroke(String id, String doc, int page, double x) => PdfInkStroke(
        id: id,
        documentId: doc,
        pageNumber: page,
        tool: InkTool.pen,
        colorValue: 0xFF246BFD,
        opacity: 1,
        width: 3,
        points: [
          InkPoint(x: x, y: .2, pressure: 1, tilt: 0, timestampMicros: 1),
          InkPoint(x: x, y: .4, pressure: 1, tilt: 0, timestampMicros: 2),
        ],
        createdAt: DateTime.utc(2026, 9, 16),
      );

  test('undo and redo persistently restore an added stroke', () async {
    final db = LocalDatabase.inMemory();
    addTearDown(db.close);
    final store = await setup(db, 'doc-history');

    await store.addStroke(stroke('a', 'doc-history', 9, .3));
    expect(await store.canUndo('doc-history'), isTrue);

    final undone = await store.undo('doc-history');
    expect(undone.changed, isTrue);
    expect(undone.pageNumber, 9);
    expect(await store.listForPage('doc-history', 9), isEmpty);
    expect(await store.canRedo('doc-history'), isTrue);

    final redone = await store.redo('doc-history');
    expect(redone.changed, isTrue);
    expect((await store.listForPage('doc-history', 9)).single.id, 'a');
  });

  test('partial eraser replacement is reversible as one history action', () async {
    final db = LocalDatabase.inMemory();
    addTearDown(db.close);
    final store = await setup(db, 'doc-erase-history');
    final original = stroke('original', 'doc-erase-history', 4, .5);
    final left = stroke('left', 'doc-erase-history', 4, .3);
    final right = stroke('right', 'doc-erase-history', 4, .7);

    await store.addStroke(original);
    await store.replaceStrokeWithFragments(original, [left, right]);
    expect(
      (await store.listForPage('doc-erase-history', 4)).map((e) => e.id),
      containsAll(<String>['left', 'right']),
    );

    await store.undo('doc-erase-history');
    final restored = await store.listForPage('doc-erase-history', 4);
    expect(restored, hasLength(1));
    expect(restored.single.id, 'original');

    await store.redo('doc-erase-history');
    final redone = await store.listForPage('doc-erase-history', 4);
    expect(redone.map((e) => e.id), containsAll(<String>['left', 'right']));
    expect(redone.any((e) => e.id == 'original'), isFalse);
  });

  test('new edit after undo clears the old redo branch', () async {
    final db = LocalDatabase.inMemory();
    addTearDown(db.close);
    final store = await setup(db, 'doc-branch');

    await store.addStroke(stroke('a', 'doc-branch', 2, .2));
    await store.addStroke(stroke('b', 'doc-branch', 2, .4));
    await store.undo('doc-branch');
    expect(await store.canRedo('doc-branch'), isTrue);

    await store.addStroke(stroke('c', 'doc-branch', 2, .8));
    expect(await store.canRedo('doc-branch'), isFalse);
    expect(
      (await store.listForPage('doc-branch', 2)).map((e) => e.id),
      containsAll(<String>['a', 'c']),
    );
  });
}

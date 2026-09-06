import 'package:flutter_test/flutter_test.dart';
import 'package:lexxpdf_app/src/core/documents/document_provider.dart';
import 'package:lexxpdf_app/src/core/ink/ink_models.dart';
import 'package:lexxpdf_app/src/core/ink/pdf_ink_models.dart';
import 'package:lexxpdf_app/src/core/storage/local_database.dart';
import 'package:lexxpdf_app/src/core/storage/local_document_catalog.dart';
import 'package:lexxpdf_app/src/core/storage/local_pdf_ink_store.dart';

void main() {
  Future<LocalPdfInkStore> setupStore(LocalDatabase db, String documentId) async {
    final catalog = LocalDocumentCatalog(db);
    await catalog.upsert(
      DocumentRef(
        id: documentId,
        provider: DocumentProviderKind.local,
        name: '$documentId.pdf',
        localPath: '/tmp/$documentId.pdf',
        availableOffline: true,
        syncState: DocumentSyncState.localOnly,
      ),
    );
    return LocalPdfInkStore(db);
  }

  PdfInkStroke stroke(String id, String documentId, int page, double x) =>
      PdfInkStroke(
        id: id,
        documentId: documentId,
        pageNumber: page,
        tool: InkTool.pen,
        colorValue: 0xFF246BFD,
        opacity: 1,
        width: 3,
        points: [
          InkPoint(x: x, y: 0.2, pressure: 1, tilt: 0, timestampMicros: 1),
          InkPoint(x: x, y: 0.4, pressure: 1, tilt: 0, timestampMicros: 2),
        ],
        createdAt: DateTime.utc(2026, 9, 6),
      );

  test('persiste traços vetoriais associados a uma página PDF', () async {
    final db = LocalDatabase.inMemory();
    addTearDown(db.close);
    final store = await setupStore(db, 'doc-1');

    await store.addStroke(stroke('stroke-1', 'doc-1', 7, 0.5));
    final loaded = await store.listForPage('doc-1', 7);

    expect(loaded, hasLength(1));
    expect(loaded.single.pageNumber, 7);
    expect(loaded.single.points, hasLength(2));
    expect(loaded.single.points.last.pressure, 1);
    expect(loaded.single.points.last.x, 0.5);
  });

  test('exclui de forma persistente apenas o traço apagado do PDF', () async {
    final db = LocalDatabase.inMemory();
    addTearDown(db.close);
    final store = await setupStore(db, 'doc-eraser');

    await store.addStroke(stroke('stroke-a', 'doc-eraser', 2, 0.2));
    await store.addStroke(stroke('stroke-b', 'doc-eraser', 2, 0.8));
    await store.deleteStroke('stroke-a');

    final loaded = await store.listForPage('doc-eraser', 2);
    expect(loaded, hasLength(1));
    expect(loaded.single.id, 'stroke-b');
  });

  test('substitui original por fragmentos em uma única transação', () async {
    final db = LocalDatabase.inMemory();
    addTearDown(db.close);
    final store = await setupStore(db, 'doc-tx');
    final original = stroke('original', 'doc-tx', 3, 0.5);
    final left = stroke('left', 'doc-tx', 3, 0.3);
    final right = stroke('right', 'doc-tx', 3, 0.7);

    await store.addStroke(original);
    await store.replaceStrokeWithFragments(original, [left, right]);

    final loaded = await store.listForPage('doc-tx', 3);
    expect(loaded.map((item) => item.id), containsAll(['left', 'right']));
    expect(loaded.any((item) => item.id == 'original'), isFalse);
  });

  test('rejeita fragmento de outra página sem remover o original', () async {
    final db = LocalDatabase.inMemory();
    addTearDown(db.close);
    final store = await setupStore(db, 'doc-rollback');
    final original = stroke('original', 'doc-rollback', 3, 0.5);
    final invalid = stroke('invalid', 'doc-rollback', 4, 0.7);

    await store.addStroke(original);
    expect(
      () => store.replaceStrokeWithFragments(original, [invalid]),
      throwsArgumentError,
    );

    final loaded = await store.listForPage('doc-rollback', 3);
    expect(loaded, hasLength(1));
    expect(loaded.single.id, 'original');
  });
}

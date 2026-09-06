import 'package:flutter_test/flutter_test.dart';
import 'package:lexxpdf_app/src/core/documents/document_provider.dart';
import 'package:lexxpdf_app/src/core/ink/ink_models.dart';
import 'package:lexxpdf_app/src/core/ink/pdf_ink_models.dart';
import 'package:lexxpdf_app/src/core/storage/local_database.dart';
import 'package:lexxpdf_app/src/core/storage/local_document_catalog.dart';
import 'package:lexxpdf_app/src/core/storage/local_pdf_ink_store.dart';

void main() {
  test('persiste traços vetoriais associados a uma página PDF', () async {
    final db = LocalDatabase.inMemory();
    addTearDown(db.close);

    final catalog = LocalDocumentCatalog(db);
    await catalog.upsert(
      const DocumentRef(
        id: 'doc-1',
        provider: DocumentProviderKind.local,
        name: 'lei.pdf',
        localPath: '/tmp/lei.pdf',
        availableOffline: true,
        syncStatus: DocumentSyncStatus.localOnly,
      ),
    );

    final store = LocalPdfInkStore(db);
    final stroke = PdfInkStroke(
      id: 'stroke-1',
      documentId: 'doc-1',
      pageNumber: 7,
      tool: InkTool.pen,
      colorValue: 0xFF246BFD,
      opacity: 1,
      width: 3,
      points: const [
        InkPoint(x: 0.1, y: 0.2, pressure: 0.4, tilt: 0.1, timestampMicros: 1),
        InkPoint(x: 0.5, y: 0.6, pressure: 0.8, tilt: 0.2, timestampMicros: 2),
      ],
      createdAt: DateTime.utc(2026, 9, 6),
    );

    await store.addStroke(stroke);
    final loaded = await store.listForPage('doc-1', 7);

    expect(loaded, hasLength(1));
    expect(loaded.single.pageNumber, 7);
    expect(loaded.single.points, hasLength(2));
    expect(loaded.single.points.last.pressure, 0.8);
    expect(loaded.single.points.last.x, 0.5);
  });
}

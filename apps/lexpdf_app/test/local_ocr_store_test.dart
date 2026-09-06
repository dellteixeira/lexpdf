import 'package:flutter_test/flutter_test.dart';
import 'package:lexxpdf_app/src/core/documents/document_provider.dart';
import 'package:lexxpdf_app/src/core/storage/local_database.dart';
import 'package:lexxpdf_app/src/core/storage/local_document_catalog.dart';
import 'package:lexxpdf_app/src/core/storage/local_ocr_store.dart';

void main() {
  test('persists and updates OCR page results offline', () async {
    final database = LocalDatabase.inMemory();
    addTearDown(database.close);
    final catalog = LocalDocumentCatalog(database);
    await catalog.upsert(
      DocumentRef(
        id: 'doc-ocr',
        name: 'scan.pdf',
        kind: DocumentProviderKind.local,
        localPath: '/tmp/scan.pdf',
        availableOffline: true,
      ),
    );
    final store = LocalOcrStore(database);
    final now = DateTime.utc(2026, 9, 6);

    await store.upsert(
      OcrPageResult(
        documentId: 'doc-ocr',
        pageNumber: 1,
        text: 'texto reconhecido',
        engine: 'mlkit-latin-offline',
        processedAt: now,
      ),
    );
    await store.upsert(
      OcrPageResult(
        documentId: 'doc-ocr',
        pageNumber: 1,
        text: 'texto atualizado',
        engine: 'mlkit-latin-offline',
        processedAt: now.add(const Duration(seconds: 1)),
      ),
    );

    final results = await store.listForDocument('doc-ocr');
    expect(results, hasLength(1));
    expect(results.single.text, 'texto atualizado');
    expect(results.single.engine, 'mlkit-latin-offline');
  });

  test('clears OCR results for one document', () async {
    final database = LocalDatabase.inMemory();
    addTearDown(database.close);
    final catalog = LocalDocumentCatalog(database);
    await catalog.upsert(
      DocumentRef(
        id: 'doc-ocr',
        name: 'scan.pdf',
        kind: DocumentProviderKind.local,
        localPath: '/tmp/scan.pdf',
        availableOffline: true,
      ),
    );
    final store = LocalOcrStore(database);
    await store.upsert(
      OcrPageResult(
        documentId: 'doc-ocr',
        pageNumber: 1,
        text: 'abc',
        engine: 'test',
        processedAt: DateTime.utc(2026, 9, 6),
      ),
    );

    await store.clearDocument('doc-ocr');
    expect(await store.listForDocument('doc-ocr'), isEmpty);
  });
}

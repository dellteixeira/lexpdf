import 'package:flutter_test/flutter_test.dart';
import 'package:lexpdf_app/src/core/documents/document_provider.dart';
import 'package:lexpdf_app/src/core/storage/local_database.dart';
import 'package:lexpdf_app/src/core/storage/local_document_catalog.dart';
import 'package:lexpdf_app/src/core/storage/local_ocr_store.dart';

void main() {
  test('persists and updates OCR page results offline with line geometry', () async {
    final database = LocalDatabase.inMemory();
    addTearDown(database.close);
    final catalog = LocalDocumentCatalog(database);
    await catalog.upsert(
      const DocumentRef(
        id: 'doc-ocr',
        name: 'scan.pdf',
        provider: DocumentProviderKind.local,
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
        lines: const [
          OcrTextLine(
            text: 'texto atualizado',
            x: 0.10,
            y: 0.20,
            width: 0.40,
            height: 0.05,
          ),
        ],
      ),
    );

    final results = await store.listForDocument('doc-ocr');
    expect(results, hasLength(1));
    expect(results.single.text, 'texto atualizado');
    expect(results.single.engine, 'mlkit-latin-offline');
    expect(results.single.lines, hasLength(1));
    expect(results.single.lines.single.x, closeTo(0.10, 0.0001));
    expect(results.single.lines.single.height, closeTo(0.05, 0.0001));

    final page = await store.getPage('doc-ocr', 1);
    expect(page?.lines.single.text, 'texto atualizado');
  });

  test('clears OCR results for one document', () async {
    final database = LocalDatabase.inMemory();
    addTearDown(database.close);
    final catalog = LocalDocumentCatalog(database);
    await catalog.upsert(
      const DocumentRef(
        id: 'doc-ocr',
        name: 'scan.pdf',
        provider: DocumentProviderKind.local,
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

import 'package:flutter_test/flutter_test.dart';
import 'package:lexpdf_app/src/core/documents/document_provider.dart';
import 'package:lexpdf_app/src/core/storage/local_database.dart';
import 'package:lexpdf_app/src/core/storage/local_document_catalog.dart';
import 'package:lexpdf_app/src/core/storage/local_reading_progress_store.dart';

void main() {
  test('page-only saves preserve zoom, offset and view mode', () async {
    final db = LocalDatabase.inMemory();
    addTearDown(db.close);

    final catalog = LocalDocumentCatalog(db);
    final progress = LocalReadingProgressStore(db);
    const document = DocumentRef(
      id: 'session-doc',
      name: 'Sessão.pdf',
      provider: DocumentProviderKind.local,
      localPath: '/tmp/Sessão.pdf',
      availableOffline: true,
    );
    await catalog.upsert(document);

    await progress.save(
      documentId: document.id,
      pageNumber: 12,
      zoom: 1.75,
      scrollOffset: 248.5,
      viewMode: 'single-page',
    );

    await progress.save(
      documentId: document.id,
      pageNumber: 37,
    );

    final restored = await progress.get(document.id);
    expect(restored, isNotNull);
    expect(restored!.pageNumber, 37);
    expect(restored.zoom, 1.75);
    expect(restored.scrollOffset, 248.5);
    expect(restored.viewMode, 'single-page');
  });

  test('first page-only save still receives safe defaults', () async {
    final db = LocalDatabase.inMemory();
    addTearDown(db.close);

    final catalog = LocalDocumentCatalog(db);
    final progress = LocalReadingProgressStore(db);
    const document = DocumentRef(
      id: 'new-session-doc',
      name: 'Novo.pdf',
      provider: DocumentProviderKind.local,
      localPath: '/tmp/Novo.pdf',
      availableOffline: true,
    );
    await catalog.upsert(document);

    await progress.save(documentId: document.id, pageNumber: 3);

    final restored = await progress.get(document.id);
    expect(restored, isNotNull);
    expect(restored!.pageNumber, 3);
    expect(restored.zoom, 1);
    expect(restored.scrollOffset, 0);
    expect(restored.viewMode, 'continuous');
  });
}

import 'package:flutter_test/flutter_test.dart';

import 'package:lexxpdf_app/src/core/documents/document_provider.dart';
import 'package:lexxpdf_app/src/core/storage/local_database.dart';
import 'package:lexxpdf_app/src/core/storage/local_document_catalog.dart';
import 'package:lexxpdf_app/src/core/storage/local_reading_progress_store.dart';

void main() {
  test('persists and updates the last-read page', () async {
    final db = LocalDatabase.inMemory();
    addTearDown(db.close);

    const document = DocumentRef(
      id: '/tmp/sample.pdf',
      name: 'sample.pdf',
      provider: DocumentProviderKind.local,
      localPath: '/tmp/sample.pdf',
      availableOffline: true,
    );

    final catalog = LocalDocumentCatalog(db);
    final store = LocalReadingProgressStore(db);
    await catalog.upsert(document);

    expect(await store.get(document.id), isNull);

    await store.save(documentId: document.id, pageNumber: 12);
    var progress = await store.get(document.id);
    expect(progress, isNotNull);
    expect(progress!.pageNumber, 12);
    expect(progress.zoom, 1);
    expect(progress.viewMode, 'continuous');

    await store.save(
      documentId: document.id,
      pageNumber: 27,
      zoom: 1.5,
      scrollOffset: 42,
      viewMode: 'continuous',
    );

    progress = await store.get(document.id);
    expect(progress!.pageNumber, 27);
    expect(progress.zoom, 1.5);
    expect(progress.scrollOffset, 42);

    await store.clear(document.id);
    expect(await store.get(document.id), isNull);
  });

  test('rejects invalid page and zoom values', () async {
    final db = LocalDatabase.inMemory();
    addTearDown(db.close);
    final store = LocalReadingProgressStore(db);

    expect(
      () => store.save(documentId: 'missing', pageNumber: 0),
      throwsArgumentError,
    );
    expect(
      () => store.save(documentId: 'missing', pageNumber: 1, zoom: 0),
      throwsArgumentError,
    );
  });
}

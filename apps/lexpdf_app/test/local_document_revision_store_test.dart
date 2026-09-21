import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lexpdf_app/src/core/documents/document_provider.dart';
import 'package:lexpdf_app/src/core/storage/local_database.dart';
import 'package:lexpdf_app/src/core/storage/local_document_catalog.dart';
import 'package:lexpdf_app/src/core/storage/local_document_revision_store.dart';

void main() {
  test('captures, deduplicates and restores document revisions atomically', () async {
    final db = LocalDatabase.inMemory();
    addTearDown(db.close);
    final root = await Directory.systemTemp.createTemp('lexpdf-revision-test-');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final file = File('${root.path}${Platform.pathSeparator}doc.pdf');
    await file.writeAsBytes([1, 2, 3, 4]);

    final catalog = LocalDocumentCatalog(db);
    final document = DocumentRef(
      id: 'doc-1',
      name: 'Documento.pdf',
      provider: DocumentProviderKind.local,
      localPath: file.path,
      availableOffline: true,
    );
    await catalog.upsert(document);
    final store = LocalDocumentRevisionStore(db);

    final first = await store.capture(document, reason: 'sync_upload');
    expect(first, isNotNull);
    final duplicate = await store.capture(document, reason: 'sync_upload');
    expect(duplicate?.id, first?.id);

    await file.writeAsBytes([9, 8, 7]);
    final second = await store.capture(
      document.copyWith(localVersion: 2),
      reason: 'before_remote_download',
    );
    expect(second, isNotNull);
    expect(second?.id, isNot(first?.id));

    final revisions = await store.listRecent(documentId: document.id);
    expect(revisions, hasLength(2));

    final checksum = await store.restore(first!, targetPath: file.path);
    expect(checksum, first.checksum);
    expect(await file.readAsBytes(), [1, 2, 3, 4]);
  });
}

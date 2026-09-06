import 'package:flutter_test/flutter_test.dart';
import 'package:lexxpdf_app/src/core/documents/document_provider.dart';
import 'package:lexxpdf_app/src/core/storage/local_database.dart';
import 'package:lexxpdf_app/src/core/storage/local_document_catalog.dart';

void main() {
  test('persists and restores local PDF metadata offline', () async {
    final database = LocalDatabase.inMemory();
    addTearDown(database.close);
    final catalog = LocalDocumentCatalog(database);

    const document = DocumentRef(
      id: 'doc-1',
      name: 'Constituicao.pdf',
      provider: DocumentProviderKind.local,
      localPath: '/documents/Constituicao.pdf',
      availableOffline: true,
      syncState: DocumentSyncState.localOnly,
    );

    await catalog.upsert(document);

    final restored = await catalog.getById('doc-1');
    expect(restored, isNotNull);
    expect(restored!.name, 'Constituicao.pdf');
    expect(restored.provider, DocumentProviderKind.local);
    expect(restored.localPath, '/documents/Constituicao.pdf');
    expect(restored.availableOffline, isTrue);
    expect(restored.favorite, isFalse);
    expect(restored.syncState, DocumentSyncState.localOnly);
  });

  test('lists documents and supports removal', () async {
    final database = LocalDatabase.inMemory();
    addTearDown(database.close);
    final catalog = LocalDocumentCatalog(database);

    await catalog.upsert(const DocumentRef(
      id: 'a',
      name: 'A.pdf',
      provider: DocumentProviderKind.local,
      localPath: '/A.pdf',
      availableOffline: true,
    ));
    await catalog.upsert(const DocumentRef(
      id: 'b',
      name: 'B.pdf',
      provider: DocumentProviderKind.googleDrive,
      remoteId: 'drive-b',
      remotePath: '/B.pdf',
      availableOffline: false,
      syncState: DocumentSyncState.remoteOnly,
    ));

    expect(await catalog.list(), hasLength(2));
    await catalog.remove('a');
    final remaining = await catalog.list();
    expect(remaining, hasLength(1));
    expect(remaining.single.id, 'b');
  });

  test('adds and removes favorites without losing document metadata', () async {
    final database = LocalDatabase.inMemory();
    addTearDown(database.close);
    final catalog = LocalDocumentCatalog(database);

    const document = DocumentRef(
      id: 'favorite-doc',
      name: 'Favorito.pdf',
      provider: DocumentProviderKind.local,
      localPath: '/Favorito.pdf',
      availableOffline: true,
    );
    await catalog.upsert(document);

    expect(await catalog.isFavorite(document.id), isFalse);
    expect(await catalog.listFavorites(), isEmpty);

    await catalog.setFavorite(document.id, true);
    expect(await catalog.isFavorite(document.id), isTrue);

    final favorites = await catalog.listFavorites();
    expect(favorites, hasLength(1));
    expect(favorites.single.id, document.id);
    expect(favorites.single.favorite, isTrue);
    expect(favorites.single.localPath, document.localPath);

    await catalog.upsert(document);
    expect(await catalog.isFavorite(document.id), isTrue);

    await catalog.setFavorite(document.id, false);
    expect(await catalog.listFavorites(), isEmpty);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:lexxpdf_app/src/core/documents/document_provider.dart';
import 'package:lexxpdf_app/src/core/storage/local_database.dart';
import 'package:lexxpdf_app/src/core/storage/local_document_catalog.dart';
import 'package:lexxpdf_app/src/core/storage/local_pdf_navigation_store.dart';

void main() {
  late LocalDatabase database;
  late LocalDocumentCatalog catalog;
  late LocalPdfNavigationStore store;

  setUp(() {
    database = LocalDatabase.inMemory();
    catalog = LocalDocumentCatalog(database);
    store = LocalPdfNavigationStore(database);
  });

  tearDown(() => database.close());

  Future<DocumentRef> seedDocument() async {
    final document = DocumentRef(
      id: 'doc-1',
      name: 'Manual de Processo Penal.pdf',
      provider: DocumentProviderKind.local,
      localPath: '/tmp/manual.pdf',
      availableOffline: true,
      syncState: DocumentSyncState.localOnly,
    );
    await catalog.upsert(document);
    return document;
  }

  test('toggles persistent bookmarks per document page', () async {
    final document = await seedDocument();
    await store.toggleBookmark(documentId: document.id, pageNumber: 3);
    var bookmarks = await store.listBookmarks(document.id);
    expect(bookmarks, hasLength(1));
    expect(bookmarks.single.pageNumber, 3);

    await store.toggleBookmark(documentId: document.id, pageNumber: 3);
    bookmarks = await store.listBookmarks(document.id);
    expect(bookmarks, isEmpty);
  });

  test('persists tags and collection memberships offline', () async {
    final document = await seedDocument();
    await store.addTag(document.id, 'concurso');
    await store.addTag(document.id, 'penal');
    expect(await store.listTags(document.id), ['concurso', 'penal']);

    final collection = await store.createCollection('Direito');
    await store.addDocumentToCollection(collection.id, document.id);
    expect(await store.listDocumentIdsInCollection(collection.id), [document.id]);

    await store.removeDocumentFromCollection(collection.id, document.id);
    expect(await store.listDocumentIdsInCollection(collection.id), isEmpty);
  });

  test('indexes page text transactionally and returns page hits', () async {
    final document = await seedDocument();
    await store.replacePageTextIndex(
      documentId: document.id,
      pages: {
        1: 'Princípio do contraditório e ampla defesa.',
        2: 'Inquérito policial e investigação preliminar.',
      },
    );

    final hits = await store.search('inquérito');
    final hit = hits.singleWhere((item) => item.kind == 'pdf_text');
    expect(hit.documentId, document.id);
    expect(hit.pageNumber, 2);
    expect(hit.snippet.toLowerCase(), contains('inquérito'));
  });
}

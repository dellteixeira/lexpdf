import 'package:flutter_test/flutter_test.dart';
import 'package:lexpdf_app/src/core/documents/document_provider.dart';
import 'package:lexpdf_app/src/core/storage/local_database.dart';
import 'package:lexpdf_app/src/core/storage/local_document_catalog.dart';
import 'package:lexpdf_app/src/core/storage/local_global_search_fts.dart';
import 'package:lexpdf_app/src/core/storage/local_pdf_navigation_store.dart';

void main() {
  test('FTS5 searches PDF text with prefix matching and page metadata', () async {
    final database = LocalDatabase.inMemory();
    addTearDown(database.close);
    final catalog = LocalDocumentCatalog(database);
    final navigation = LocalPdfNavigationStore(database);
    final fts = LocalGlobalSearchFts(database);

    await catalog.upsert(
      const DocumentRef(
        id: 'doc-fts',
        name: 'Processo Penal.pdf',
        provider: DocumentProviderKind.local,
        localPath: '/tmp/processo.pdf',
        availableOffline: true,
      ),
    );
    await navigation.replacePageTextIndex(
      documentId: 'doc-fts',
      pages: {
        1: 'Princípio do contraditório e ampla defesa.',
        2: 'Inquérito policial e investigação preliminar.',
      },
    );

    final hits = await fts.search('inquer');
    final hit = hits.singleWhere((item) => item.kind == 'pdf_text');
    expect(hit.documentId, 'doc-fts');
    expect(hit.pageNumber, 2);
    expect(hit.snippet.toLowerCase(), contains('inquérito'));
  });

  test('FTS5 includes document tags in global search', () async {
    final database = LocalDatabase.inMemory();
    addTearDown(database.close);
    final catalog = LocalDocumentCatalog(database);
    final navigation = LocalPdfNavigationStore(database);
    final fts = LocalGlobalSearchFts(database);

    await catalog.upsert(
      const DocumentRef(
        id: 'doc-tag',
        name: 'Manual.pdf',
        provider: DocumentProviderKind.local,
        localPath: '/tmp/manual.pdf',
        availableOffline: true,
      ),
    );
    await navigation.addTag('doc-tag', 'concurso');

    final hits = await fts.search('concur');
    expect(
      hits.any((item) => item.kind == 'document' && item.documentId == 'doc-tag'),
      isTrue,
    );
  });
}

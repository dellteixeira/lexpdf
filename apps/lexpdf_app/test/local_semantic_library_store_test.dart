import 'package:flutter_test/flutter_test.dart';
import 'package:lexpdf_app/src/core/documents/document_provider.dart';
import 'package:lexpdf_app/src/core/storage/local_database.dart';
import 'package:lexpdf_app/src/core/storage/local_document_catalog.dart';
import 'package:lexpdf_app/src/core/storage/local_pdf_navigation_store.dart';
import 'package:lexpdf_app/src/core/storage/local_semantic_library_store.dart';

void main() {
  test('semantic library ranks fresh page vectors by cosine similarity', () async {
    final database = LocalDatabase.inMemory();
    addTearDown(database.close);
    final catalog = LocalDocumentCatalog(database);
    final navigation = LocalPdfNavigationStore(database);
    final semantic = LocalSemanticLibraryStore(database);

    await catalog.upsert(
      const DocumentRef(
        id: 'doc-rag',
        name: 'Constitucional.pdf',
        provider: DocumentProviderKind.local,
        localPath: '/tmp/constitucional.pdf',
        availableOffline: true,
      ),
    );
    await navigation.replacePageTextIndex(
      documentId: 'doc-rag',
      pages: {
        3: 'Controle difuso pode ser exercido no caso concreto.',
        8: 'Direitos fundamentais possuem aplicação imediata.',
      },
    );

    final pending =
        await semantic.pagesNeedingIndex(model: '@cf/baai/bge-m3');
    expect(pending, hasLength(2));

    await semantic.saveEmbeddings(
      pages: pending,
      vectors: const [
        [1, 0, 0],
        [0, 1, 0],
      ],
      model: '@cf/baai/bge-m3',
    );

    final hits = await semantic.search(
      queryVector: const [0.98, 0.02, 0],
      model: '@cf/baai/bge-m3',
    );
    expect(hits.first.pageNumber, 3);
    expect(hits.first.documentTitle, 'Constitucional.pdf');

    final status = await semantic.status();
    expect(status.sourcePages, 2);
    expect(status.indexedPages, 2);
    expect(
      await semantic.pagesNeedingIndex(model: '@cf/baai/bge-m3'),
      isEmpty,
    );
  });
}

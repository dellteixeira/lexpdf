import 'package:flutter_test/flutter_test.dart';
import 'package:lexpdf_app/src/core/documents/document_provider.dart';
import 'package:lexpdf_app/src/core/storage/local_database.dart';
import 'package:lexpdf_app/src/core/storage/local_document_catalog.dart';
import 'package:lexpdf_app/src/core/storage/local_global_search_fts.dart';
import 'package:lexpdf_app/src/core/storage/local_hybrid_rag_store.dart';
import 'package:lexpdf_app/src/core/storage/local_pdf_navigation_store.dart';

void main() {
  test('hybrid RAG combines chunk vectors, FTS5 and reranking', () async {
    final database = LocalDatabase.inMemory();
    addTearDown(database.close);
    final catalog = LocalDocumentCatalog(database);
    final navigation = LocalPdfNavigationStore(database);
    final fts = LocalGlobalSearchFts(database);
    final rag = LocalHybridRagStore(database);

    await catalog.upsert(
      const DocumentRef(
        id: 'doc-constitutional',
        name: 'Constitucional.pdf',
        provider: DocumentProviderKind.local,
        localPath: '/tmp/constitucional.pdf',
        availableOffline: true,
      ),
    );
    await catalog.upsert(
      const DocumentRef(
        id: 'doc-civil',
        name: 'Civil.pdf',
        provider: DocumentProviderKind.local,
        localPath: '/tmp/civil.pdf',
        availableOffline: true,
      ),
    );
    await navigation.replacePageTextIndex(
      documentId: 'doc-constitutional',
      pages: {
        10: 'O contraditório e a ampla defesa asseguram participação e reação '
            'no processo. A defesa deve conhecer os atos relevantes.',
      },
    );
    await navigation.replacePageTextIndex(
      documentId: 'doc-civil',
      pages: {
        4: 'A compra e venda transfere obrigações entre comprador e vendedor.',
      },
    );
    await fts.rebuild();

    final pending = await rag.chunksNeedingIndex(model: 'test-model');
    expect(pending.length, greaterThanOrEqualTo(2));
    await rag.saveEmbeddings(
      chunks: pending,
      vectors: [
        for (final chunk in pending)
          chunk.documentId == 'doc-constitutional'
              ? const [1.0, 0.0, 0.0]
              : const [0.0, 1.0, 0.0],
      ],
      model: 'test-model',
    );

    final hits = await rag.searchHybrid(
      query: 'ampla defesa contraditório',
      queryVector: const [0.98, 0.02, 0.0],
      model: 'test-model',
      limit: 4,
    );
    expect(hits, isNotEmpty);
    expect(hits.first.documentId, 'doc-constitutional');
    expect(hits.first.pageNumber, 10);
    expect(hits.first.lexicalScore, greaterThan(0));
    expect(hits.first.rerankScore, greaterThan(0.5));

    final scoped = await rag.searchHybrid(
      query: 'compra vendedor',
      queryVector: const [0.0, 1.0, 0.0],
      model: 'test-model',
      documentId: 'doc-civil',
    );
    expect(scoped.every((hit) => hit.documentId == 'doc-civil'), isTrue);
  });

  test('structure-aware chunking preserves useful overlap', () {
    final text = List.generate(
      50,
      (index) =>
          'Parágrafo $index explica um conceito jurídico com detalhes suficientes.',
    ).join('\n\n');
    final chunks = LocalHybridRagStore.chunkPage(text);
    expect(chunks.length, greaterThan(1));
    expect(
      chunks.every(
        (chunk) =>
            chunk.length <= LocalHybridRagStore.maxChunkCharacters + 200,
      ),
      isTrue,
    );
  });
}

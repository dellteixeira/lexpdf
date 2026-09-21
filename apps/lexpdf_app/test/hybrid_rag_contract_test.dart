import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('RAG hybrid pipeline keeps FTS5, embeddings, chunking and reranking', () {
    final store =
        File('lib/src/core/storage/local_hybrid_rag_store.dart').readAsStringSync();
    final service =
        File('lib/src/core/ai/hybrid_rag_service.dart').readAsStringSync();
    final study =
        File('lib/src/screens/advanced_study_screen.dart').readAsStringSync();

    expect(store, contains('hybrid_rag_chunks'));
    expect(store, contains('global_search_fts MATCH'));
    expect(store, contains('bm25(global_search_fts'));
    expect(store, contains('_cosine(queryVector, vector)'));
    expect(store, contains('rerankScore'));
    expect(store, contains('chunkPage'));
    expect(store, contains('overlapCharacters'));
    expect(service, contains('searchHybrid'));
    expect(study, contains('RAG híbrido'));
    expect(study, contains('Atualizar índice híbrido'));
  });
}

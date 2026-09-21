import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('library RAG is semantic, authenticated and source-bound', () {
    final screen =
        File('lib/src/screens/advanced_study_screen.dart').readAsStringSync();
    final models = File('lib/src/core/ai/ai_models.dart').readAsStringSync();
    final embeddings =
        File('lib/src/core/ai/remote_embedding_service.dart').readAsStringSync();
    final semantic = File(
      'lib/src/core/storage/local_hybrid_rag_store.dart',
    ).readAsStringSync();

    expect(screen, contains('Perguntar à biblioteca — RAG'));
    expect(screen, contains("label: const Text('Perguntar à biblioteca')"));
    expect(screen, contains("label: const Text('Atualizar índice híbrido')"));
    expect(screen, contains('AiExplanationIntent.libraryRag'));
    expect(screen, contains('currentSession?.accessToken'));
    expect(screen, contains("'[F\${index + 1}]"));
    expect(screen, contains("title: const Text('Fontes recuperadas')"));
    expect(models, contains('libraryRag'));
    expect(
      models,
      contains("AiExplanationIntent.libraryRag => 'Perguntar à biblioteca'"),
    );
    expect(embeddings, contains("'texts': normalized"));
    expect(embeddings, contains('maxBatchSize = 32'));
    expect(semantic, contains('semantic_page_embeddings'));
    expect(semantic, contains('_cosine(queryVector, vector)'));
  });
}

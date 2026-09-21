import '../storage/local_hybrid_rag_store.dart';
import '../storage/local_knowledge_rag_store.dart';
import 'hybrid_rag_service.dart';
import 'embedding_service.dart';

class ExtendedHybridRagService {
  ExtendedHybridRagService({
    required this.base,
    required this.knowledge,
    required this.embeddings,
  });

  final HybridRagService base;
  final LocalKnowledgeRagStore knowledge;
  final AiEmbeddingService embeddings;

  Future<void> _ensureKnowledgeIndex({
    required String model,
    String? documentId,
    void Function(double progress)? onProgress,
  }) async {
    final pending = await knowledge.sourcesNeedingIndex(
      model: model,
      documentId: documentId,
    );
    if (pending.isEmpty) {
      onProgress?.call(1);
      return;
    }
    var completed = 0;
    for (var offset = 0;
        offset < pending.length;
        offset += embeddings.batchSize) {
      final end = (offset + embeddings.batchSize)
          .clamp(0, pending.length);
      final batch = pending.sublist(offset, end);
      final embedded = await embeddings.embed(
        batch.map((source) => source.content).toList(growable: false),
      );
      await knowledge.saveEmbeddings(
        sources: batch,
        vectors: embedded.vectors,
        model: embedded.model,
      );
      completed += batch.length;
      onProgress?.call(completed / pending.length);
    }
  }

  Future<HybridRagRetrieval> retrieve(
    String query, {
    String? documentId,
    int limit = 8,
    void Function(double progress)? onIndexProgress,
  }) async {
    final queryEmbedding = await embeddings.embed([query]);
    await base.ensureIndex(
      model: queryEmbedding.model,
      documentId: documentId,
      onProgress: (value) => onIndexProgress?.call(value * 0.65),
    );
    await _ensureKnowledgeIndex(
      model: queryEmbedding.model,
      documentId: documentId,
      onProgress: (value) => onIndexProgress?.call(0.65 + value * 0.35),
    );
    final pdfHits = await base.store.searchHybrid(
      query: query,
      queryVector: queryEmbedding.vectors.single,
      model: queryEmbedding.model,
      documentId: documentId,
      limit: limit * 2,
    );
    final knowledgeHits = await knowledge.search(
      query: query,
      queryVector: queryEmbedding.vectors.single,
      model: queryEmbedding.model,
      documentId: documentId,
      limit: limit * 2,
    );
    final combined = [...pdfHits, ...knowledgeHits]
      ..sort((a, b) => b.rerankScore.compareTo(a.rerankScore));
    final selected = <HybridRagHit>[];
    final seen = <String>{};
    for (final hit in combined) {
      if (!seen.add(hit.key)) continue;
      selected.add(hit);
      if (selected.length >= limit) break;
    }
    onIndexProgress?.call(1);
    return HybridRagRetrieval(
      hits: selected,
      model: queryEmbedding.model,
      quotaRemaining: queryEmbedding.quotaRemaining,
      quotaLimit: queryEmbedding.quotaLimit,
    );
  }

  Future<String> updateIndex({
    String? documentId,
    void Function(double progress)? onProgress,
  }) async {
    final probe = await embeddings.embed(const ['Índice ampliado LexPDF']);
    await base.ensureIndex(
      model: probe.model,
      documentId: documentId,
      onProgress: (value) => onProgress?.call(value * 0.65),
    );
    await _ensureKnowledgeIndex(
      model: probe.model,
      documentId: documentId,
      onProgress: (value) => onProgress?.call(0.65 + value * 0.35),
    );
    onProgress?.call(1);
    return probe.model;
  }
}

import '../storage/local_hybrid_rag_store.dart';
import 'remote_embedding_service.dart';

class HybridRagRetrieval {
  const HybridRagRetrieval({
    required this.hits,
    required this.model,
    this.quotaRemaining,
    this.quotaLimit,
  });

  final List<HybridRagHit> hits;
  final String model;
  final int? quotaRemaining;
  final int? quotaLimit;
}

class HybridRagService {
  HybridRagService({
    required this.store,
    required this.embeddings,
  });

  final LocalHybridRagStore store;
  final RemoteAiEmbeddingService embeddings;

  Future<void> ensureIndex({
    required String model,
    String? documentId,
    void Function(double progress)? onProgress,
  }) async {
    final pending = await store.chunksNeedingIndex(
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
        offset += RemoteAiEmbeddingService.maxBatchSize) {
      final end = (offset + RemoteAiEmbeddingService.maxBatchSize)
          .clamp(0, pending.length);
      final batch = pending.sublist(offset, end);
      final embedded = await embeddings.embed(
        batch.map((chunk) => chunk.content).toList(growable: false),
      );
      if (embedded.model != model) {
        throw StateError(
          'O modelo de embeddings mudou durante a indexação. '
          'Reinicie a atualização do índice.',
        );
      }
      await store.saveEmbeddings(
        chunks: batch,
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
    final embeddedQuery = await embeddings.embed([query]);
    await ensureIndex(
      model: embeddedQuery.model,
      documentId: documentId,
      onProgress: onIndexProgress,
    );
    final hits = await store.searchHybrid(
      query: query,
      queryVector: embeddedQuery.vectors.single,
      model: embeddedQuery.model,
      documentId: documentId,
      limit: limit,
    );
    return HybridRagRetrieval(
      hits: hits,
      model: embeddedQuery.model,
      quotaRemaining: embeddedQuery.quotaRemaining,
      quotaLimit: embeddedQuery.quotaLimit,
    );
  }

  Future<String> updateIndex({
    String? documentId,
    void Function(double progress)? onProgress,
  }) async {
    final probe = await embeddings.embed(const ['Índice híbrido LexPDF']);
    await ensureIndex(
      model: probe.model,
      documentId: documentId,
      onProgress: onProgress,
    );
    return probe.model;
  }
}

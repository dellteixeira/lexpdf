class AiEmbeddingBatch {
  const AiEmbeddingBatch({
    required this.vectors,
    required this.model,
    this.quotaRemaining,
    this.quotaLimit,
  });

  final List<List<double>> vectors;
  final String model;
  final int? quotaRemaining;
  final int? quotaLimit;
}

abstract interface class AiEmbeddingService {
  int get batchSize;

  Future<AiEmbeddingBatch> embed(List<String> texts);
}

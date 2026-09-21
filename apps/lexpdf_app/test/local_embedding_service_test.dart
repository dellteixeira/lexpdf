import 'package:flutter_test/flutter_test.dart';
import 'package:lexpdf_app/src/core/ai/local_embedding_service.dart';

void main() {
  test('local embeddings are deterministic and rank related text higher', () async {
    const service = LocalAiEmbeddingService();
    final batch = await service.embed([
      'controle de constitucionalidade difuso',
      'controle constitucional realizado de forma difusa',
      'receita de bolo com chocolate',
    ]);

    expect(batch.model, LocalAiEmbeddingService.modelName);
    expect(batch.vectors, hasLength(3));
    expect(batch.vectors.first, hasLength(256));

    final related = _cosine(batch.vectors[0], batch.vectors[1]);
    final unrelated = _cosine(batch.vectors[0], batch.vectors[2]);
    expect(related, greaterThan(unrelated));

    final again = await service.embed([
      'controle de constitucionalidade difuso',
    ]);
    expect(again.vectors.single, batch.vectors.first);
  });
}

double _cosine(List<double> a, List<double> b) {
  var dot = 0.0;
  var aa = 0.0;
  var bb = 0.0;
  for (var i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    aa += a[i] * a[i];
    bb += b[i] * b[i];
  }
  if (aa == 0 || bb == 0) return -1;
  return dot / _sqrt(aa * bb);
}

double _sqrt(double value) {
  var x = value;
  for (var i = 0; i < 24; i++) {
    x = (x + value / x) / 2;
  }
  return x;
}

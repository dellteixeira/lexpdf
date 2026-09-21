import 'dart:math' as math;

import 'embedding_service.dart';

/// Fully local, deterministic retrieval embeddings.
///
/// This is intentionally a compact feature-hashing model rather than a
/// bundled neural-network binary. It mixes normalized word, stem, word-bigram
/// and character-trigram features into a fixed-size vector. The result is
/// suitable for private/offline hybrid retrieval and requires no network,
/// account, model download, API key or native runtime.
class LocalAiEmbeddingService implements AiEmbeddingService {
  const LocalAiEmbeddingService({
    this.dimensions = 256,
    this.maxCharactersPerText = 24000,
  }) : assert(dimensions >= 64);

  static const String modelName = 'lexpdf-local-hash-v1-256';
  static const int defaultBatchSize = 64;

  final int dimensions;
  final int maxCharactersPerText;

  @override
  int get batchSize => defaultBatchSize;

  @override
  Future<AiEmbeddingBatch> embed(List<String> texts) async {
    final normalized = texts
        .map((text) => text.trim())
        .where((text) => text.isNotEmpty)
        .map(
          (text) => text.length <= maxCharactersPerText
              ? text
              : text.substring(0, maxCharactersPerText),
        )
        .toList(growable: false);
    if (normalized.isEmpty) {
      throw ArgumentError('At least one non-empty text is required.');
    }
    if (normalized.length > batchSize) {
      throw ArgumentError('Embedding batch exceeds $batchSize texts.');
    }

    return AiEmbeddingBatch(
      vectors: normalized.map(_embedOne).toList(growable: false),
      model: dimensions == 256
          ? modelName
          : 'lexpdf-local-hash-v1-$dimensions',
    );
  }

  List<double> _embedOne(String input) {
    final vector = List<double>.filled(dimensions, 0);
    final normalized = _normalize(input);
    final words = RegExp(r'[a-z0-9]+')
        .allMatches(normalized)
        .map((match) => match.group(0)!)
        .where((word) => word.length >= 2)
        .toList(growable: false);

    for (var index = 0; index < words.length; index++) {
      final word = words[index];
      _addFeature(vector, 'w:$word', 1.0);
      final stem = _stem(word);
      if (stem != word && stem.length >= 3) {
        _addFeature(vector, 's:$stem', 0.72);
      }

      final padded = '^${word}#';
      if (padded.length >= 3) {
        for (var i = 0; i <= padded.length - 3; i++) {
          _addFeature(vector, 'c:${padded.substring(i, i + 3)}', 0.18);
        }
      }

      if (index + 1 < words.length) {
        _addFeature(vector, 'b:$word ${words[index + 1]}', 0.58);
      }
    }

    if (words.isEmpty) {
      final end = math.min(64, normalized.length);
      _addFeature(vector, 'raw:${normalized.substring(0, end)}', 1);
    }

    var norm = 0.0;
    for (final value in vector) {
      norm += value * value;
    }
    if (norm == 0) {
      vector[0] = 1;
      return vector;
    }
    final scale = 1 / math.sqrt(norm);
    for (var i = 0; i < vector.length; i++) {
      vector[i] *= scale;
    }
    return vector;
  }

  void _addFeature(List<double> vector, String feature, double weight) {
    final hash = _fnv1a(feature);
    final slot = (hash & 0x7fffffff) % vector.length;
    final sign = (hash & 0x80000000) == 0 ? 1.0 : -1.0;
    vector[slot] += weight * sign;
  }

  static int _fnv1a(String value) {
    var hash = 0x811c9dc5;
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash;
  }

  static String _stem(String word) {
    const endings = <String>[
      'amentos', 'imentos', 'amento', 'imento', 'acoes', 'icoes',
      'acao', 'icao', 'mente', 'idades', 'idade', 'istas', 'ista',
      'icos', 'icas', 'ico', 'ica', 'ivos', 'ivas', 'ivo', 'iva',
      'oes', 'aes', 'es', 'os', 'as', 's',
    ];
    for (final ending in endings) {
      if (word.length >= ending.length + 4 && word.endsWith(ending)) {
        return word.substring(0, word.length - ending.length);
      }
    }
    return word;
  }

  static String _normalize(String value) {
    var result = value.toLowerCase();
    const replacements = <String, String>{
      'á': 'a', 'à': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a',
      'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
      'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i',
      'ó': 'o', 'ò': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o',
      'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u',
      'ç': 'c', 'ñ': 'n',
    };
    replacements.forEach((from, to) {
      result = result.replaceAll(from, to);
    });
    return result;
  }
}

import '../storage/local_hybrid_rag_store.dart';
import 'ai_models.dart';

class LocalGroundedAnswerEngine {
  const LocalGroundedAnswerEngine();

  AiStudyResult answer({
    required String query,
    required List<HybridRagHit> hits,
    int maxSources = 6,
  }) {
    if (hits.isEmpty) {
      throw ArgumentError('At least one grounded source is required.');
    }
    final selected = hits.take(maxSources).toList(growable: false);
    final terms = _terms(query);
    final lines = <String>[
      'Resposta offline baseada exclusivamente nas fontes locais recuperadas:',
      '',
    ];
    for (var index = 0; index < selected.length; index++) {
      final sentence = _bestSentence(selected[index].content, terms);
      lines.add('• [F${index + 1}] $sentence');
    }
    lines.add('');
    lines.add(
      'Os marcadores [F#] correspondem às fontes exibidas abaixo. '
      'Nenhuma informação externa foi acrescentada no modo offline.',
    );
    return AiStudyResult(
      action: AiStudyAction.explain,
      engine: AiEngineKind.local,
      sourceText: query,
      text: lines.join('\n'),
      explanationDepth: AiExplanationDepth.detailed,
      model: 'lexpdf-local-grounded-v1',
    );
  }

  static String _bestSentence(String content, Set<String> queryTerms) {
    final sentences = content
        .replaceAll('\r', ' ')
        .split(RegExp(r'(?<=[.!?;])\s+|\n+'))
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    if (sentences.isEmpty) {
      return LocalHybridRagStore.ragExcerpt(
        content,
        queryTerms.join(' '),
        maxCharacters: 420,
      );
    }

    String best = sentences.first;
    var bestScore = -1;
    for (final sentence in sentences.take(18)) {
      final lower = sentence.toLowerCase();
      var score = 0;
      for (final term in queryTerms) {
        if (lower.contains(term)) score++;
      }
      if (score > bestScore ||
          (score == bestScore && sentence.length < best.length)) {
        best = sentence;
        bestScore = score;
      }
    }
    if (best.length > 520) return '${best.substring(0, 520)}…';
    return best;
  }

  static Set<String> _terms(String query) => RegExp(r'[A-Za-zÀ-ÿ0-9]+')
      .allMatches(query.toLowerCase())
      .map((match) => match.group(0)!)
      .where((term) => term.length >= 3)
      .toSet();
}

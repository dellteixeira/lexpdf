import 'dart:math' as math;

import 'ai_engine.dart';
import 'ai_models.dart';

class LocalStudyEngine implements AiStudyEngine {
  const LocalStudyEngine();

  static const _stopwords = <String>{
    'a','o','as','os','um','uma','uns','umas','de','da','do','das','dos','e','ou','em','no','na','nos','nas','por','para','com','sem','que','se','ao','aos','à','às','é','são','foi','ser','como','mais','menos','muito','muita','muitos','muitas','este','esta','esse','essa','isso','isto','aquele','aquela','também','já','não','sim','entre','sobre','sob','quando','onde','qual','quais','quem','seu','sua','seus','suas','pela','pelo','pelas','pelos','num','numa','nuns','numas','the','and','of','to','in','is','are','for','with','that','this','as','on','by','or','an','be','from'
  };

  @override
  AiEngineKind get kind => AiEngineKind.local;

  @override
  Future<AiStudyResult> run({
    required AiStudyAction action,
    required String text,
    int itemCount = 8,
  }) async {
    final source = _normalize(text);
    if (source.isEmpty) {
      throw ArgumentError('O texto de origem está vazio.');
    }
    return switch (action) {
      AiStudyAction.summarize => AiStudyResult(
          action: action,
          engine: kind,
          sourceText: source,
          text: _summarize(source, maxSentences: math.max(2, math.min(8, itemCount))),
        ),
      AiStudyAction.explain => AiStudyResult(
          action: action,
          engine: kind,
          sourceText: source,
          text: _explain(source),
        ),
      AiStudyAction.flashcards => AiStudyResult(
          action: action,
          engine: kind,
          sourceText: source,
          flashcards: _flashcards(source, itemCount),
        ),
      AiStudyAction.questions => AiStudyResult(
          action: action,
          engine: kind,
          sourceText: source,
          questions: _questions(source, itemCount),
        ),
    };
  }

  String _summarize(String text, {required int maxSentences}) {
    final sentences = _sentences(text);
    if (sentences.length <= maxSentences) return sentences.join(' ');
    final frequencies = _wordFrequencies(text);
    final scored = <({int index, String sentence, double score})>[];
    for (var index = 0; index < sentences.length; index++) {
      final words = _words(sentences[index]);
      if (words.isEmpty) continue;
      final score = words.fold<double>(
            0,
            (sum, word) => sum + (frequencies[word] ?? 0),
          ) /
          math.sqrt(words.length);
      scored.add((index: index, sentence: sentences[index], score: score));
    }
    scored.sort((a, b) => b.score.compareTo(a.score));
    final chosen = scored.take(maxSentences).toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    return chosen.map((item) => item.sentence).join(' ');
  }

  String _explain(String text) {
    final summary = _summarize(text, maxSentences: 4);
    final terms = _topTerms(text, 5);
    final buffer = StringBuffer()
      ..writeln('Ideia central:')
      ..writeln(summary);
    if (terms.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Conceitos-chave: ${terms.join(', ')}.');
    }
    buffer
      ..writeln()
      ..write('Leitura prática: identifique a regra principal, as condições de aplicação e as exceções explícitas no trecho.');
    return buffer.toString();
  }

  List<AiFlashcard> _flashcards(String text, int count) {
    final sentences = _sentences(text)
        .where((sentence) => sentence.length >= 35)
        .toList(growable: false);
    final cards = <AiFlashcard>[];
    final seen = <String>{};
    for (final sentence in sentences) {
      if (cards.length >= count) break;
      final terms = _topTerms(sentence, 2);
      if (terms.isEmpty) continue;
      final term = terms.first;
      final key = term.toLowerCase();
      if (!seen.add(key)) continue;
      cards.add(
        AiFlashcard(
          question: 'O que o trecho afirma sobre “$term”?',
          answer: sentence,
        ),
      );
    }
    if (cards.isEmpty) {
      cards.add(
        AiFlashcard(
          question: 'Qual é a ideia principal do trecho?',
          answer: _summarize(text, maxSentences: 2),
        ),
      );
    }
    return cards;
  }

  List<String> _questions(String text, int count) {
    final terms = _topTerms(text, math.max(count, 6));
    final questions = <String>[];
    for (final term in terms) {
      if (questions.length >= count) break;
      questions.add('Explique o papel de “$term” no trecho e indique a regra ou consequência associada.');
    }
    if (questions.isEmpty) {
      questions.add('Qual é a tese central do trecho e quais elementos a sustentam?');
    }
    return questions;
  }

  Map<String, int> _wordFrequencies(String text) {
    final frequencies = <String, int>{};
    for (final word in _words(text)) {
      if (_stopwords.contains(word) || word.length < 4) continue;
      frequencies.update(word, (value) => value + 1, ifAbsent: () => 1);
    }
    return frequencies;
  }

  List<String> _topTerms(String text, int count) {
    final entries = _wordFrequencies(text).entries.toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        return byCount != 0 ? byCount : a.key.compareTo(b.key);
      });
    return entries.take(count).map((entry) => entry.key).toList(growable: false);
  }

  List<String> _sentences(String text) => text
      .split(RegExp(r'(?<=[.!?;])\s+|\n+'))
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toList(growable: false);

  List<String> _words(String text) => RegExp(r"[A-Za-zÀ-ÿ0-9][A-Za-zÀ-ÿ0-9'’-]*")
      .allMatches(text.toLowerCase())
      .map((match) => match.group(0)!)
      .toList(growable: false);

  String _normalize(String value) => value.replaceAll(RegExp(r'\s+'), ' ').trim();
}

enum AiStudyAction { explain, summarize, flashcards, questions }

enum AiEngineKind { local, remote }

enum AiExplanationDepth { quick, detailed, deep }

enum AiExplanationIntent {
  explain,
  contest,
  simplify,
  example,
  flashcard,
  crossStudy,
  reviewTutor,
  libraryRag,
  contextChat,
}

extension AiExplanationIntentLabel on AiExplanationIntent {
  String get label => switch (this) {
        AiExplanationIntent.explain => 'Explicar',
        AiExplanationIntent.contest => 'Modo Concurso',
        AiExplanationIntent.simplify => 'Simplificar',
        AiExplanationIntent.example => 'Dar exemplo',
        AiExplanationIntent.flashcard => 'Sugerir flashcard',
        AiExplanationIntent.crossStudy => 'Síntese cruzada',
        AiExplanationIntent.reviewTutor => 'Tutor de revisão',
        AiExplanationIntent.libraryRag => 'Perguntar à biblioteca',
        AiExplanationIntent.contextChat => 'Chat contextual',
      };
}

extension AiExplanationDepthLabel on AiExplanationDepth {
  String get label => switch (this) {
        AiExplanationDepth.quick => 'Rápida',
        AiExplanationDepth.detailed => 'Detalhada',
        AiExplanationDepth.deep => 'Aprofundada',
      };
}

class AiFlashcard {
  const AiFlashcard({required this.question, required this.answer});

  final String question;
  final String answer;
}

class AiStudyResult {
  const AiStudyResult({
    required this.action,
    required this.engine,
    required this.sourceText,
    this.text,
    this.flashcards = const [],
    this.questions = const [],
    this.explanationDepth,
    this.model,
    this.fallbackUsed = false,
    this.quotaRemaining,
    this.quotaLimit,
  });

  final AiStudyAction action;
  final AiEngineKind engine;
  final String sourceText;
  final String? text;
  final List<AiFlashcard> flashcards;
  final List<String> questions;
  final AiExplanationDepth? explanationDepth;
  final String? model;
  final bool fallbackUsed;
  final int? quotaRemaining;
  final int? quotaLimit;
}

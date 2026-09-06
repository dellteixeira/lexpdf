enum AiStudyAction { explain, summarize, flashcards, questions }

enum AiEngineKind { local, remote }

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
  });

  final AiStudyAction action;
  final AiEngineKind engine;
  final String sourceText;
  final String? text;
  final List<AiFlashcard> flashcards;
  final List<String> questions;
}

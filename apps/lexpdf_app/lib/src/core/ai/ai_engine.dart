import 'ai_models.dart';

abstract interface class AiStudyEngine {
  AiEngineKind get kind;

  Future<AiStudyResult> run({
    required AiStudyAction action,
    required String text,
    int itemCount = 8,
  });
}

import 'ai_engine.dart';
import 'ai_input_policy.dart';
import 'ai_models.dart';

abstract interface class LocalModelRunner {
  Future<bool> isAvailable();

  Future<AiStudyResult> run({
    required AiStudyAction action,
    required String text,
    required int itemCount,
  });
}

class LocalModelAiStudyEngine implements AiStudyEngine {
  LocalModelAiStudyEngine({
    required this.runner,
    this.inputPolicy = const AiInputPolicy(),
  });

  final LocalModelRunner runner;
  final AiInputPolicy inputPolicy;

  @override
  AiEngineKind get kind => AiEngineKind.local;

  Future<bool> get isAvailable => runner.isAvailable();

  @override
  Future<AiStudyResult> run({
    required AiStudyAction action,
    required String text,
    int itemCount = 8,
  }) async {
    if (!await runner.isAvailable()) {
      throw StateError('Nenhum modelo local compatível está disponível neste dispositivo.');
    }
    final input = inputPolicy.prepare(text, itemCount);
    final result = await runner.run(
      action: action,
      text: input.text,
      itemCount: input.itemCount,
    );
    if (result.engine != AiEngineKind.local) {
      throw StateError('O runner de modelo local retornou um resultado de engine inválida.');
    }
    return result;
  }
}

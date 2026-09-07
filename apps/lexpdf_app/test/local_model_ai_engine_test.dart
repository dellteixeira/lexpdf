import 'package:flutter_test/flutter_test.dart';
import 'package:lexxpdf_app/src/core/ai/ai_models.dart';
import 'package:lexxpdf_app/src/core/ai/local_model_ai_engine.dart';

class _FakeRunner implements LocalModelRunner {
  _FakeRunner({this.available = true});

  final bool available;
  String? receivedText;
  int? receivedCount;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<AiStudyResult> run({
    required AiStudyAction action,
    required String text,
    required int itemCount,
  }) async {
    receivedText = text;
    receivedCount = itemCount;
    return AiStudyResult(
      action: action,
      engine: AiEngineKind.local,
      sourceText: text,
      text: 'ok',
    );
  }
}

void main() {
  test('adapts a future local model runner without changing UI contract', () async {
    final runner = _FakeRunner();
    final engine = LocalModelAiStudyEngine(runner: runner);
    final result = await engine.run(
      action: AiStudyAction.summarize,
      text: '  conteúdo   local  ',
      itemCount: 99,
    );
    expect(result.engine, AiEngineKind.local);
    expect(runner.receivedText, 'conteúdo local');
    expect(runner.receivedCount, 20);
  });

  test('fails closed when no compatible local model is available', () async {
    final engine = LocalModelAiStudyEngine(runner: _FakeRunner(available: false));
    expect(
      () => engine.run(action: AiStudyAction.explain, text: 'conteúdo'),
      throwsStateError,
    );
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:lexpdf_app/src/core/ai/ai_models.dart';
import 'package:lexpdf_app/src/core/ai/local_study_engine.dart';

void main() {
  const engine = LocalStudyEngine();
  const source = '''
A administração pública deve obedecer aos princípios da legalidade, impessoalidade,
moralidade, publicidade e eficiência. A legalidade exige atuação conforme a lei.
A publicidade favorece transparência e controle social. A eficiência orienta a melhor
utilização dos recursos públicos para alcançar resultados adequados.
''';

  test('summarizes locally without changing source', () async {
    final result = await engine.run(
      action: AiStudyAction.summarize,
      text: source,
      itemCount: 3,
    );
    expect(result.engine, AiEngineKind.local);
    expect(result.text, isNotEmpty);
    expect(result.sourceText, contains('administração pública'));
  });

  test('generates flashcards and questions offline', () async {
    final flashcards = await engine.run(
      action: AiStudyAction.flashcards,
      text: source,
      itemCount: 4,
    );
    final questions = await engine.run(
      action: AiStudyAction.questions,
      text: source,
      itemCount: 4,
    );
    expect(flashcards.flashcards, isNotEmpty);
    expect(questions.questions, isNotEmpty);
  });

  test('explanation identifies central ideas', () async {
    final result = await engine.run(
      action: AiStudyAction.explain,
      text: source,
    );
    expect(result.text, contains('Ideia central'));
    expect(result.text, contains('Conceitos-chave'));
  });

  test('rejects empty source', () async {
    expect(
      () => engine.run(action: AiStudyAction.summarize, text: '   '),
      throwsArgumentError,
    );
  });
}

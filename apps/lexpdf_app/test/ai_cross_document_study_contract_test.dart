import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('cross-document study synthesis stays source-bound and authenticated', () {
    final screen =
        File('lib/src/screens/advanced_study_screen.dart').readAsStringSync();
    final models = File('lib/src/core/ai/ai_models.dart').readAsStringSync();
    final remote =
        File('lib/src/core/ai/remote_ai_engine.dart').readAsStringSync();

    expect(screen, contains("label: const Text('Sintetizar com IA')"));
    expect(screen, contains('AiExplanationIntent.crossStudy'));
    expect(screen, contains('AiAccessSession.bearerToken'));
    expect(screen, isNot(contains('Entre na sua conta LexPDF')));
    expect(screen, contains("'[F\${index + 1}]"));
    expect(screen, contains("title: const Text('Fontes consideradas')"));
    expect(
      screen,
      contains('A busca cruzada continua disponível offline'),
    );
    expect(models, contains('crossStudy'));
    expect(models, contains("AiExplanationIntent.crossStudy => 'Síntese cruzada'"));
    expect(remote, contains("'intent': intent.name"));
  });
}

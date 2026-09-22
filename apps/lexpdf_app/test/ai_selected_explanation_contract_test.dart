import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('selected PDF text exposes authenticated Workers AI explanation flow', () {
    final menu = File('lib/src/widgets/pdf_selection_action_menu.dart').readAsStringSync();
    final workspace =
        File('lib/src/screens/pdf_workspace_stylus_screen.dart').readAsStringSync();
    final screen = File('lib/src/screens/ai_selection_explanation_screen.dart')
        .readAsStringSync();
    final remote = File('lib/src/core/ai/remote_ai_engine.dart').readAsStringSync();
    final config = File('lib/src/core/backend/backend_config.dart').readAsStringSync();

    expect(menu, contains("label: 'Explicar com IA'"));
    expect(menu, isNot(contains("label: 'Questão'")));
    expect(workspace, contains('AiSelectionExplanationScreen('));
    expect(screen, contains("label: 'Rápida'"));
    expect(screen, contains("label: 'Detalhada'"));
    expect(screen, contains("label: 'Aprofundada'"));
    expect(screen, contains("label: 'Modo Concurso'"));
    expect(screen, contains("label: const Text('Simplificar')"));
    expect(screen, contains("label: const Text('Dar exemplo')"));
    expect(screen, contains("label: const Text('Sugerir flashcard')"));
    expect(screen, contains("label: const Text('Salvar como anotação')"));
    expect(screen, contains('lexpdf-note-v1:'));
    expect(screen, contains('AiAccessSession.bearerToken'));
    expect(screen, isNot(contains('Entre na sua conta LexPDF')));
    expect(workspace, contains('anchorX: anchorX'));
    expect(workspace, contains('anchorY: anchorY'));
    expect(menu, contains('enumerateFragmentBoundingRects()'));
    expect(remote, contains("'depth': explanationDepth.name"));
    expect(remote, contains("'intent': intent.name"));
    expect(config, contains('/v1/ai/explain'));
    expect(config, isNot(contains('SUPABASE_SECRET_KEY')));
  });
}

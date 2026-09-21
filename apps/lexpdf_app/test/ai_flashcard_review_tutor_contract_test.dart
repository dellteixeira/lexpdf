import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('flashcard review tutor opens only after again or hard grades', () {
    final screen =
        File('lib/src/screens/advanced_study_screen.dart').readAsStringSync();
    final models = File('lib/src/core/ai/ai_models.dart').readAsStringSync();
    final remote =
        File('lib/src/core/ai/remote_ai_engine.dart').readAsStringSync();

    expect(screen, contains('item.kind == StudyItemKind.flashcard'));
    expect(screen, contains('grade == StudyReviewGrade.again'));
    expect(screen, contains('grade == StudyReviewGrade.hard'));
    expect(screen, contains('AiExplanationIntent.reviewTutor'));
    expect(screen, contains('currentSession?.accessToken'));
    expect(screen, contains('O flashcard original não foi alterado.'));
    expect(screen, contains("child: const Text('Fechar e continuar')"));
    expect(screen, contains("label: const Text('Abrir página original')"));
    expect(screen, contains('Preparando reforço com o Tutor IA'));
    expect(models, contains('reviewTutor'));
    expect(
      models,
      contains("AiExplanationIntent.reviewTutor => 'Tutor de revisão'"),
    );
    expect(remote, contains("'intent': intent.name"));
  });
}

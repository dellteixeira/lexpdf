import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('continuous chat supports PDF and library scopes with persisted context', () {
    final chat =
        File('lib/src/screens/ai_context_chat_screen.dart').readAsStringSync();
    final pdf =
        File('lib/src/screens/pdf_workspace_screen.dart').readAsStringSync();
    final study =
        File('lib/src/screens/advanced_study_screen.dart').readAsStringSync();
    final models = File('lib/src/core/ai/ai_models.dart').readAsStringSync();

    expect(chat, contains('HISTÓRICO DA CONVERSA'));
    expect(chat, contains('AiExplanationIntent.contextChat'));
    expect(chat, contains('LocalAiChatStore'));
    expect(chat, contains('HybridRagService'));
    expect(chat, contains('Nova conversa'));
    expect(chat, contains('Fontes desta resposta'));
    expect(chat, contains('currentSession?.accessToken'));
    expect(pdf, contains("'chat-pdf'"));
    expect(pdf, contains('Chat com este PDF'));
    expect(study, contains('Chat com a biblioteca'));
    expect(models, contains('contextChat'));
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('library RAG and contextual chat have offline local retrieval fallback', () {
    final chat =
        File('lib/src/screens/ai_context_chat_screen.dart').readAsStringSync();
    final study =
        File('lib/src/screens/advanced_study_screen.dart').readAsStringSync();

    expect(chat, contains('LocalAiEmbeddingService'));
    expect(chat, contains('LocalGroundedAnswerEngine'));
    expect(chat, contains('A resposta funciona offline'));
    expect(study, contains('embeddings locais'));
    expect(study, contains('índice vetorial LSH'));
    expect(study, contains('_onlineAiToken'));
    expect(study, contains('LocalGroundedAnswerEngine'));
  });
}

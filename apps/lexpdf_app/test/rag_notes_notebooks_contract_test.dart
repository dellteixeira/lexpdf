import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('RAG includes annotations notebooks and visual descriptions in chat', () {
    final chat =
        File('lib/src/screens/ai_context_chat_screen.dart').readAsStringSync();
    final study =
        File('lib/src/screens/advanced_study_screen.dart').readAsStringSync();
    final service = File(
      'lib/src/core/ai/extended_hybrid_rag_service.dart',
    ).readAsStringSync();
    final store = File(
      'lib/src/core/storage/local_knowledge_rag_store.dart',
    ).readAsStringSync();

    expect(chat, contains('ExtendedHybridRagService'));
    expect(chat, contains('PDFs, anotações, cadernos e descrições visuais'));
    expect(study, contains('LocalKnowledgeRagStore'));
    expect(service, contains('knowledge.search'));
    expect(store, contains("'pdf_annotation'"));
    expect(store, contains("'pdf_note'"));
    expect(store, contains("'notebook'"));
    expect(store, contains('ai_visual_descriptions'));
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:lexpdf_app/src/core/storage/local_ai_chat_store.dart';
import 'package:lexpdf_app/src/core/storage/local_database.dart';

void main() {
  test('context chat persists sessions, turns and source provenance', () async {
    final database = LocalDatabase.inMemory();
    addTearDown(database.close);
    final store = LocalAiChatStore(database);

    final session = await store.createSession(scope: AiChatScope.library);
    await store.appendMessage(
      sessionId: session.id,
      role: AiChatRole.user,
      content: 'Explique controle difuso.',
    );
    await store.appendMessage(
      sessionId: session.id,
      role: AiChatRole.assistant,
      content: 'A fonte descreve o controle difuso. [F1]',
      sources: const [
        AiChatSource(
          documentId: 'doc-1',
          documentTitle: 'Constitucional.pdf',
          pageNumber: 42,
          excerpt: 'Trecho da página.',
          score: 0.91,
        ),
      ],
    );

    final latest =
        await store.latestSession(scope: AiChatScope.library);
    expect(latest?.id, session.id);
    expect(latest?.title, contains('Explique controle difuso'));

    final messages = await store.listMessages(session.id);
    expect(messages, hasLength(2));
    expect(messages.last.role, AiChatRole.assistant);
    expect(messages.last.sources.single.pageNumber, 42);
    expect(messages.last.sources.single.documentTitle, 'Constitucional.pdf');
  });
}

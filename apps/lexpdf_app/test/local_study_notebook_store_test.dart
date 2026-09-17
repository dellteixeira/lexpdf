import 'package:flutter_test/flutter_test.dart';
import 'package:lexpdf_app/src/core/ai/ai_models.dart';
import 'package:lexpdf_app/src/core/storage/local_database.dart';
import 'package:lexpdf_app/src/core/storage/local_study_notebook_store.dart';

void main() {
  test('saves generated flashcards into the existing notebook model', () async {
    final database = LocalDatabase.inMemory();
    addTearDown(database.close);
    final store = LocalStudyNotebookStore(database);

    final saved = await store.saveResult(
      documentId: 'doc-1',
      documentTitle: 'Constituição.pdf',
      result: const AiStudyResult(
        action: AiStudyAction.flashcards,
        engine: AiEngineKind.local,
        sourceText: 'A República Federativa do Brasil constitui-se em Estado Democrático de Direito.',
        flashcards: [
          AiFlashcard(
            question: 'Como se constitui a República Federativa do Brasil?',
            answer: 'Em Estado Democrático de Direito.',
          ),
          AiFlashcard(
            question: 'Qual é a fonte deste flashcard?',
            answer: 'O trecho selecionado no PDF.',
          ),
        ],
      ),
    );

    expect(saved.notebookId, 'study-notebook-doc-1');
    expect(saved.savedItems, 2);

    final notebook = database.database.select(
      'SELECT title FROM notebooks WHERE id = ?;',
      [saved.notebookId],
    );
    expect(notebook.single['title'], 'Estudo — Constituição.pdf');

    final objects = database.database.select(
      '''
      SELECT o.text_value
      FROM notebook_objects o
      JOIN notebook_pages p ON p.id = o.page_id
      WHERE p.notebook_id = ?
      ORDER BY o.created_at;
      ''',
      [saved.notebookId],
    );
    expect(objects, hasLength(2));
    expect(objects.first['text_value'], contains('FLASHCARD'));
    expect(objects.first['text_value'], contains('P:'));
    expect(objects.first['text_value'], contains('R:'));
    expect(objects.first['text_value'], contains('Constituição.pdf'));
  });

  test('uses SAVEPOINT so study persistence is safe inside an outer transaction', () async {
    final database = LocalDatabase.inMemory();
    addTearDown(database.close);
    final store = LocalStudyNotebookStore(database);

    database.database.execute('BEGIN IMMEDIATE;');
    try {
      final saved = await store.saveResult(
        documentId: 'doc-nested',
        documentTitle: 'Lei.pdf',
        result: const AiStudyResult(
          action: AiStudyAction.explain,
          engine: AiEngineKind.local,
          sourceText: 'Trecho selecionado',
          text: 'Explicação local do trecho.',
        ),
      );
      expect(saved.savedItems, 1);
      expect(
        database.database.select(
          'SELECT COUNT(*) AS count FROM notebooks WHERE id = ?;',
          [saved.notebookId],
        ).single['count'],
        1,
      );
    } finally {
      database.database.execute('ROLLBACK;');
    }

    expect(
      database.database
          .select('SELECT COUNT(*) AS count FROM notebooks;')
          .single['count'],
      0,
    );
  });

  test('questions and explanations are stored as editable text objects', () async {
    final database = LocalDatabase.inMemory();
    addTearDown(database.close);
    final store = LocalStudyNotebookStore(database);

    await store.saveResult(
      documentId: 'doc-2',
      documentTitle: 'Direito.pdf',
      result: const AiStudyResult(
        action: AiStudyAction.questions,
        engine: AiEngineKind.local,
        sourceText: 'Texto-base',
        questions: ['Questão 1?', 'Questão 2?'],
      ),
    );
    await store.saveResult(
      documentId: 'doc-2',
      documentTitle: 'Direito.pdf',
      result: const AiStudyResult(
        action: AiStudyAction.explain,
        engine: AiEngineKind.local,
        sourceText: 'Texto-base',
        text: 'Explicação do conteúdo.',
      ),
    );

    final rows = database.database.select(
      '''
      SELECT o.type, o.text_value
      FROM notebook_objects o
      JOIN notebook_pages p ON p.id = o.page_id
      WHERE p.notebook_id = 'study-notebook-doc-2'
      ORDER BY o.created_at;
      ''',
    );
    expect(rows, hasLength(3));
    expect(rows.every((row) => row['type'] == 'text'), isTrue);
    expect(rows[0]['text_value'], contains('QUESTÃO'));
    expect(rows[2]['text_value'], contains('EXPLICAÇÃO'));
  });
}

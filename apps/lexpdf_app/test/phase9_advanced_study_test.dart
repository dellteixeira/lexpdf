import 'package:flutter_test/flutter_test.dart';
import 'package:lexpdf_app/src/core/ai/ai_models.dart';
import 'package:lexpdf_app/src/core/storage/local_advanced_study_store.dart';
import 'package:lexpdf_app/src/core/storage/local_database.dart';
import 'package:lexpdf_app/src/core/storage/local_study_notebook_store.dart';
import 'package:lexpdf_app/src/core/study/advanced_study_models.dart';

void main() {
  late LocalDatabase db;

  setUp(() {
    db = LocalDatabase.inMemory();
    final now = DateTime.utc(2026, 9, 17).toIso8601String();
    db.database.execute('''
      INSERT INTO documents(
        id, title, filename, created_at, updated_at
      ) VALUES ('doc-1', 'Direito Constitucional', 'cf.pdf', ?, ?);
    ''', [now, now]);
  });

  tearDown(() => db.close());

  test('generated flashcards remain editable in notebook and reviewable', () async {
    final result = AiStudyResult(
      action: AiStudyAction.flashcards,
      engine: AiEngineKind.local,
      sourceText: 'A Constituição assegura direitos e garantias fundamentais.',
      flashcards: const [
        AiFlashcard(
          question: 'O que a Constituição assegura?',
          answer: 'Direitos e garantias fundamentais.',
        ),
        AiFlashcard(
          question: 'Qual é a fonte deste card?',
          answer: 'O trecho selecionado do PDF.',
        ),
      ],
    );

    final saved = await LocalStudyNotebookStore(db).saveResult(
      documentId: 'doc-1',
      documentTitle: 'Direito Constitucional',
      result: result,
      sourcePage: 5,
      subject: 'Direitos fundamentais',
      tags: const ['CF', 'art. 5º'],
    );

    expect(saved.savedItems, 2);
    expect(
      db.database.select('SELECT COUNT(*) AS c FROM notebook_objects;').single['c'],
      2,
    );

    final store = LocalAdvancedStudyStore(db);
    final items = await store.listItems(kind: StudyItemKind.flashcard);
    expect(items, hasLength(2));
    expect(items.first.documentId, 'doc-1');
    expect(items.first.sourcePage, 5);
    expect(items.first.subject, 'Direitos fundamentais');
    expect(items.first.tags, contains('art. 5º'));
    expect(await store.listDue(), hasLength(2));
  });

  test('spaced review updates due date and session statistics', () async {
    final result = AiStudyResult(
      action: AiStudyAction.flashcards,
      engine: AiEngineKind.local,
      sourceText: 'Texto base.',
      flashcards: const [
        AiFlashcard(question: 'Pergunta', answer: 'Resposta'),
      ],
    );
    await LocalStudyNotebookStore(db).saveResult(
      documentId: 'doc-1',
      documentTitle: 'Direito Constitucional',
      result: result,
    );

    final store = LocalAdvancedStudyStore(db);
    final item = (await store.listDue()).single;
    final session = await store.startSession();
    final state = await store.recordReview(
      itemId: item.id,
      grade: StudyReviewGrade.good,
      sessionId: session,
    );
    await store.finishSession(session);

    expect(state.repetitions, 1);
    expect(state.intervalDays, 1);
    expect(state.dueAt.isAfter(DateTime.now().toUtc()), isTrue);

    final stats = await store.dashboardStats();
    expect(stats.totalItems, 1);
    expect(stats.reviewedToday, 1);
    expect(stats.correctToday, 1);
    expect(stats.accuracyToday, 1);
  });

  test('review scheduler keeps hard/again states conservative', () async {
    final result = AiStudyResult(
      action: AiStudyAction.questions,
      engine: AiEngineKind.local,
      sourceText: 'Texto base.',
      questions: const ['Explique o conceito.'],
    );
    await LocalStudyNotebookStore(db).saveResult(
      documentId: 'doc-1',
      documentTitle: 'Direito Constitucional',
      result: result,
    );

    final store = LocalAdvancedStudyStore(db);
    final item = (await store.listDue()).single;
    final hard = await store.recordReview(
      itemId: item.id,
      grade: StudyReviewGrade.hard,
    );
    expect(hard.easeFactor, lessThan(2.5));

    final again = await store.recordReview(
      itemId: item.id,
      grade: StudyReviewGrade.again,
    );
    expect(again.repetitions, 0);
    expect(again.lapses, 1);
    expect(again.intervalDays, lessThan(1));
  });
}

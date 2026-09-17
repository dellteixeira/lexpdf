import 'dart:convert';

import '../ai/ai_models.dart';
import '../study/advanced_study_models.dart';
import 'local_database.dart';

class LocalAdvancedStudyStore {
  LocalAdvancedStudyStore(this.db) {
    _ensureTables();
  }

  final LocalDatabase db;

  void _ensureTables() {
    db.database.execute('''
      CREATE TABLE IF NOT EXISTS study_items (
        id TEXT PRIMARY KEY,
        notebook_id TEXT REFERENCES notebooks(id) ON DELETE SET NULL,
        document_id TEXT REFERENCES documents(id) ON DELETE SET NULL,
        kind TEXT NOT NULL CHECK(kind IN ('flashcard', 'question', 'explanation', 'summary')),
        prompt TEXT NOT NULL,
        answer TEXT NOT NULL DEFAULT '',
        commentary TEXT NOT NULL DEFAULT '',
        source_page INTEGER CHECK(source_page IS NULL OR source_page >= 1),
        source_text TEXT NOT NULL DEFAULT '',
        subject TEXT NOT NULL DEFAULT '',
        tags_json TEXT NOT NULL DEFAULT '[]',
        difficulty INTEGER NOT NULL DEFAULT 3 CHECK(difficulty BETWEEN 1 AND 5),
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      );
    ''');
    db.database.execute('''
      CREATE INDEX IF NOT EXISTS study_items_notebook_idx
      ON study_items(notebook_id, updated_at DESC);
    ''');
    db.database.execute('''
      CREATE INDEX IF NOT EXISTS study_items_document_idx
      ON study_items(document_id, source_page);
    ''');
    db.database.execute('''
      CREATE TABLE IF NOT EXISTS study_review_state (
        item_id TEXT PRIMARY KEY REFERENCES study_items(id) ON DELETE CASCADE,
        due_at TEXT NOT NULL,
        interval_days REAL NOT NULL DEFAULT 0,
        ease_factor REAL NOT NULL DEFAULT 2.5,
        repetitions INTEGER NOT NULL DEFAULT 0,
        lapses INTEGER NOT NULL DEFAULT 0,
        last_grade TEXT CHECK(last_grade IS NULL OR last_grade IN ('again', 'hard', 'good', 'easy')),
        last_reviewed_at TEXT
      );
    ''');
    db.database.execute('''
      CREATE INDEX IF NOT EXISTS study_review_due_idx
      ON study_review_state(due_at);
    ''');
    db.database.execute('''
      CREATE TABLE IF NOT EXISTS study_sessions (
        id TEXT PRIMARY KEY,
        started_at TEXT NOT NULL,
        ended_at TEXT,
        reviewed_count INTEGER NOT NULL DEFAULT 0,
        correct_count INTEGER NOT NULL DEFAULT 0
      );
    ''');
  }

  Future<int> saveGeneratedResult({
    required String documentId,
    required String documentTitle,
    required String notebookId,
    required AiStudyResult result,
    int? sourcePage,
    String subject = '',
    List<String> tags = const [],
  }) async {
    final now = DateTime.now().toUtc();
    final items = <StudyItem>[];
    var ordinal = 0;

    StudyItem build({
      required StudyItemKind kind,
      required String prompt,
      required String answer,
      String commentary = '',
    }) {
      final id =
          'study-${now.microsecondsSinceEpoch.toRadixString(36)}-${ordinal++}';
      return StudyItem(
        id: id,
        kind: kind,
        prompt: prompt.trim(),
        answer: answer.trim(),
        commentary: commentary.trim(),
        notebookId: notebookId,
        documentId: documentId,
        documentTitle: documentTitle,
        sourcePage: sourcePage,
        sourceText: result.sourceText.trim(),
        subject: subject.trim(),
        tags: tags
            .map((tag) => tag.trim())
            .where((tag) => tag.isNotEmpty)
            .toSet()
            .toList(growable: false),
        createdAt: now,
        updatedAt: now,
      );
    }

    switch (result.action) {
      case AiStudyAction.flashcards:
        for (final card in result.flashcards) {
          if (card.question.trim().isEmpty || card.answer.trim().isEmpty) continue;
          items.add(build(
            kind: StudyItemKind.flashcard,
            prompt: card.question,
            answer: card.answer,
          ));
        }
        break;
      case AiStudyAction.questions:
        for (final question in result.questions) {
          final text = question.trim();
          if (text.isEmpty) continue;
          items.add(build(
            kind: StudyItemKind.question,
            prompt: text,
            answer: '',
          ));
        }
        break;
      case AiStudyAction.explain:
        final text = result.text?.trim() ?? '';
        if (text.isNotEmpty) {
          items.add(build(
            kind: StudyItemKind.explanation,
            prompt: result.sourceText.trim(),
            answer: text,
          ));
        }
        break;
      case AiStudyAction.summarize:
        final text = result.text?.trim() ?? '';
        if (text.isNotEmpty) {
          items.add(build(
            kind: StudyItemKind.summary,
            prompt: result.sourceText.trim(),
            answer: text,
          ));
        }
        break;
    }

    if (items.isEmpty) return 0;
    final savepoint = 'advanced_study_${now.microsecondsSinceEpoch}';
    db.database.execute('SAVEPOINT $savepoint;');
    try {
      for (final item in items) {
        _insertItem(item);
      }
      db.database.execute('RELEASE SAVEPOINT $savepoint;');
      return items.length;
    } catch (_) {
      db.database.execute('ROLLBACK TO SAVEPOINT $savepoint;');
      db.database.execute('RELEASE SAVEPOINT $savepoint;');
      rethrow;
    }
  }

  Future<List<StudyItem>> listItems({
    String? notebookId,
    StudyItemKind? kind,
    int limit = 500,
  }) async {
    final clauses = <String>[];
    final args = <Object?>[];
    if (notebookId != null) {
      clauses.add('i.notebook_id = ?');
      args.add(notebookId);
    }
    if (kind != null) {
      clauses.add('i.kind = ?');
      args.add(kind.name);
    }
    final where = clauses.isEmpty ? '' : 'WHERE ${clauses.join(' AND ')}';
    args.add(limit);
    final rows = db.database.select('''
      SELECT i.*, d.title AS document_title
      FROM study_items i
      LEFT JOIN documents d ON d.id = i.document_id
      $where
      ORDER BY i.updated_at DESC
      LIMIT ?;
    ''', args);
    return rows.map(_itemFromRow).toList(growable: false);
  }

  Future<List<StudyItem>> listDue({int limit = 100}) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final rows = db.database.select('''
      SELECT i.*, d.title AS document_title
      FROM study_items i
      JOIN study_review_state r ON r.item_id = i.id
      LEFT JOIN documents d ON d.id = i.document_id
      WHERE r.due_at <= ?
      ORDER BY r.due_at, i.created_at
      LIMIT ?;
    ''', [now, limit]);
    return rows.map(_itemFromRow).toList(growable: false);
  }

  Future<StudyReviewState?> reviewState(String itemId) async {
    final rows = db.database.select(
      'SELECT * FROM study_review_state WHERE item_id = ? LIMIT 1;',
      [itemId],
    );
    return rows.isEmpty ? null : _reviewFromRow(rows.first);
  }

  Future<StudyReviewState> recordReview({
    required String itemId,
    required StudyReviewGrade grade,
    String? sessionId,
  }) async {
    final now = DateTime.now().toUtc();
    final current = await reviewState(itemId) ?? StudyReviewState(
      itemId: itemId,
      dueAt: now,
      intervalDays: 0,
      easeFactor: 2.5,
      repetitions: 0,
      lapses: 0,
    );

    var ease = current.easeFactor;
    var repetitions = current.repetitions;
    var lapses = current.lapses;
    double interval;

    switch (grade) {
      case StudyReviewGrade.again:
        repetitions = 0;
        lapses += 1;
        ease = (ease - 0.2).clamp(1.3, 3.0).toDouble();
        interval = 0.04;
        break;
      case StudyReviewGrade.hard:
        repetitions += 1;
        ease = (ease - 0.15).clamp(1.3, 3.0).toDouble();
        interval = current.intervalDays <= 1
            ? 1.0
            : (current.intervalDays * 1.2).clamp(1.0, 36500.0).toDouble();
        break;
      case StudyReviewGrade.good:
        repetitions += 1;
        interval = repetitions == 1
            ? 1.0
            : repetitions == 2
                ? 6.0
                : (current.intervalDays * ease)
                    .clamp(1.0, 36500.0)
                    .toDouble();
        break;
      case StudyReviewGrade.easy:
        repetitions += 1;
        ease = (ease + 0.15).clamp(1.3, 3.0).toDouble();
        interval = repetitions == 1
            ? 4.0
            : (current.intervalDays * ease * 1.3)
                .clamp(4.0, 36500.0)
                .toDouble();
        break;
    }

    final dueAt = now.add(Duration(minutes: (interval * 1440).round()));
    db.database.execute('''
      INSERT INTO study_review_state(
        item_id, due_at, interval_days, ease_factor, repetitions, lapses,
        last_grade, last_reviewed_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(item_id) DO UPDATE SET
        due_at = excluded.due_at,
        interval_days = excluded.interval_days,
        ease_factor = excluded.ease_factor,
        repetitions = excluded.repetitions,
        lapses = excluded.lapses,
        last_grade = excluded.last_grade,
        last_reviewed_at = excluded.last_reviewed_at;
    ''', [
      itemId,
      dueAt.toIso8601String(),
      interval,
      ease,
      repetitions,
      lapses,
      grade.name,
      now.toIso8601String(),
    ]);

    if (sessionId != null) {
      final isCorrect =
          grade == StudyReviewGrade.good || grade == StudyReviewGrade.easy;
      db.database.execute('''
        UPDATE study_sessions
        SET reviewed_count = reviewed_count + 1,
            correct_count = correct_count + ?
        WHERE id = ?;
      ''', [isCorrect ? 1 : 0, sessionId]);
    }

    return StudyReviewState(
      itemId: itemId,
      dueAt: dueAt,
      intervalDays: interval,
      easeFactor: ease,
      repetitions: repetitions,
      lapses: lapses,
      lastGrade: grade,
      lastReviewedAt: now,
    );
  }

  Future<String> startSession() async {
    final now = DateTime.now().toUtc();
    final id = 'study-session-${now.microsecondsSinceEpoch.toRadixString(36)}';
    db.database.execute('''
      INSERT INTO study_sessions(id, started_at, reviewed_count, correct_count)
      VALUES (?, ?, 0, 0);
    ''', [id, now.toIso8601String()]);
    return id;
  }

  Future<void> finishSession(String sessionId) async {
    db.database.execute(
      'UPDATE study_sessions SET ended_at = ? WHERE id = ? AND ended_at IS NULL;',
      [DateTime.now().toUtc().toIso8601String(), sessionId],
    );
  }

  Future<StudyDashboardStats> dashboardStats() async {
    final now = DateTime.now().toUtc();
    final start = DateTime.utc(now.year, now.month, now.day);
    final end = start.add(const Duration(days: 1));
    final row = db.database.select('''
      SELECT
        (SELECT COUNT(*) FROM study_items) AS total_items,
        (SELECT COUNT(*) FROM study_review_state WHERE due_at <= ?) AS due_items,
        COALESCE((SELECT SUM(reviewed_count) FROM study_sessions
          WHERE started_at >= ? AND started_at < ?), 0) AS reviewed_today,
        COALESCE((SELECT SUM(correct_count) FROM study_sessions
          WHERE started_at >= ? AND started_at < ?), 0) AS correct_today;
    ''', [
      now.toIso8601String(),
      start.toIso8601String(),
      end.toIso8601String(),
      start.toIso8601String(),
      end.toIso8601String(),
    ]).single;

    final reviewDays = db.database.select('''
      SELECT DISTINCT substr(last_reviewed_at, 1, 10) AS review_day
      FROM study_review_state
      WHERE last_reviewed_at IS NOT NULL
      ORDER BY review_day DESC;
    ''').map((r) => r['review_day'] as String).toSet();

    var streak = 0;
    var cursor = start;
    while (reviewDays.contains(cursor.toIso8601String().substring(0, 10))) {
      streak += 1;
      cursor = cursor.subtract(const Duration(days: 1));
    }

    return StudyDashboardStats(
      totalItems: row['total_items'] as int? ?? 0,
      dueItems: row['due_items'] as int? ?? 0,
      reviewedToday: row['reviewed_today'] as int? ?? 0,
      correctToday: row['correct_today'] as int? ?? 0,
      streakDays: streak,
    );
  }

  Future<List<StudySourceHit>> searchSources(
    String query, {
    int limit = 100,
  }) async {
    final normalized = query.trim();
    if (normalized.isEmpty) return const [];
    _ensureFtsTable();
    final tokens = normalized
        .split(RegExp(r'\s+'))
        .where((token) => token.isNotEmpty)
        .map((token) => '"${token.replaceAll('"', '""')}"*')
        .join(' AND ');
    if (tokens.isEmpty) return const [];

    final rows = db.database.select('''
      SELECT owner_id, page_number, title,
             snippet(global_search_fts, 4, '‹', '›', '…', 28) AS snippet_text,
             bm25(global_search_fts, 2.0, 1.0) AS rank
      FROM global_search_fts
      WHERE global_search_fts MATCH ? AND kind = 'pdf_text'
      ORDER BY rank
      LIMIT ?;
    ''', [tokens, limit]);

    return rows
        .map((row) => StudySourceHit(
              documentId: row['owner_id'] as String,
              documentTitle: row['title'] as String,
              pageNumber: int.tryParse(row['page_number'].toString()) ?? 1,
              snippet: row['snippet_text'] as String? ?? '',
            ))
        .toList(growable: false);
  }

  void _ensureFtsTable() {
    db.database.execute('''
      CREATE VIRTUAL TABLE IF NOT EXISTS global_search_fts USING fts5(
        kind UNINDEXED,
        owner_id UNINDEXED,
        page_number UNINDEXED,
        title,
        content,
        tokenize = 'unicode61 remove_diacritics 2'
      );
    ''');
  }

  void _insertItem(StudyItem item) {
    db.database.execute('''
      INSERT INTO study_items(
        id, notebook_id, document_id, kind, prompt, answer, commentary,
        source_page, source_text, subject, tags_json, difficulty,
        created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
    ''', [
      item.id,
      item.notebookId,
      item.documentId,
      item.kind.name,
      item.prompt,
      item.answer,
      item.commentary,
      item.sourcePage,
      item.sourceText,
      item.subject,
      jsonEncode(item.tags),
      item.difficulty.clamp(1, 5),
      item.createdAt.toUtc().toIso8601String(),
      item.updatedAt.toUtc().toIso8601String(),
    ]);
    db.database.execute('''
      INSERT INTO study_review_state(
        item_id, due_at, interval_days, ease_factor, repetitions, lapses
      ) VALUES (?, ?, 0, 2.5, 0, 0);
    ''', [item.id, item.createdAt.toUtc().toIso8601String()]);
  }

  StudyItem _itemFromRow(dynamic row) {
    List<String> tags = const [];
    try {
      tags = (jsonDecode(row['tags_json'] as String? ?? '[]') as List)
          .map((value) => value.toString())
          .toList(growable: false);
    } catch (_) {
      tags = const [];
    }
    return StudyItem(
      id: row['id'] as String,
      kind: StudyItemKind.values.firstWhere(
        (value) => value.name == row['kind'],
        orElse: () => StudyItemKind.flashcard,
      ),
      prompt: row['prompt'] as String? ?? '',
      answer: row['answer'] as String? ?? '',
      commentary: row['commentary'] as String? ?? '',
      notebookId: row['notebook_id'] as String?,
      documentId: row['document_id'] as String?,
      documentTitle: row['document_title'] as String?,
      sourcePage: row['source_page'] as int?,
      sourceText: row['source_text'] as String? ?? '',
      subject: row['subject'] as String? ?? '',
      tags: tags,
      difficulty: row['difficulty'] as int? ?? 3,
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }

  StudyReviewState _reviewFromRow(dynamic row) => StudyReviewState(
        itemId: row['item_id'] as String,
        dueAt: DateTime.parse(row['due_at'] as String),
        intervalDays: (row['interval_days'] as num).toDouble(),
        easeFactor: (row['ease_factor'] as num).toDouble(),
        repetitions: row['repetitions'] as int,
        lapses: row['lapses'] as int,
        lastGrade: row['last_grade'] == null
            ? null
            : StudyReviewGrade.values.firstWhere(
                (value) => value.name == row['last_grade'],
                orElse: () => StudyReviewGrade.good,
              ),
        lastReviewedAt: row['last_reviewed_at'] == null
            ? null
            : DateTime.parse(row['last_reviewed_at'] as String),
      );
}

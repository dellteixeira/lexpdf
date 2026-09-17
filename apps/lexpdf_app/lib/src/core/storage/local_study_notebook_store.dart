import '../ai/ai_models.dart';
import 'local_advanced_study_store.dart';
import 'local_database.dart';

class StudyNotebookSaveResult {
  const StudyNotebookSaveResult({
    required this.notebookId,
    required this.savedItems,
  });

  final String notebookId;
  final int savedItems;
}

/// Persists generated study material into the existing notebook model and the
/// structured Phase 9 study index. Both live in the same encrypted database.
class LocalStudyNotebookStore {
  const LocalStudyNotebookStore(this.db);

  final LocalDatabase db;

  Future<StudyNotebookSaveResult> saveResult({
    required String documentId,
    required String documentTitle,
    required AiStudyResult result,
    int? sourcePage,
    String subject = '',
    List<String> tags = const [],
  }) async {
    final entries = _entriesFor(result);
    if (entries.isEmpty) {
      return StudyNotebookSaveResult(
        notebookId: _notebookId(documentId),
        savedItems: 0,
      );
    }

    final now = DateTime.now().toUtc();
    final notebookId = _notebookId(documentId);
    final savepoint = 'study_${now.microsecondsSinceEpoch}';
    db.database.execute('SAVEPOINT $savepoint;');
    try {
      db.database.execute(
        '''
        INSERT INTO notebooks(id, title, created_at, updated_at)
        VALUES (?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
          title = excluded.title,
          updated_at = excluded.updated_at;
        ''',
        [
          notebookId,
          'Estudo — $documentTitle',
          now.toIso8601String(),
          now.toIso8601String(),
        ],
      );

      var saved = 0;
      for (final entry in entries) {
        final placement = _nextPlacement(notebookId);
        _ensurePageAndLayer(
          notebookId: notebookId,
          pageNumber: placement.pageNumber,
          now: now,
        );

        final pageId = _pageId(notebookId, placement.pageNumber);
        final layerId = _layerId(pageId);
        final objectId =
            'study-object-${now.microsecondsSinceEpoch.toRadixString(36)}-$saved';
        final source = result.sourceText.trim();
        final sourcePreview = source.length <= 280
            ? source
            : '${source.substring(0, 280)}…';
        final text = '${entry.label}\n${entry.body}\n\nFonte: $documentTitle'
            '${sourcePreview.isEmpty ? '' : '\nTrecho: $sourcePreview'}';

        db.database.execute(
          '''
          INSERT INTO notebook_objects(
            id, page_id, type, x, y, width, height, rotation, color_value,
            fill_color_value, stroke_width, text_value, font_size, font_family,
            font_bold, font_italic, font_underline, text_align, image_path,
            created_at, updated_at
          ) VALUES (?, ?, 'text', ?, ?, ?, ?, 0, ?, NULL, 2, ?, 18, NULL,
                    0, 0, 0, 'left', NULL, ?, ?);
          ''',
          [
            objectId,
            pageId,
            72.0,
            placement.y,
            936.0,
            150.0,
            0xFF1C1B1F,
            text,
            now.add(Duration(microseconds: saved)).toIso8601String(),
            now.add(Duration(microseconds: saved)).toIso8601String(),
          ],
        );
        db.database.execute(
          '''
          INSERT INTO notebook_layer_items(layer_id, item_type, item_id, created_at)
          VALUES (?, 'object', ?, ?);
          ''',
          [layerId, objectId, now.toIso8601String()],
        );
        saved++;
      }

      await LocalAdvancedStudyStore(db).saveGeneratedResult(
        documentId: documentId,
        documentTitle: documentTitle,
        notebookId: notebookId,
        result: result,
        sourcePage: sourcePage,
        subject: subject,
        tags: tags,
      );

      db.database.execute(
        'UPDATE notebooks SET updated_at = ? WHERE id = ?;',
        [DateTime.now().toUtc().toIso8601String(), notebookId],
      );
      db.database.execute('RELEASE SAVEPOINT $savepoint;');
      return StudyNotebookSaveResult(
        notebookId: notebookId,
        savedItems: saved,
      );
    } catch (_) {
      db.database.execute('ROLLBACK TO SAVEPOINT $savepoint;');
      db.database.execute('RELEASE SAVEPOINT $savepoint;');
      rethrow;
    }
  }

  List<_StudyEntry> _entriesFor(AiStudyResult result) {
    switch (result.action) {
      case AiStudyAction.flashcards:
        return [
          for (final card in result.flashcards)
            _StudyEntry(
              label: 'FLASHCARD',
              body: 'P: ${card.question}\nR: ${card.answer}',
            ),
        ];
      case AiStudyAction.questions:
        return [
          for (final question in result.questions)
            _StudyEntry(label: 'QUESTÃO', body: question),
        ];
      case AiStudyAction.explain:
        final text = result.text?.trim() ?? '';
        return text.isEmpty
            ? const []
            : [_StudyEntry(label: 'EXPLICAÇÃO', body: text)];
      case AiStudyAction.summarize:
        final text = result.text?.trim() ?? '';
        return text.isEmpty
            ? const []
            : [_StudyEntry(label: 'RESUMO', body: text)];
    }
  }

  _StudyPlacement _nextPlacement(String notebookId) {
    final pageRows = db.database.select(
      '''
      SELECT p.page_number,
             (SELECT COUNT(*) FROM notebook_objects o WHERE o.page_id = p.id) AS object_count
      FROM notebook_pages p
      WHERE p.notebook_id = ?
      ORDER BY p.page_number DESC
      LIMIT 1;
      ''',
      [notebookId],
    );
    if (pageRows.isEmpty) {
      return const _StudyPlacement(pageNumber: 1, y: 72.0);
    }
    final row = pageRows.first;
    final pageNumber = row['page_number'] as int;
    final count = row['object_count'] as int? ?? 0;
    const perPage = 7;
    if (count >= perPage) {
      return _StudyPlacement(pageNumber: pageNumber + 1, y: 72.0);
    }
    return _StudyPlacement(
      pageNumber: pageNumber,
      y: 72.0 + (count * 180.0),
    );
  }

  void _ensurePageAndLayer({
    required String notebookId,
    required int pageNumber,
    required DateTime now,
  }) {
    final pageId = _pageId(notebookId, pageNumber);
    final layerId = _layerId(pageId);
    final timestamp = now.toIso8601String();
    db.database.execute(
      '''
      INSERT OR IGNORE INTO notebook_pages(
        id, notebook_id, page_number, width, height, background, created_at, updated_at
      ) VALUES (?, ?, ?, 1080, 1440, 'blank', ?, ?);
      ''',
      [pageId, notebookId, pageNumber, timestamp, timestamp],
    );
    db.database.execute(
      '''
      INSERT OR IGNORE INTO notebook_layers(
        id, page_id, name, sort_order, is_visible, is_locked, created_at, updated_at
      ) VALUES (?, ?, 'Estudo', 0, 1, 0, ?, ?);
      ''',
      [layerId, pageId, timestamp, timestamp],
    );
  }

  String _notebookId(String documentId) => 'study-notebook-$documentId';
  String _pageId(String notebookId, int pageNumber) =>
      '$notebookId-page-$pageNumber';
  String _layerId(String pageId) => '$pageId-layer-0';
}

class _StudyEntry {
  const _StudyEntry({required this.label, required this.body});

  final String label;
  final String body;
}

class _StudyPlacement {
  const _StudyPlacement({required this.pageNumber, required this.y});

  final int pageNumber;
  final double y;
}

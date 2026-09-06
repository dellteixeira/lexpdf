import '../ink/ink_models.dart';
import 'local_database.dart';

class LocalInkStore {
  const LocalInkStore(this.db);

  final LocalDatabase db;

  Future<InkNotebook> ensureDefaultNotebook() async {
    const notebookId = 'default-notebook';
    final now = DateTime.now().toUtc();
    final iso = now.toIso8601String();
    db.database.execute('''
      INSERT INTO notebooks(id, title, created_at, updated_at)
      VALUES (?, ?, ?, ?)
      ON CONFLICT(id) DO NOTHING;
    ''', [notebookId, 'Meu caderno', iso, iso]);
    final row = db.database.select(
      'SELECT * FROM notebooks WHERE id = ? LIMIT 1;',
      [notebookId],
    ).single;
    return _notebookFromRow(row);
  }

  Future<InkNotebookPage> ensureDefaultPage() async {
    final notebook = await ensureDefaultNotebook();
    const pageId = 'default-page-1';
    final now = DateTime.now().toUtc().toIso8601String();
    db.database.execute('''
      INSERT INTO notebook_pages(
        id, notebook_id, page_number, width, height, background, created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO NOTHING;
    ''', [pageId, notebook.id, 1, 1080.0, 1440.0, 'blank', now, now]);
    return (await listPages(notebook.id)).first;
  }

  Future<List<InkNotebook>> listNotebooks() async {
    final rows = db.database.select(
      'SELECT * FROM notebooks ORDER BY updated_at DESC, created_at DESC;',
    );
    return rows.map(_notebookFromRow).toList(growable: false);
  }

  Future<InkNotebook> createNotebook(String title) async {
    final now = DateTime.now().toUtc();
    final id = 'notebook-${now.microsecondsSinceEpoch.toRadixString(36)}';
    final normalized = title.trim().isEmpty ? 'Novo caderno' : title.trim();
    final iso = now.toIso8601String();
    db.database.execute(
      'INSERT INTO notebooks(id, title, created_at, updated_at) VALUES (?, ?, ?, ?);',
      [id, normalized, iso, iso],
    );
    await createPage(id);
    return InkNotebook(id: id, title: normalized, createdAt: now, updatedAt: now);
  }

  Future<void> renameNotebook(String id, String title) async {
    final normalized = title.trim();
    if (normalized.isEmpty) return;
    db.database.execute(
      'UPDATE notebooks SET title = ?, updated_at = ? WHERE id = ?;',
      [normalized, DateTime.now().toUtc().toIso8601String(), id],
    );
  }

  Future<void> deleteNotebook(String id) async {
    db.database.execute('DELETE FROM notebooks WHERE id = ?;', [id]);
  }

  Future<List<InkNotebookPage>> listPages(String notebookId) async {
    final rows = db.database.select(
      'SELECT * FROM notebook_pages WHERE notebook_id = ? ORDER BY page_number ASC;',
      [notebookId],
    );
    return rows.map(_pageFromRow).toList(growable: false);
  }

  Future<InkNotebookPage> createPage(
    String notebookId, {
    InkPageBackground background = InkPageBackground.blank,
    double width = 1080,
    double height = 1440,
  }) async {
    final now = DateTime.now().toUtc();
    final maxRows = db.database.select(
      'SELECT COALESCE(MAX(page_number), 0) AS max_page FROM notebook_pages WHERE notebook_id = ?;',
      [notebookId],
    );
    final pageNumber = (maxRows.single['max_page'] as int) + 1;
    final id = 'page-${now.microsecondsSinceEpoch.toRadixString(36)}';
    final iso = now.toIso8601String();
    db.database.execute('''
      INSERT INTO notebook_pages(
        id, notebook_id, page_number, width, height, background, created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?);
    ''', [id, notebookId, pageNumber, width, height, background.dbValue, iso, iso]);
    _touchNotebook(notebookId);
    return InkNotebookPage(
      id: id,
      notebookId: notebookId,
      pageNumber: pageNumber,
      width: width,
      height: height,
      background: background,
    );
  }

  Future<InkNotebookPage> duplicatePage(InkNotebookPage source) async {
    final duplicate = await createPage(
      source.notebookId,
      background: source.background,
      width: source.width,
      height: source.height,
    );
    final sourceStrokes = await listStrokes(source.id);
    final now = DateTime.now().toUtc().microsecondsSinceEpoch;
    for (var index = 0; index < sourceStrokes.length; index++) {
      final stroke = sourceStrokes[index];
      await addStroke(
        InkStroke(
          id: 'stroke-${now.toRadixString(36)}-$index',
          pageId: duplicate.id,
          tool: stroke.tool,
          colorValue: stroke.colorValue,
          opacity: stroke.opacity,
          width: stroke.width,
          points: stroke.points,
          createdAt: stroke.createdAt,
        ),
      );
    }
    return duplicate;
  }

  Future<void> updatePageBackground(String pageId, InkPageBackground background) async {
    db.database.execute(
      'UPDATE notebook_pages SET background = ?, updated_at = ? WHERE id = ?;',
      [background.dbValue, DateTime.now().toUtc().toIso8601String(), pageId],
    );
  }

  Future<void> deletePage(String pageId) async {
    final rows = db.database.select(
      'SELECT notebook_id FROM notebook_pages WHERE id = ? LIMIT 1;',
      [pageId],
    );
    db.database.execute('DELETE FROM notebook_pages WHERE id = ?;', [pageId]);
    if (rows.isNotEmpty) _touchNotebook(rows.single['notebook_id'] as String);
  }

  Future<void> reorderPages(String notebookId, List<String> orderedPageIds) async {
    db.database.execute('BEGIN IMMEDIATE;');
    try {
      for (var index = 0; index < orderedPageIds.length; index++) {
        db.database.execute(
          'UPDATE notebook_pages SET page_number = ? WHERE id = ? AND notebook_id = ?;',
          [-(index + 1), orderedPageIds[index], notebookId],
        );
      }
      for (var index = 0; index < orderedPageIds.length; index++) {
        db.database.execute(
          'UPDATE notebook_pages SET page_number = ?, updated_at = ? WHERE id = ? AND notebook_id = ?;',
          [
            index + 1,
            DateTime.now().toUtc().toIso8601String(),
            orderedPageIds[index],
            notebookId,
          ],
        );
      }
      _touchNotebook(notebookId);
      db.database.execute('COMMIT;');
    } catch (_) {
      db.database.execute('ROLLBACK;');
      rethrow;
    }
  }

  Future<void> addStroke(InkStroke stroke) async {
    db.database.execute('''
      INSERT OR REPLACE INTO ink_strokes(
        id, page_id, tool, color_value, opacity, width, points_json, created_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?);
    ''', [
      stroke.id,
      stroke.pageId,
      _toolToDb(stroke.tool),
      stroke.colorValue,
      stroke.opacity,
      stroke.width,
      stroke.encodePoints(),
      stroke.createdAt.toUtc().toIso8601String(),
    ]);
  }

  Future<List<InkStroke>> listStrokes(String pageId) async {
    final rows = db.database.select(
      'SELECT * FROM ink_strokes WHERE page_id = ? ORDER BY created_at ASC;',
      [pageId],
    );
    return rows
        .map(
          (row) => InkStroke(
            id: row['id'] as String,
            pageId: row['page_id'] as String,
            tool: _toolFromDb(row['tool'] as String),
            colorValue: row['color_value'] as int,
            opacity: (row['opacity'] as num).toDouble(),
            width: (row['width'] as num).toDouble(),
            points: InkStroke.decodePoints(row['points_json'] as String),
            createdAt: DateTime.parse(row['created_at'] as String),
          ),
        )
        .toList(growable: false);
  }

  Future<void> deleteStroke(String id) async {
    db.database.execute('DELETE FROM ink_strokes WHERE id = ?;', [id]);
  }

  Future<void> clearPage(String pageId) async {
    db.database.execute('DELETE FROM ink_strokes WHERE page_id = ?;', [pageId]);
  }

  void _touchNotebook(String notebookId) {
    db.database.execute(
      'UPDATE notebooks SET updated_at = ? WHERE id = ?;',
      [DateTime.now().toUtc().toIso8601String(), notebookId],
    );
  }

  static InkNotebook _notebookFromRow(dynamic row) => InkNotebook(
        id: row['id'] as String,
        title: row['title'] as String,
        createdAt: DateTime.parse(row['created_at'] as String),
        updatedAt: DateTime.parse(row['updated_at'] as String),
      );

  static InkNotebookPage _pageFromRow(dynamic row) => InkNotebookPage(
        id: row['id'] as String,
        notebookId: row['notebook_id'] as String,
        pageNumber: row['page_number'] as int,
        width: (row['width'] as num).toDouble(),
        height: (row['height'] as num).toDouble(),
        background: InkPageBackground.fromDb(row['background'] as String),
      );

  static String _toolToDb(InkTool tool) => switch (tool) {
        InkTool.pen => 'pen',
        InkTool.pencil => 'pencil',
        InkTool.highlighter => 'highlighter',
      };

  static InkTool _toolFromDb(String value) => switch (value) {
        'pen' => InkTool.pen,
        'pencil' => InkTool.pencil,
        'highlighter' => InkTool.highlighter,
        _ => throw StateError('Ferramenta de tinta desconhecida: $value'),
      };
}

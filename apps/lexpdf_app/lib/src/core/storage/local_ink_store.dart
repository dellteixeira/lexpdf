import '../ink/ink_models.dart';
import 'local_database.dart';

class LocalInkStore {
  const LocalInkStore(this.db);

  final LocalDatabase db;

  Future<InkNotebookPage> ensureDefaultPage() async {
    const notebookId = 'default-notebook';
    const pageId = 'default-page-1';
    final now = DateTime.now().toUtc().toIso8601String();

    db.database.execute('''
      INSERT INTO notebooks(id, title, created_at, updated_at)
      VALUES (?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET updated_at = excluded.updated_at;
    ''', [notebookId, 'Meu caderno', now, now]);

    db.database.execute('''
      INSERT INTO notebook_pages(
        id, notebook_id, page_number, width, height, background, created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET updated_at = excluded.updated_at;
    ''', [pageId, notebookId, 1, 1080.0, 1440.0, 'blank', now, now]);

    return const InkNotebookPage(
      id: pageId,
      notebookId: notebookId,
      pageNumber: 1,
      width: 1080,
      height: 1440,
    );
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

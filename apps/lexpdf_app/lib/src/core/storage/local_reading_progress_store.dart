import 'local_database.dart';

class ReadingProgressState {
  const ReadingProgressState({
    required this.documentId,
    required this.pageNumber,
    required this.zoom,
    required this.scrollOffset,
    required this.viewMode,
    required this.updatedAt,
  });

  final String documentId;
  final int pageNumber;
  final double zoom;
  final double scrollOffset;
  final String viewMode;
  final DateTime updatedAt;
}

class LocalReadingProgressStore {
  const LocalReadingProgressStore(this.db);

  final LocalDatabase db;

  Future<ReadingProgressState?> get(String documentId) async {
    final rows = db.database.select(
      'SELECT * FROM reading_progress WHERE document_id = ? LIMIT 1;',
      [documentId],
    );
    if (rows.isEmpty) return null;

    final row = rows.first;
    return ReadingProgressState(
      documentId: row['document_id'] as String,
      pageNumber: row['page_number'] as int,
      zoom: (row['zoom'] as num).toDouble(),
      scrollOffset: (row['scroll_offset'] as num).toDouble(),
      viewMode: row['view_mode'] as String,
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }

  Future<void> save({
    required String documentId,
    required int pageNumber,
    double zoom = 1,
    double scrollOffset = 0,
    String viewMode = 'continuous',
  }) async {
    if (pageNumber < 1) {
      throw ArgumentError.value(pageNumber, 'pageNumber', 'Must be >= 1');
    }
    if (zoom <= 0) {
      throw ArgumentError.value(zoom, 'zoom', 'Must be > 0');
    }

    final now = DateTime.now().toUtc().toIso8601String();
    db.database.execute('''
      INSERT INTO reading_progress (
        document_id, page_number, zoom, scroll_offset, view_mode, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?)
      ON CONFLICT(document_id) DO UPDATE SET
        page_number = excluded.page_number,
        zoom = excluded.zoom,
        scroll_offset = excluded.scroll_offset,
        view_mode = excluded.view_mode,
        updated_at = excluded.updated_at;
    ''', [
      documentId,
      pageNumber,
      zoom,
      scrollOffset,
      viewMode,
      now,
    ]);
  }

  Future<void> clear(String documentId) async {
    db.database.execute(
      'DELETE FROM reading_progress WHERE document_id = ?;',
      [documentId],
    );
  }
}

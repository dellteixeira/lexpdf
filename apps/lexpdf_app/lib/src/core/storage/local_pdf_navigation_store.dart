import 'local_database.dart';

class PdfBookmark {
  const PdfBookmark({
    required this.id,
    required this.documentId,
    required this.pageNumber,
    required this.label,
    required this.createdAt,
  });

  final String id;
  final String documentId;
  final int pageNumber;
  final String label;
  final DateTime createdAt;
}

class LocalSearchHit {
  const LocalSearchHit({
    required this.kind,
    required this.title,
    required this.snippet,
    this.documentId,
    this.notebookId,
    this.pageNumber,
  });

  final String kind;
  final String title;
  final String snippet;
  final String? documentId;
  final String? notebookId;
  final int? pageNumber;
}

class LocalPdfNavigationStore {
  LocalPdfNavigationStore(this.db) {
    _ensureTables();
  }

  final LocalDatabase db;

  void _ensureTables() {
    db.database.execute('''
      CREATE TABLE IF NOT EXISTS pdf_bookmarks (
        id TEXT PRIMARY KEY,
        document_id TEXT NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
        page_number INTEGER NOT NULL CHECK(page_number >= 1),
        label TEXT NOT NULL,
        created_at TEXT NOT NULL,
        UNIQUE(document_id, page_number)
      );
    ''');
    db.database.execute('''
      CREATE INDEX IF NOT EXISTS pdf_bookmarks_document_page_idx
      ON pdf_bookmarks(document_id, page_number);
    ''');
    db.database.execute('''
      CREATE TABLE IF NOT EXISTS pdf_page_text_index (
        document_id TEXT NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
        page_number INTEGER NOT NULL CHECK(page_number >= 1),
        content TEXT NOT NULL,
        indexed_at TEXT NOT NULL,
        PRIMARY KEY(document_id, page_number)
      );
    ''');
    db.database.execute('''
      CREATE TABLE IF NOT EXISTS document_tags (
        document_id TEXT NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
        tag TEXT NOT NULL,
        PRIMARY KEY(document_id, tag)
      );
    ''');
  }

  Future<List<PdfBookmark>> listBookmarks(String documentId) async {
    final rows = db.database.select('''
      SELECT * FROM pdf_bookmarks
      WHERE document_id = ?
      ORDER BY page_number;
    ''', [documentId]);
    return rows
        .map(
          (row) => PdfBookmark(
            id: row['id'] as String,
            documentId: row['document_id'] as String,
            pageNumber: row['page_number'] as int,
            label: row['label'] as String,
            createdAt: DateTime.parse(row['created_at'] as String),
          ),
        )
        .toList(growable: false);
  }

  Future<void> toggleBookmark({
    required String documentId,
    required int pageNumber,
    String? label,
  }) async {
    if (pageNumber < 1) {
      throw ArgumentError.value(pageNumber, 'pageNumber', 'Must be >= 1');
    }
    final existing = db.database.select(
      'SELECT id FROM pdf_bookmarks WHERE document_id = ? AND page_number = ? LIMIT 1;',
      [documentId, pageNumber],
    );
    if (existing.isNotEmpty) {
      db.database.execute(
        'DELETE FROM pdf_bookmarks WHERE document_id = ? AND page_number = ?;',
        [documentId, pageNumber],
      );
      return;
    }
    final now = DateTime.now().toUtc();
    final id = 'bookmark-${documentId.hashCode.toUnsigned(32).toRadixString(36)}-${pageNumber.toRadixString(36)}-${now.microsecondsSinceEpoch.toRadixString(36)}';
    db.database.execute('''
      INSERT INTO pdf_bookmarks(id, document_id, page_number, label, created_at)
      VALUES (?, ?, ?, ?, ?);
    ''', [
      id,
      documentId,
      pageNumber,
      (label == null || label.trim().isEmpty) ? 'Página $pageNumber' : label.trim(),
      now.toIso8601String(),
    ]);
  }

  Future<void> replacePageTextIndex({
    required String documentId,
    required Map<int, String> pages,
  }) async {
    db.database.execute('BEGIN IMMEDIATE;');
    try {
      db.database.execute(
        'DELETE FROM pdf_page_text_index WHERE document_id = ?;',
        [documentId],
      );
      final now = DateTime.now().toUtc().toIso8601String();
      for (final entry in pages.entries) {
        if (entry.key < 1) continue;
        db.database.execute('''
          INSERT INTO pdf_page_text_index(document_id, page_number, content, indexed_at)
          VALUES (?, ?, ?, ?);
        ''', [documentId, entry.key, entry.value, now]);
      }
      db.database.execute('COMMIT;');
    } catch (_) {
      db.database.execute('ROLLBACK;');
      rethrow;
    }
  }

  Future<List<LocalSearchHit>> search(String query, {int limit = 100}) async {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return const [];
    final like = '%$normalized%';
    final hits = <LocalSearchHit>[];

    final documentRows = db.database.select('''
      SELECT id, title, filename FROM documents
      WHERE lower(title) LIKE ? OR lower(filename) LIKE ?
      ORDER BY COALESCE(last_opened_at, updated_at) DESC
      LIMIT ?;
    ''', [like, like, limit]);
    for (final row in documentRows) {
      hits.add(LocalSearchHit(
        kind: 'document',
        title: row['title'] as String,
        snippet: row['filename'] as String,
        documentId: row['id'] as String,
      ));
    }

    final textRows = db.database.select('''
      SELECT i.document_id, i.page_number, i.content, d.title
      FROM pdf_page_text_index i
      JOIN documents d ON d.id = i.document_id
      WHERE lower(i.content) LIKE ?
      ORDER BY d.title, i.page_number
      LIMIT ?;
    ''', [like, limit]);
    for (final row in textRows) {
      hits.add(LocalSearchHit(
        kind: 'pdf_text',
        title: row['title'] as String,
        snippet: _snippet(row['content'] as String, normalized),
        documentId: row['document_id'] as String,
        pageNumber: row['page_number'] as int,
      ));
    }

    final annotationRows = db.database.select('''
      SELECT a.document_id, a.page_number,
             COALESCE(a.selected_text, '') AS text_value,
             d.title
      FROM annotations a
      JOIN documents d ON d.id = a.document_id
      WHERE lower(COALESCE(a.selected_text, '')) LIKE ?
      UNION ALL
      SELECT o.document_id, o.page_number,
             COALESCE(o.text_value, '') AS text_value,
             d.title
      FROM pdf_annotation_objects o
      JOIN documents d ON d.id = o.document_id
      WHERE lower(COALESCE(o.text_value, '')) LIKE ?
      LIMIT ?;
    ''', [like, like, limit]);
    for (final row in annotationRows) {
      hits.add(LocalSearchHit(
        kind: 'annotation',
        title: row['title'] as String,
        snippet: row['text_value'] as String,
        documentId: row['document_id'] as String,
        pageNumber: row['page_number'] as int,
      ));
    }

    final notebookRows = db.database.select('''
      SELECT n.id AS notebook_id, n.title, n.title AS text_value, NULL AS page_number
      FROM notebooks n
      WHERE lower(n.title) LIKE ?
      UNION ALL
      SELECT p.notebook_id, n.title,
             COALESCE(o.text_value, '') AS text_value,
             p.page_number
      FROM notebook_objects o
      JOIN notebook_pages p ON p.id = o.page_id
      JOIN notebooks n ON n.id = p.notebook_id
      WHERE lower(COALESCE(o.text_value, '')) LIKE ?
      LIMIT ?;
    ''', [like, like, limit]);
    for (final row in notebookRows) {
      hits.add(LocalSearchHit(
        kind: 'notebook',
        title: row['title'] as String,
        snippet: row['text_value'] as String,
        notebookId: row['notebook_id'] as String,
        pageNumber: row['page_number'] as int?,
      ));
    }

    if (hits.length > limit) return hits.take(limit).toList(growable: false);
    return hits;
  }

  Future<List<String>> listTags(String documentId) async {
    final rows = db.database.select(
      'SELECT tag FROM document_tags WHERE document_id = ? ORDER BY tag;',
      [documentId],
    );
    return rows.map((row) => row['tag'] as String).toList(growable: false);
  }

  Future<void> addTag(String documentId, String tag) async {
    final value = tag.trim();
    if (value.isEmpty) return;
    db.database.execute(
      'INSERT OR IGNORE INTO document_tags(document_id, tag) VALUES (?, ?);',
      [documentId, value],
    );
  }

  Future<void> removeTag(String documentId, String tag) async {
    db.database.execute(
      'DELETE FROM document_tags WHERE document_id = ? AND tag = ?;',
      [documentId, tag],
    );
  }

  static String _snippet(String content, String query) {
    final lower = content.toLowerCase();
    final index = lower.indexOf(query);
    if (index < 0) return content.length <= 180 ? content : '${content.substring(0, 180)}…';
    final start = (index - 70).clamp(0, content.length);
    final end = (index + query.length + 90).clamp(0, content.length);
    final prefix = start > 0 ? '…' : '';
    final suffix = end < content.length ? '…' : '';
    return '$prefix${content.substring(start, end)}$suffix';
  }
}

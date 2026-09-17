import 'local_database.dart';
import 'local_pdf_navigation_store.dart';

class LocalGlobalSearchFts {
  LocalGlobalSearchFts(this.db) {
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

  final LocalDatabase db;

  Future<void> rebuild() async {
    final sourceSignature = _nonPdfSourceSignature();
    final pdfSignature = _pdfTextSignature();
    db.database.execute('BEGIN IMMEDIATE;');
    try {
      db.database.execute('DELETE FROM global_search_fts;');

      db.database.execute('''
        INSERT INTO global_search_fts(kind, owner_id, page_number, title, content)
        SELECT
          'document',
          d.id,
          NULL,
          d.title,
          trim(
            d.filename || ' ' ||
            COALESCE((
              SELECT group_concat(t.tag, ' ')
              FROM document_tags t
              WHERE t.document_id = d.id
            ), '')
          )
        FROM documents d;
      ''');

      _insertAllPdfTextRows();

      db.database.execute('''
        INSERT INTO global_search_fts(kind, owner_id, page_number, title, content)
        SELECT 'annotation', a.document_id, a.page_number, d.title,
               COALESCE(a.selected_text, '')
        FROM annotations a
        JOIN documents d ON d.id = a.document_id
        WHERE trim(COALESCE(a.selected_text, '')) <> '';
      ''');

      db.database.execute('''
        INSERT INTO global_search_fts(kind, owner_id, page_number, title, content)
        SELECT 'annotation', o.document_id, o.page_number, d.title,
               COALESCE(o.text_value, '')
        FROM pdf_annotation_objects o
        JOIN documents d ON d.id = o.document_id
        WHERE trim(COALESCE(o.text_value, '')) <> '';
      ''');

      db.database.execute('''
        INSERT INTO global_search_fts(kind, owner_id, page_number, title, content)
        SELECT 'notebook', n.id, NULL, n.title, n.title
        FROM notebooks n;
      ''');

      db.database.execute('''
        INSERT INTO global_search_fts(kind, owner_id, page_number, title, content)
        SELECT 'notebook', p.notebook_id, p.page_number, n.title,
               COALESCE(o.text_value, '')
        FROM notebook_objects o
        JOIN notebook_pages p ON p.id = o.page_id
        JOIN notebooks n ON n.id = p.notebook_id
        WHERE trim(COALESCE(o.text_value, '')) <> '';
      ''');

      _writeMetadata('global_search_fts_signature', sourceSignature);
      _writeMetadata('global_search_fts_pdf_signature', pdfSignature);
      db.database.execute('COMMIT;');
    } catch (_) {
      db.database.execute('ROLLBACK;');
      rethrow;
    }
  }

  Future<void> rebuildIfNeeded() async {
    final currentSource = _nonPdfSourceSignature();
    final indexedSource = _readMetadata('global_search_fts_signature');
    if (indexedSource != currentSource) {
      await rebuild();
      return;
    }

    final currentPdf = _pdfTextSignature();
    final indexedPdf = _readMetadata('global_search_fts_pdf_signature');
    if (indexedPdf != currentPdf) {
      await syncPdfTextOnly();
    }
  }

  /// Re-synchronizes only PDF page text without destroying unrelated FTS rows.
  /// This is used as a repair path for legacy/manual indexers. The OCR pipeline
  /// normally calls [upsertPdfPage] and updates one FTS row at a time.
  Future<void> syncPdfTextOnly() async {
    db.database.execute("DELETE FROM global_search_fts WHERE kind = 'pdf_text';");
    _insertAllPdfTextRows();
    _writeMetadata('global_search_fts_pdf_signature', _pdfTextSignature());
  }

  /// Incrementally updates a single PDF page in FTS5 after its durable page-text
  /// row has been written. This keeps background OCR searchable immediately.
  Future<void> upsertPdfPage({
    required String documentId,
    required int pageNumber,
    required String content,
  }) async {
    if (pageNumber < 1) return;
    db.database.execute('''
      DELETE FROM global_search_fts
      WHERE kind = 'pdf_text' AND owner_id = ? AND page_number = ?;
    ''', [documentId, pageNumber]);
    if (content.trim().isNotEmpty) {
      db.database.execute('''
        INSERT INTO global_search_fts(kind, owner_id, page_number, title, content)
        SELECT 'pdf_text', d.id, ?, d.title, ?
        FROM documents d
        WHERE d.id = ?;
      ''', [pageNumber, content, documentId]);
    }
    _writeMetadata('global_search_fts_pdf_signature', _pdfTextSignature());
  }

  void _insertAllPdfTextRows() {
    db.database.execute('''
      INSERT INTO global_search_fts(kind, owner_id, page_number, title, content)
      SELECT 'pdf_text', i.document_id, i.page_number, d.title, i.content
      FROM pdf_page_text_index i
      JOIN documents d ON d.id = i.document_id
      WHERE trim(i.content) <> '';
    ''');
  }

  String _nonPdfSourceSignature() {
    final row = db.database.select('''
      SELECT
        (SELECT COUNT(*) FROM documents) AS documents_count,
        COALESCE((SELECT MAX(updated_at) FROM documents), '') AS documents_max,
        (SELECT COUNT(*) FROM annotations) AS annotations_count,
        COALESCE((SELECT MAX(updated_at) FROM annotations), '') AS annotations_max,
        (SELECT COUNT(*) FROM pdf_annotation_objects) AS objects_count,
        COALESCE((SELECT MAX(updated_at) FROM pdf_annotation_objects), '') AS objects_max,
        (SELECT COUNT(*) FROM notebooks) AS notebooks_count,
        COALESCE((SELECT MAX(updated_at) FROM notebooks), '') AS notebooks_max,
        (SELECT COUNT(*) FROM notebook_objects) AS notebook_objects_count,
        COALESCE((SELECT MAX(updated_at) FROM notebook_objects), '') AS notebook_objects_max,
        (SELECT COUNT(*) FROM document_tags) AS tags_count;
    ''').single;
    return [
      row['documents_count'],
      row['documents_max'],
      row['annotations_count'],
      row['annotations_max'],
      row['objects_count'],
      row['objects_max'],
      row['notebooks_count'],
      row['notebooks_max'],
      row['notebook_objects_count'],
      row['notebook_objects_max'],
      row['tags_count'],
    ].join('|');
  }

  String _pdfTextSignature() {
    final row = db.database.select('''
      SELECT
        COUNT(*) AS text_count,
        COALESCE(MAX(indexed_at), '') AS text_max
      FROM pdf_page_text_index;
    ''').single;
    return '${row['text_count']}|${row['text_max']}';
  }

  String? _readMetadata(String key) {
    final rows = db.database.select(
      'SELECT value FROM app_metadata WHERE key = ? LIMIT 1;',
      [key],
    );
    return rows.isEmpty ? null : rows.first['value']?.toString();
  }

  void _writeMetadata(String key, String value) {
    db.database.execute('''
      INSERT INTO app_metadata(key, value) VALUES (?, ?)
      ON CONFLICT(key) DO UPDATE SET value = excluded.value;
    ''', [key, value]);
  }

  Future<List<LocalSearchHit>> search(String query, {int limit = 100}) async {
    final normalized = query.trim();
    if (normalized.isEmpty) return const [];
    await rebuildIfNeeded();
    final match = _toMatchExpression(normalized);
    if (match.isEmpty) return const [];

    final rows = db.database.select('''
      SELECT
        kind,
        owner_id,
        page_number,
        title,
        snippet(global_search_fts, 4, '‹', '›', '…', 24) AS snippet_text,
        bm25(global_search_fts, 2.0, 1.0) AS rank
      FROM global_search_fts
      WHERE global_search_fts MATCH ?
      ORDER BY rank
      LIMIT ?;
    ''', [match, limit]);

    return rows.map((row) {
      final kind = row['kind'] as String;
      final ownerId = row['owner_id'] as String;
      final rawPage = row['page_number'];
      final pageNumber = rawPage == null
          ? null
          : rawPage is int
              ? rawPage
              : int.tryParse(rawPage.toString());
      return LocalSearchHit(
        kind: kind,
        title: row['title'] as String,
        snippet: row['snippet_text'] as String? ?? '',
        documentId: kind == 'notebook' ? null : ownerId,
        notebookId: kind == 'notebook' ? ownerId : null,
        pageNumber: pageNumber,
      );
    }).toList(growable: false);
  }

  static String _toMatchExpression(String query) {
    final tokens = query
        .split(RegExp(r'\s+'))
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .map((value) => '"${value.replaceAll('"', '""')}"*')
        .toList(growable: false);
    return tokens.join(' AND ');
  }
}

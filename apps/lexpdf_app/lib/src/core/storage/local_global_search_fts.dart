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

      db.database.execute('''
        INSERT INTO global_search_fts(kind, owner_id, page_number, title, content)
        SELECT 'pdf_text', i.document_id, i.page_number, d.title, i.content
        FROM pdf_page_text_index i
        JOIN documents d ON d.id = i.document_id
        WHERE trim(i.content) <> '';
      ''');

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

      db.database.execute('COMMIT;');
    } catch (_) {
      db.database.execute('ROLLBACK;');
      rethrow;
    }
  }

  Future<List<LocalSearchHit>> search(String query, {int limit = 100}) async {
    final normalized = query.trim();
    if (normalized.isEmpty) return const [];
    await rebuild();
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

import 'dart:convert';
import 'dart:math' as math;

import 'local_database.dart';

class SemanticIndexStatus {
  const SemanticIndexStatus({
    required this.sourcePages,
    required this.indexedPages,
  });

  final int sourcePages;
  final int indexedPages;

  int get pendingPages => math.max(0, sourcePages - indexedPages);
}

class SemanticPageSource {
  const SemanticPageSource({
    required this.documentId,
    required this.documentTitle,
    required this.pageNumber,
    required this.content,
    required this.sourceIndexedAt,
  });

  final String documentId;
  final String documentTitle;
  final int pageNumber;
  final String content;
  final String sourceIndexedAt;
}

class SemanticLibraryHit {
  const SemanticLibraryHit({
    required this.documentId,
    required this.documentTitle,
    required this.pageNumber,
    required this.content,
    required this.score,
  });

  final String documentId;
  final String documentTitle;
  final int pageNumber;
  final String content;
  final double score;
}

class LocalSemanticLibraryStore {
  LocalSemanticLibraryStore(this.db) {
    _ensureTables();
  }

  final LocalDatabase db;

  void _ensureTables() {
    db.database.execute('''
      CREATE TABLE IF NOT EXISTS semantic_page_embeddings (
        document_id TEXT NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
        page_number INTEGER NOT NULL CHECK(page_number >= 1),
        source_indexed_at TEXT NOT NULL,
        model TEXT NOT NULL,
        dimensions INTEGER NOT NULL CHECK(dimensions > 0),
        embedding_json TEXT NOT NULL,
        indexed_at TEXT NOT NULL,
        PRIMARY KEY(document_id, page_number)
      );
    ''');
    db.database.execute('''
      CREATE INDEX IF NOT EXISTS semantic_page_embeddings_model_idx
      ON semantic_page_embeddings(model);
    ''');
  }

  Future<SemanticIndexStatus> status() async {
    final source = db.database.select('''
      SELECT COUNT(*) AS c
      FROM pdf_page_text_index
      WHERE trim(content) <> '';
    ''').single['c'] as int? ?? 0;
    final indexed = db.database.select('''
      SELECT COUNT(*) AS c
      FROM semantic_page_embeddings e
      JOIN pdf_page_text_index i
        ON i.document_id = e.document_id
       AND i.page_number = e.page_number
       AND i.indexed_at = e.source_indexed_at
      WHERE trim(i.content) <> '';
    ''').single['c'] as int? ?? 0;
    return SemanticIndexStatus(sourcePages: source, indexedPages: indexed);
  }

  Future<List<SemanticPageSource>> pagesNeedingIndex({
    required String model,
    int limit = 100000,
  }) async {
    final rows = db.database.select('''
      SELECT i.document_id, i.page_number, i.content, i.indexed_at, d.title
      FROM pdf_page_text_index i
      JOIN documents d ON d.id = i.document_id
      WHERE trim(i.content) <> ''
        AND NOT EXISTS (
          SELECT 1
          FROM semantic_page_embeddings e
          WHERE e.document_id = i.document_id
            AND e.page_number = i.page_number
            AND e.source_indexed_at = i.indexed_at
            AND e.model = ?
        )
      ORDER BY d.title, i.page_number
      LIMIT ?;
    ''', [model, limit]);
    return rows
        .map(
          (row) => SemanticPageSource(
            documentId: row['document_id'] as String,
            documentTitle: row['title'] as String,
            pageNumber: row['page_number'] as int,
            content: row['content'] as String,
            sourceIndexedAt: row['indexed_at'] as String,
          ),
        )
        .toList(growable: false);
  }

  Future<void> saveEmbeddings({
    required List<SemanticPageSource> pages,
    required List<List<double>> vectors,
    required String model,
  }) async {
    if (pages.length != vectors.length) {
      throw ArgumentError('Each semantic page must have exactly one vector.');
    }
    if (pages.isEmpty) return;
    final now = DateTime.now().toUtc().toIso8601String();
    db.database.execute('BEGIN IMMEDIATE;');
    try {
      for (var index = 0; index < pages.length; index++) {
        final vector = vectors[index];
        if (vector.isEmpty) {
          throw ArgumentError('Embedding vectors cannot be empty.');
        }
        final page = pages[index];
        db.database.execute('''
          INSERT INTO semantic_page_embeddings(
            document_id, page_number, source_indexed_at, model,
            dimensions, embedding_json, indexed_at
          ) VALUES (?, ?, ?, ?, ?, ?, ?)
          ON CONFLICT(document_id, page_number) DO UPDATE SET
            source_indexed_at = excluded.source_indexed_at,
            model = excluded.model,
            dimensions = excluded.dimensions,
            embedding_json = excluded.embedding_json,
            indexed_at = excluded.indexed_at;
        ''', [
          page.documentId,
          page.pageNumber,
          page.sourceIndexedAt,
          model,
          vector.length,
          jsonEncode(vector),
          now,
        ]);
      }
      db.database.execute('COMMIT;');
    } catch (_) {
      db.database.execute('ROLLBACK;');
      rethrow;
    }
  }

  Future<List<SemanticLibraryHit>> search({
    required List<double> queryVector,
    required String model,
    int limit = 8,
  }) async {
    if (queryVector.isEmpty || limit < 1) return const [];
    final rows = db.database.select('''
      SELECT e.embedding_json, e.dimensions,
             i.document_id, i.page_number, i.content, d.title
      FROM semantic_page_embeddings e
      JOIN pdf_page_text_index i
        ON i.document_id = e.document_id
       AND i.page_number = e.page_number
       AND i.indexed_at = e.source_indexed_at
      JOIN documents d ON d.id = i.document_id
      WHERE e.model = ?
        AND e.dimensions = ?
        AND trim(i.content) <> '';
    ''', [model, queryVector.length]);

    final hits = <SemanticLibraryHit>[];
    for (final row in rows) {
      final raw = jsonDecode(row['embedding_json'] as String) as List<dynamic>;
      final vector = raw.map((value) => (value as num).toDouble()).toList();
      final score = _cosine(queryVector, vector);
      hits.add(
        SemanticLibraryHit(
          documentId: row['document_id'] as String,
          documentTitle: row['title'] as String,
          pageNumber: row['page_number'] as int,
          content: row['content'] as String,
          score: score,
        ),
      );
    }
    hits.sort((a, b) => b.score.compareTo(a.score));
    return hits.take(limit).toList(growable: false);
  }

  static String ragExcerpt(
    String content,
    String query, {
    int maxCharacters = 3200,
  }) {
    final clean = content.trim();
    if (clean.length <= maxCharacters) return clean;

    final terms = query
        .toLowerCase()
        .split(RegExp(r'[^\p{L}\p{N}]+', unicode: true))
        .where((term) => term.length >= 4)
        .toList(growable: false);
    final lower = clean.toLowerCase();
    var anchor = -1;
    for (final term in terms) {
      final found = lower.indexOf(term);
      if (found >= 0 && (anchor < 0 || found < anchor)) anchor = found;
    }
    if (anchor < 0) return '${clean.substring(0, maxCharacters)}…';

    final start = (anchor - maxCharacters ~/ 3).clamp(0, clean.length);
    final end = (start + maxCharacters).clamp(0, clean.length);
    final prefix = start > 0 ? '…' : '';
    final suffix = end < clean.length ? '…' : '';
    return '$prefix${clean.substring(start, end)}$suffix';
  }

  static double _cosine(List<double> a, List<double> b) {
    if (a.length != b.length || a.isEmpty) return -1;
    var dot = 0.0;
    var normA = 0.0;
    var normB = 0.0;
    for (var index = 0; index < a.length; index++) {
      dot += a[index] * b[index];
      normA += a[index] * a[index];
      normB += b[index] * b[index];
    }
    if (normA == 0 || normB == 0) return -1;
    return dot / (math.sqrt(normA) * math.sqrt(normB));
  }
}

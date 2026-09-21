import 'dart:convert';
import 'dart:math' as math;

import 'local_database.dart';
import 'local_global_search_fts.dart';
import 'local_vector_lsh_index.dart';

class HybridRagIndexStatus {
  const HybridRagIndexStatus({
    required this.sourcePages,
    required this.indexedPages,
    required this.indexedChunks,
  });

  final int sourcePages;
  final int indexedPages;
  final int indexedChunks;
}

class HybridRagChunkSource {
  const HybridRagChunkSource({
    required this.documentId,
    required this.documentTitle,
    required this.pageNumber,
    required this.chunkIndex,
    required this.content,
    required this.sourceIndexedAt,
  });

  final String documentId;
  final String documentTitle;
  final int pageNumber;
  final int chunkIndex;
  final String content;
  final String sourceIndexedAt;

  String get key => '$documentId:$pageNumber:$chunkIndex';
}

class HybridRagHit {
  const HybridRagHit({
    required this.documentId,
    required this.documentTitle,
    required this.pageNumber,
    required this.chunkIndex,
    required this.content,
    required this.semanticScore,
    required this.lexicalScore,
    required this.rerankScore,
    this.sourceKind = 'pdf',
    this.sourceId,
    this.pdfDocumentId,
    this.locationLabel,
  });

  final String documentId;
  final String documentTitle;
  final int pageNumber;
  final int chunkIndex;
  final String content;
  final double semanticScore;
  final double lexicalScore;
  final double rerankScore;
  final String sourceKind;
  final String? sourceId;
  final String? pdfDocumentId;
  final String? locationLabel;

  bool get canOpenPdf => pdfDocumentId?.trim().isNotEmpty == true;

  String get key =>
      '$sourceKind:${sourceId ?? documentId}:$pageNumber:$chunkIndex';
}

class LocalHybridRagStore {
  LocalHybridRagStore(this.db) : _vectorIndex = LocalVectorLshIndex(db) {
    _ensureTables();
  }

  final LocalDatabase db;
  final LocalVectorLshIndex _vectorIndex;

  static const int targetChunkCharacters = 1100;
  static const int maxChunkCharacters = 1650;
  static const int overlapCharacters = 160;

  static const _stopWords = <String>{
    'a',
    'ao',
    'aos',
    'as',
    'com',
    'como',
    'da',
    'das',
    'de',
    'do',
    'dos',
    'e',
    'em',
    'entre',
    'esta',
    'este',
    'isso',
    'mais',
    'na',
    'nas',
    'no',
    'nos',
    'o',
    'os',
    'ou',
    'para',
    'pela',
    'pelo',
    'por',
    'qual',
    'quais',
    'que',
    'se',
    'sem',
    'sobre',
    'um',
    'uma',
  };

  void _ensureTables() {
    db.database.execute('''
      CREATE TABLE IF NOT EXISTS hybrid_rag_chunks (
        document_id TEXT NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
        page_number INTEGER NOT NULL CHECK(page_number >= 1),
        chunk_index INTEGER NOT NULL CHECK(chunk_index >= 0),
        source_indexed_at TEXT NOT NULL,
        content TEXT NOT NULL,
        model TEXT NOT NULL,
        dimensions INTEGER NOT NULL CHECK(dimensions > 0),
        embedding_json TEXT NOT NULL,
        indexed_at TEXT NOT NULL,
        PRIMARY KEY(document_id, page_number, chunk_index)
      );
    ''');
    db.database.execute('''
      CREATE INDEX IF NOT EXISTS hybrid_rag_chunks_model_idx
      ON hybrid_rag_chunks(model, dimensions);
    ''');
    db.database.execute('''
      CREATE INDEX IF NOT EXISTS hybrid_rag_chunks_source_idx
      ON hybrid_rag_chunks(document_id, page_number, source_indexed_at);
    ''');
  }

  Future<HybridRagIndexStatus> status() async {
    final sourcePages = db.database.select('''
      SELECT COUNT(*) AS c
      FROM pdf_page_text_index
      WHERE trim(content) <> '';
    ''').single['c'] as int? ?? 0;

    final indexedPages = db.database.select('''
      SELECT COUNT(DISTINCT e.document_id || ':' || e.page_number) AS c
      FROM hybrid_rag_chunks e
      JOIN pdf_page_text_index i
        ON i.document_id = e.document_id
       AND i.page_number = e.page_number
       AND i.indexed_at = e.source_indexed_at
      WHERE trim(i.content) <> '';
    ''').single['c'] as int? ?? 0;

    final indexedChunks = db.database.select('''
      SELECT COUNT(*) AS c
      FROM hybrid_rag_chunks e
      JOIN pdf_page_text_index i
        ON i.document_id = e.document_id
       AND i.page_number = e.page_number
       AND i.indexed_at = e.source_indexed_at
      WHERE trim(i.content) <> '';
    ''').single['c'] as int? ?? 0;

    return HybridRagIndexStatus(
      sourcePages: sourcePages,
      indexedPages: indexedPages,
      indexedChunks: indexedChunks,
    );
  }

  Future<List<HybridRagChunkSource>> chunksNeedingIndex({
    required String model,
    String? documentId,
    int limit = 100000,
  }) async {
    final whereDocument = documentId == null ? '' : 'AND i.document_id = ?';
    final args = <Object?>[if (documentId != null) documentId];
    final pages = db.database.select('''
      SELECT i.document_id, i.page_number, i.content, i.indexed_at, d.title
      FROM pdf_page_text_index i
      JOIN documents d ON d.id = i.document_id
      WHERE trim(i.content) <> ''
      $whereDocument
      ORDER BY d.title, i.page_number;
    ''', args);

    final pending = <HybridRagChunkSource>[];
    for (final page in pages) {
      final docId = page['document_id'] as String;
      final pageNumber = page['page_number'] as int;
      final sourceIndexedAt = page['indexed_at'] as String;
      final title = page['title'] as String;
      final chunks = chunkPage(page['content'] as String);
      if (chunks.isEmpty) continue;

      final existingRows = db.database.select('''
        SELECT chunk_index, source_indexed_at, model, content
        FROM hybrid_rag_chunks
        WHERE document_id = ? AND page_number = ?;
      ''', [docId, pageNumber]);
      final existing = <int, dynamic>{
        for (final row in existingRows) row['chunk_index'] as int: row,
      };

      for (var index = 0; index < chunks.length; index++) {
        final current = existing[index];
        final fresh = current != null &&
            current['source_indexed_at'] == sourceIndexedAt &&
            current['model'] == model &&
            current['content'] == chunks[index];
        if (fresh) continue;
        pending.add(
          HybridRagChunkSource(
            documentId: docId,
            documentTitle: title,
            pageNumber: pageNumber,
            chunkIndex: index,
            content: chunks[index],
            sourceIndexedAt: sourceIndexedAt,
          ),
        );
        if (pending.length >= limit) return pending;
      }
    }
    return pending;
  }

  Future<void> saveEmbeddings({
    required List<HybridRagChunkSource> chunks,
    required List<List<double>> vectors,
    required String model,
  }) async {
    if (chunks.length != vectors.length) {
      throw ArgumentError('Each RAG chunk must have exactly one vector.');
    }
    if (chunks.isEmpty) return;
    final now = DateTime.now().toUtc().toIso8601String();
    db.database.execute('BEGIN IMMEDIATE;');
    try {
      for (var index = 0; index < chunks.length; index++) {
        final vector = vectors[index];
        if (vector.isEmpty) {
          throw ArgumentError('Embedding vectors cannot be empty.');
        }
        final chunk = chunks[index];
        db.database.execute('''
          INSERT INTO hybrid_rag_chunks(
            document_id, page_number, chunk_index, source_indexed_at,
            content, model, dimensions, embedding_json, indexed_at
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
          ON CONFLICT(document_id, page_number, chunk_index) DO UPDATE SET
            source_indexed_at = excluded.source_indexed_at,
            content = excluded.content,
            model = excluded.model,
            dimensions = excluded.dimensions,
            embedding_json = excluded.embedding_json,
            indexed_at = excluded.indexed_at;
        ''', [
          chunk.documentId,
          chunk.pageNumber,
          chunk.chunkIndex,
          chunk.sourceIndexedAt,
          chunk.content,
          model,
          vector.length,
          jsonEncode(vector),
          now,
        ]);
        _vectorIndex.upsert(
          namespace: 'pdf',
          sourceKey: chunk.key,
          model: model,
          vector: vector,
        );
      }
      db.database.execute('COMMIT;');
    } catch (_) {
      db.database.execute('ROLLBACK;');
      rethrow;
    }
  }

  Future<List<HybridRagHit>> searchHybrid({
    required String query,
    required List<double> queryVector,
    required String model,
    String? documentId,
    int limit = 8,
  }) async {
    if (query.trim().isEmpty || queryVector.isEmpty || limit < 1) {
      return const [];
    }

    await LocalGlobalSearchFts(db).rebuildIfNeeded();
    final semanticKeys = _vectorIndex.candidateKeys(
      namespace: 'pdf',
      model: model,
      queryVector: queryVector,
      maxResults: 96,
    );
    final semanticRows = _validChunkRows(
      model: model,
      dimensions: queryVector.length,
      documentId: documentId,
      candidateKeys: semanticKeys,
    );

    final lexicalRanks = _lexicalPageRanks(
      query,
      documentId: documentId,
      limit: 40,
    );
    final lexicalRows = _rowsForPages(
      lexicalRanks.keys,
      model: model,
      dimensions: queryVector.length,
      documentId: documentId,
    );

    final semantic = <String, _HybridCandidate>{};
    for (final row in semanticRows) {
      final vector = _decodeVector(row['embedding_json'] as String);
      if (vector.length != queryVector.length) continue;
      final candidate = _candidateFromRow(
        row,
        semanticScore: _cosine(queryVector, vector),
      );
      semantic[candidate.key] = candidate;
    }

    final semanticRanked = semantic.values.toList()
      ..sort((a, b) => b.semanticScore.compareTo(a.semanticScore));
    final topSemantic = semanticRanked.take(60).toList(growable: false);

    final candidates = <String, _HybridCandidate>{
      for (final candidate in topSemantic) candidate.key: candidate,
    };

    for (final row in lexicalRows) {
      final key = _chunkKey(
        row['document_id'] as String,
        row['page_number'] as int,
        row['chunk_index'] as int,
      );
      candidates.putIfAbsent(
        key,
        () {
          final vector = _decodeVector(row['embedding_json'] as String);
          return _candidateFromRow(
            row,
            semanticScore: vector.length == queryVector.length
                ? _cosine(queryVector, vector)
                : -1,
          );
        },
      );
    }

    if (candidates.isEmpty) return const [];

    final terms = _queryTerms(query);
    final reranked = <HybridRagHit>[];
    for (final candidate in candidates.values) {
      final overlap = _lexicalOverlap(candidate.content, terms);
      final pageRank = lexicalRanks[
          _pageKey(candidate.documentId, candidate.pageNumber)];
      final ftsBoost = pageRank == null ? 0.0 : 1 / (1 + pageRank);
      final semanticNorm =
          ((candidate.semanticScore.clamp(-1.0, 1.0) + 1) / 2).toDouble();
      final lexicalScore = (overlap * 0.72 + ftsBoost * 0.28)
          .clamp(0.0, 1.0)
          .toDouble();
      final rerankScore =
          (semanticNorm * 0.62 + lexicalScore * 0.38).toDouble();
      reranked.add(
        HybridRagHit(
          documentId: candidate.documentId,
          documentTitle: candidate.documentTitle,
          pageNumber: candidate.pageNumber,
          chunkIndex: candidate.chunkIndex,
          content: candidate.content,
          semanticScore: candidate.semanticScore,
          lexicalScore: lexicalScore,
          rerankScore: rerankScore,
          pdfDocumentId: candidate.documentId,
        ),
      );
    }

    reranked.sort((a, b) => b.rerankScore.compareTo(a.rerankScore));
    final selected = <HybridRagHit>[];
    final perPage = <String, int>{};
    final perDocument = <String, int>{};
    for (final hit in reranked) {
      final pageKey = _pageKey(hit.documentId, hit.pageNumber);
      if ((perPage[pageKey] ?? 0) >= 2) continue;
      if (documentId == null && (perDocument[hit.documentId] ?? 0) >= 3) {
        continue;
      }
      selected.add(hit);
      perPage[pageKey] = (perPage[pageKey] ?? 0) + 1;
      perDocument[hit.documentId] =
          (perDocument[hit.documentId] ?? 0) + 1;
      if (selected.length >= limit) break;
    }
    return selected;
  }

  List<dynamic> _validChunkRows({
    required String model,
    required int dimensions,
    String? documentId,
    List<String>? candidateKeys,
  }) {
    if (candidateKeys == null) {
      final whereDocument =
          documentId == null ? '' : 'AND e.document_id = ?';
      final args = <Object?>[
        model,
        dimensions,
        if (documentId != null) documentId,
      ];
      return db.database.select('''
        SELECT e.embedding_json, e.chunk_index, e.content,
               e.document_id, e.page_number, d.title
        FROM hybrid_rag_chunks e
        JOIN pdf_page_text_index i
          ON i.document_id = e.document_id
         AND i.page_number = e.page_number
         AND i.indexed_at = e.source_indexed_at
        JOIN documents d ON d.id = e.document_id
        WHERE e.model = ?
          AND e.dimensions = ?
          $whereDocument
          AND trim(e.content) <> '';
      ''', args);
    }

    final rows = <dynamic>[];
    for (final key in candidateKeys) {
      final parsed = _parseChunkKey(key);
      if (parsed == null) continue;
      if (documentId != null && parsed.documentId != documentId) continue;
      rows.addAll(db.database.select('''
        SELECT e.embedding_json, e.chunk_index, e.content,
               e.document_id, e.page_number, d.title
        FROM hybrid_rag_chunks e
        JOIN pdf_page_text_index i
          ON i.document_id = e.document_id
         AND i.page_number = e.page_number
         AND i.indexed_at = e.source_indexed_at
        JOIN documents d ON d.id = e.document_id
        WHERE e.model = ? AND e.dimensions = ?
          AND e.document_id = ? AND e.page_number = ? AND e.chunk_index = ?
          AND trim(e.content) <> ''
        LIMIT 1;
      ''', [
        model,
        dimensions,
        parsed.documentId,
        parsed.pageNumber,
        parsed.chunkIndex,
      ]));
    }
    return rows;
  }

  List<dynamic> _rowsForPages(
    Iterable<String> pageKeys, {
    required String model,
    required int dimensions,
    String? documentId,
  }) {
    final rows = <dynamic>[];
    for (final key in pageKeys) {
      final split = key.lastIndexOf(':');
      if (split <= 0 || split >= key.length - 1) continue;
      final docId = key.substring(0, split);
      final page = int.tryParse(key.substring(split + 1));
      if (page == null || (documentId != null && docId != documentId)) {
        continue;
      }
      rows.addAll(db.database.select('''
        SELECT e.embedding_json, e.chunk_index, e.content,
               e.document_id, e.page_number, d.title
        FROM hybrid_rag_chunks e
        JOIN pdf_page_text_index i
          ON i.document_id = e.document_id
         AND i.page_number = e.page_number
         AND i.indexed_at = e.source_indexed_at
        JOIN documents d ON d.id = e.document_id
        WHERE e.model = ? AND e.dimensions = ?
          AND e.document_id = ? AND e.page_number = ?
          AND trim(e.content) <> '';
      ''', [model, dimensions, docId, page]));
    }
    return rows;
  }

  static ({String documentId, int pageNumber, int chunkIndex})?
      _parseChunkKey(String key) {
    final last = key.lastIndexOf(':');
    if (last <= 0 || last >= key.length - 1) return null;
    final previous = key.lastIndexOf(':', last - 1);
    if (previous <= 0 || previous >= last - 1) return null;
    final page = int.tryParse(key.substring(previous + 1, last));
    final chunk = int.tryParse(key.substring(last + 1));
    if (page == null || chunk == null) return null;
    return (
      documentId: key.substring(0, previous),
      pageNumber: page,
      chunkIndex: chunk,
    );
  }

  Map<String, int> _lexicalPageRanks(
    String query, {
    String? documentId,
    int limit = 40,
  }) {
    final terms = _queryTerms(query).take(12).toList(growable: false);
    if (terms.isEmpty) return const {};
    final expression = terms
        .map((term) => '"${term.replaceAll('"', '""')}"*')
        .join(' OR ');
    final whereDocument =
        documentId == null ? '' : 'AND owner_id = ?';
    final args = <Object?>[
      expression,
      if (documentId != null) documentId,
      limit,
    ];
    final rows = db.database.select('''
      SELECT owner_id, page_number,
             bm25(global_search_fts, 2.0, 1.0) AS rank
      FROM global_search_fts
      WHERE global_search_fts MATCH ?
        AND kind = 'pdf_text'
        $whereDocument
      ORDER BY rank
      LIMIT ?;
    ''', args);
    return {
      for (var index = 0; index < rows.length; index++)
        _pageKey(
          rows[index]['owner_id'] as String,
          int.tryParse(rows[index]['page_number'].toString()) ?? 1,
        ): index,
    };
  }

  static List<String> chunkPage(String source) {
    final text = source
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .trim();
    if (text.isEmpty) return const [];
    if (text.length <= maxChunkCharacters) return [text];

    final units = _semanticUnits(text);
    final result = <String>[];
    var current = '';

    void flush() {
      final clean = current.trim();
      if (clean.isEmpty) return;
      result.add(clean);
      final overlapStart =
          math.max(0, clean.length - overlapCharacters).toInt();
      var overlap = clean.substring(overlapStart);
      final space = overlap.indexOf(' ');
      if (space >= 0 && space < overlap.length - 1) {
        overlap = overlap.substring(space + 1);
      }
      current = overlap.trim();
    }

    for (final unit in units) {
      if (unit.length > maxChunkCharacters) {
        final words = unit.split(RegExp(r'\s+'));
        for (final word in words) {
          if (current.isNotEmpty &&
              current.length + word.length + 1 > targetChunkCharacters) {
            flush();
          }
          current = current.isEmpty ? word : '$current $word';
        }
        continue;
      }

      if (current.isNotEmpty &&
          current.length + unit.length + 1 > targetChunkCharacters) {
        flush();
      }
      current = current.isEmpty ? unit : '$current $unit';
      if (current.length >= maxChunkCharacters) flush();
    }
    flush();
    return result
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
  }

  static List<String> _semanticUnits(String text) {
    final result = <String>[];
    final buffer = StringBuffer();
    for (var index = 0; index < text.length; index++) {
      final char = text[index];
      buffer.write(char);
      final boundary = char == '\n' ||
          char == '.' ||
          char == '!' ||
          char == '?' ||
          char == ';' ||
          char == ':';
      if (!boundary) continue;
      final value = buffer.toString().trim();
      if (value.length >= 180 || char == '\n') {
        if (value.isNotEmpty) result.add(value);
        buffer.clear();
      }
    }
    final tail = buffer.toString().trim();
    if (tail.isNotEmpty) result.add(tail);
    return result;
  }

  static List<String> _queryTerms(String query) {
    return query
        .toLowerCase()
        .split(RegExp(r'[^\p{L}\p{N}]+', unicode: true))
        .map((term) => term.trim())
        .where((term) => term.length >= 3 && !_stopWords.contains(term))
        .toSet()
        .toList(growable: false);
  }

  static double _lexicalOverlap(String content, List<String> terms) {
    if (terms.isEmpty) return 0;
    final lower = content.toLowerCase();
    var matched = 0;
    for (final term in terms) {
      if (lower.contains(term)) matched++;
    }
    return matched / terms.length;
  }

  static List<double> _decodeVector(String value) {
    final raw = jsonDecode(value) as List<dynamic>;
    return raw.map((entry) => (entry as num).toDouble()).toList();
  }

  static _HybridCandidate _candidateFromRow(
    dynamic row, {
    required double semanticScore,
  }) =>
      _HybridCandidate(
        documentId: row['document_id'] as String,
        documentTitle: row['title'] as String,
        pageNumber: row['page_number'] as int,
        chunkIndex: row['chunk_index'] as int,
        content: row['content'] as String,
        semanticScore: semanticScore,
      );

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

  static String ragExcerpt(
    String content,
    String query, {
    int maxCharacters = 1400,
  }) {
    final clean = content.trim();
    if (clean.length <= maxCharacters) return clean;
    final terms = _queryTerms(query);
    final lower = clean.toLowerCase();
    var anchor = -1;
    for (final term in terms) {
      final found = lower.indexOf(term);
      if (found >= 0 && (anchor < 0 || found < anchor)) anchor = found;
    }
    if (anchor < 0) return '${clean.substring(0, maxCharacters)}…';
    final start =
        math.max(0, anchor - maxCharacters ~/ 3).toInt();
    final end = math.min(clean.length, start + maxCharacters).toInt();
    return '${start > 0 ? '…' : ''}'
        '${clean.substring(start, end)}'
        '${end < clean.length ? '…' : ''}';
  }

  static String _pageKey(String documentId, int pageNumber) =>
      '$documentId:$pageNumber';

  static String _chunkKey(
    String documentId,
    int pageNumber,
    int chunkIndex,
  ) =>
      '$documentId:$pageNumber:$chunkIndex';
}

class _HybridCandidate {
  const _HybridCandidate({
    required this.documentId,
    required this.documentTitle,
    required this.pageNumber,
    required this.chunkIndex,
    required this.content,
    required this.semanticScore,
  });

  final String documentId;
  final String documentTitle;
  final int pageNumber;
  final int chunkIndex;
  final String content;
  final double semanticScore;

  String get key => '$documentId:$pageNumber:$chunkIndex';
}

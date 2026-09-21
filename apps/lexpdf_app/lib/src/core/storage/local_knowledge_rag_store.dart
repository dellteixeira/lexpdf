import 'dart:convert';
import 'dart:math' as math;

import 'local_database.dart';
import 'local_hybrid_rag_store.dart';
import 'local_vector_lsh_index.dart';

class KnowledgeRagChunkSource {
  const KnowledgeRagChunkSource({
    required this.sourceKind,
    required this.sourceId,
    required this.ownerId,
    required this.ownerTitle,
    required this.pageNumber,
    required this.content,
    required this.sourceUpdatedAt,
    this.pdfDocumentId,
    this.locationLabel,
  });

  final String sourceKind;
  final String sourceId;
  final String ownerId;
  final String ownerTitle;
  final int pageNumber;
  final String content;
  final String sourceUpdatedAt;
  final String? pdfDocumentId;
  final String? locationLabel;
}

class LocalKnowledgeRagStore {
  LocalKnowledgeRagStore(this.db) : _vectorIndex = LocalVectorLshIndex(db) {
    _ensureTables();
  }

  final LocalDatabase db;
  final LocalVectorLshIndex _vectorIndex;

  void _ensureTables() {
    db.database.execute('''
      CREATE TABLE IF NOT EXISTS knowledge_rag_embeddings (
        source_kind TEXT NOT NULL,
        source_id TEXT NOT NULL,
        owner_id TEXT NOT NULL,
        owner_title TEXT NOT NULL,
        page_number INTEGER NOT NULL DEFAULT 1,
        pdf_document_id TEXT,
        location_label TEXT,
        source_updated_at TEXT NOT NULL,
        content TEXT NOT NULL,
        model TEXT NOT NULL,
        dimensions INTEGER NOT NULL CHECK(dimensions > 0),
        embedding_json TEXT NOT NULL,
        indexed_at TEXT NOT NULL,
        PRIMARY KEY(source_kind, source_id)
      );
    ''');
    db.database.execute('''
      CREATE INDEX IF NOT EXISTS knowledge_rag_embeddings_model_idx
      ON knowledge_rag_embeddings(model, dimensions);
    ''');
    db.database.execute('''
      CREATE TABLE IF NOT EXISTS ai_visual_descriptions (
        id TEXT PRIMARY KEY,
        source_kind TEXT NOT NULL,
        owner_id TEXT NOT NULL,
        owner_title TEXT NOT NULL,
        page_number INTEGER NOT NULL DEFAULT 1,
        pdf_document_id TEXT,
        image_path TEXT,
        description TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      );
    ''');
  }

  Future<void> upsertVisualDescription({
    required String id,
    required String sourceKind,
    required String ownerId,
    required String ownerTitle,
    required int pageNumber,
    required String description,
    String? pdfDocumentId,
    String? imagePath,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    db.database.execute('''
      INSERT INTO ai_visual_descriptions(
        id, source_kind, owner_id, owner_title, page_number,
        pdf_document_id, image_path, description, created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        source_kind = excluded.source_kind,
        owner_id = excluded.owner_id,
        owner_title = excluded.owner_title,
        page_number = excluded.page_number,
        pdf_document_id = excluded.pdf_document_id,
        image_path = excluded.image_path,
        description = excluded.description,
        updated_at = excluded.updated_at;
    ''', [
      id, sourceKind, ownerId, ownerTitle, pageNumber,
      pdfDocumentId, imagePath, description.trim(), now, now,
    ]);
  }

  Future<List<KnowledgeRagChunkSource>> sourcesNeedingIndex({
    required String model,
    String? documentId,
    int limit = 100000,
  }) async {
    final sources = _collectSources(documentId: documentId);
    final result = <KnowledgeRagChunkSource>[];
    for (final source in sources) {
      final rows = db.database.select('''
        SELECT source_updated_at, content, model
        FROM knowledge_rag_embeddings
        WHERE source_kind = ? AND source_id = ? LIMIT 1;
      ''', [source.sourceKind, source.sourceId]);
      final fresh = rows.isNotEmpty &&
          rows.first['source_updated_at'] == source.sourceUpdatedAt &&
          rows.first['content'] == source.content &&
          rows.first['model'] == model;
      if (!fresh) result.add(source);
      if (result.length >= limit) break;
    }
    return result;
  }

  Future<void> saveEmbeddings({
    required List<KnowledgeRagChunkSource> sources,
    required List<List<double>> vectors,
    required String model,
  }) async {
    if (sources.length != vectors.length) {
      throw ArgumentError('Each knowledge source must have one embedding.');
    }
    if (sources.isEmpty) return;
    final now = DateTime.now().toUtc().toIso8601String();
    db.database.execute('BEGIN IMMEDIATE;');
    try {
      for (var index = 0; index < sources.length; index++) {
        final vector = vectors[index];
        if (vector.isEmpty) throw ArgumentError('Embedding cannot be empty.');
        final source = sources[index];
        db.database.execute('''
          INSERT INTO knowledge_rag_embeddings(
            source_kind, source_id, owner_id, owner_title, page_number,
            pdf_document_id, location_label, source_updated_at, content,
            model, dimensions, embedding_json, indexed_at
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          ON CONFLICT(source_kind, source_id) DO UPDATE SET
            owner_id = excluded.owner_id,
            owner_title = excluded.owner_title,
            page_number = excluded.page_number,
            pdf_document_id = excluded.pdf_document_id,
            location_label = excluded.location_label,
            source_updated_at = excluded.source_updated_at,
            content = excluded.content,
            model = excluded.model,
            dimensions = excluded.dimensions,
            embedding_json = excluded.embedding_json,
            indexed_at = excluded.indexed_at;
        ''', [
          source.sourceKind, source.sourceId, source.ownerId, source.ownerTitle,
          source.pageNumber, source.pdfDocumentId, source.locationLabel,
          source.sourceUpdatedAt, source.content, model, vector.length,
          jsonEncode(vector), now,
        ]);
        _vectorIndex.upsert(
          namespace: 'knowledge',
          sourceKey: '§{source.sourceKind}:§{source.sourceId}',
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

  Future<List<HybridRagHit>> search({
    required String query,
    required List<double> queryVector,
    required String model,
    String? documentId,
    int limit = 12,
  }) async {
    if (queryVector.isEmpty || query.trim().isEmpty) return const [];
    final candidateKeys = _vectorIndex.candidateKeys(
      namespace: 'knowledge',
      model: model,
      queryVector: queryVector,
      maxResults: 120,
    );
    final rows = candidateKeys == null
        ? _allSearchRows(
            model: model,
            dimensions: queryVector.length,
            documentId: documentId,
          )
        : _candidateSearchRows(
            candidateKeys,
            model: model,
            dimensions: queryVector.length,
            documentId: documentId,
          );

    final terms = _queryTerms(query);
    final hits = <HybridRagHit>[];
    for (final row in rows) {
      final vector = (jsonDecode(row['embedding_json'] as String) as List)
          .map((value) => (value as num).toDouble()).toList(growable: false);
      if (vector.length != queryVector.length) continue;
      final semantic = _cosine(queryVector, vector);
      final semanticNorm = ((semantic.clamp(-1.0, 1.0) + 1) / 2).toDouble();
      final content = row['content'] as String;
      final lexical = _lexicalOverlap(content, terms);
      final score = semanticNorm * 0.68 + lexical * 0.32;
      hits.add(HybridRagHit(
        documentId: row['owner_id'] as String,
        documentTitle: row['owner_title'] as String,
        pageNumber: row['page_number'] as int? ?? 1,
        chunkIndex: 0,
        content: content,
        semanticScore: semantic,
        lexicalScore: lexical,
        rerankScore: score,
        sourceKind: row['source_kind'] as String,
        sourceId: row['source_id'] as String,
        pdfDocumentId: row['pdf_document_id'] as String?,
        locationLabel: row['location_label'] as String?,
      ));
    }
    hits.sort((a, b) => b.rerankScore.compareTo(a.rerankScore));
    return hits.take(limit).toList(growable: false);
  }

  List<dynamic> _allSearchRows({
    required String model,
    required int dimensions,
    String? documentId,
  }) {
    final whereDocument =
        documentId == null ? '' : 'AND pdf_document_id = ?';
    return db.database.select('''
      SELECT * FROM knowledge_rag_embeddings
      WHERE model = ? AND dimensions = ? $whereDocument;
    ''', [model, dimensions, if (documentId != null) documentId]);
  }

  List<dynamic> _candidateSearchRows(
    List<String> keys, {
    required String model,
    required int dimensions,
    String? documentId,
  }) {
    final rows = <dynamic>[];
    for (final key in keys) {
      final split = key.indexOf(':');
      if (split <= 0 || split >= key.length - 1) continue;
      final kind = key.substring(0, split);
      final sourceId = key.substring(split + 1);
      final found = db.database.select('''
        SELECT * FROM knowledge_rag_embeddings
        WHERE model = ? AND dimensions = ?
          AND source_kind = ? AND source_id = ?
        LIMIT 1;
      ''', [model, dimensions, kind, sourceId]);
      if (found.isEmpty) continue;
      final row = found.first;
      if (documentId != null && row['pdf_document_id'] != documentId) {
        continue;
      }
      rows.add(row);
    }
    return rows;
  }

  List<KnowledgeRagChunkSource> _collectSources({String? documentId}) {
    final result = <KnowledgeRagChunkSource>[];
    final annotationWhere =
        documentId == null ? '' : 'AND a.document_id = ?';
    final annotationRows = db.database.select('''
      SELECT a.id, a.document_id, a.page_number, a.selected_text,
             a.updated_at, d.title
      FROM annotations a JOIN documents d ON d.id = a.document_id
      WHERE trim(COALESCE(a.selected_text, '')) <> '' $annotationWhere;
    ''', [if (documentId != null) documentId]);
    for (final row in annotationRows) {
      result.add(KnowledgeRagChunkSource(
        sourceKind: 'pdf_annotation',
        sourceId: 'text:${row['id']}',
        ownerId: row['document_id'] as String,
        ownerTitle: 'Anotação — ${row['title']}',
        pageNumber: row['page_number'] as int,
        content: (row['selected_text'] as String).trim(),
        sourceUpdatedAt: row['updated_at'] as String,
        pdfDocumentId: row['document_id'] as String,
        locationLabel: 'Anotação na página ${row['page_number']}',
      ));
    }

    final objectWhere =
        documentId == null ? '' : 'AND o.document_id = ?';
    final objectRows = db.database.select('''
      SELECT o.id, o.document_id, o.page_number, o.text_value,
             o.updated_at, d.title
      FROM pdf_annotation_objects o JOIN documents d ON d.id = o.document_id
      WHERE trim(COALESCE(o.text_value, '')) <> '' $objectWhere;
    ''', [if (documentId != null) documentId]);
    for (final row in objectRows) {
      result.add(KnowledgeRagChunkSource(
        sourceKind: 'pdf_note',
        sourceId: 'object:${row['id']}',
        ownerId: row['document_id'] as String,
        ownerTitle: 'Nota — ${row['title']}',
        pageNumber: row['page_number'] as int,
        content: (row['text_value'] as String).trim(),
        sourceUpdatedAt: row['updated_at'] as String,
        pdfDocumentId: row['document_id'] as String,
        locationLabel: 'Nota na página ${row['page_number']}',
      ));
    }

    if (documentId == null) {
      final richRows = db.database.select('''
        SELECT pd.page_id, pd.document_json, pd.updated_at,
               p.page_number, n.id AS notebook_id, n.title
        FROM notebook_page_documents pd
        JOIN notebook_pages p ON p.id = pd.page_id
        JOIN notebooks n ON n.id = p.notebook_id
        ORDER BY n.title, p.page_number;
      ''');
      for (final row in richRows) {
        final text = _extractDocumentText(row['document_json'] as String);
        final chunks = LocalHybridRagStore.chunkPage(text);
        for (var index = 0; index < chunks.length; index++) {
          result.add(KnowledgeRagChunkSource(
            sourceKind: 'notebook',
            sourceId: 'rich:${row['page_id']}:$index',
            ownerId: row['notebook_id'] as String,
            ownerTitle: 'Caderno — ${row['title']}',
            pageNumber: row['page_number'] as int,
            content: chunks[index],
            sourceUpdatedAt: row['updated_at'] as String,
            locationLabel: 'Caderno, página ${row['page_number']}',
          ));
        }
      }
      final textObjects = db.database.select('''
        SELECT o.id, o.text_value, o.updated_at,
               p.page_number, n.id AS notebook_id, n.title
        FROM notebook_objects o
        JOIN notebook_pages p ON p.id = o.page_id
        JOIN notebooks n ON n.id = p.notebook_id
        WHERE o.type = 'text' AND trim(COALESCE(o.text_value, '')) <> '';
      ''');
      for (final row in textObjects) {
        result.add(KnowledgeRagChunkSource(
          sourceKind: 'notebook_object',
          sourceId: 'text:${row['id']}',
          ownerId: row['notebook_id'] as String,
          ownerTitle: 'Caderno — ${row['title']}',
          pageNumber: row['page_number'] as int,
          content: (row['text_value'] as String).trim(),
          sourceUpdatedAt: row['updated_at'] as String,
          locationLabel: 'Objeto de texto, página ${row['page_number']}',
        ));
      }
    }

    final visualWhere =
        documentId == null ? '' : 'AND pdf_document_id = ?';
    final visualRows = db.database.select('''
      SELECT * FROM ai_visual_descriptions
      WHERE trim(description) <> '' $visualWhere;
    ''', [if (documentId != null) documentId]);
    for (final row in visualRows) {
      result.add(KnowledgeRagChunkSource(
        sourceKind: row['source_kind'] as String,
        sourceId: 'visual:${row['id']}',
        ownerId: row['owner_id'] as String,
        ownerTitle: row['owner_title'] as String,
        pageNumber: row['page_number'] as int? ?? 1,
        content: row['description'] as String,
        sourceUpdatedAt: row['updated_at'] as String,
        pdfDocumentId: row['pdf_document_id'] as String?,
        locationLabel: 'Descrição visual, página ${row['page_number']}',
      ));
    }
    return result;
  }

  static String _extractDocumentText(String jsonValue) {
    try {
      final decoded = jsonDecode(jsonValue);
      final buffer = StringBuffer();
      void walk(Object? value) {
        if (value is Map) {
          for (final entry in value.entries) {
            if (entry.key.toString() == 'text' && entry.value is String) {
              final text = (entry.value as String).trim();
              if (text.isNotEmpty) buffer.writeln(text);
            } else {
              walk(entry.value);
            }
          }
        } else if (value is List) {
          for (final item in value) walk(item);
        }
      }
      walk(decoded);
      return buffer.toString().trim();
    } catch (_) {
      return '';
    }
  }

  static List<String> _queryTerms(String query) => query.toLowerCase()
      .split(RegExp(r'[^\p{L}\p{N}]+', unicode: true))
      .where((term) => term.length >= 3).toSet().toList(growable: false);

  static double _lexicalOverlap(String content, List<String> terms) {
    if (terms.isEmpty) return 0;
    final lower = content.toLowerCase();
    var matched = 0;
    for (final term in terms) {
      if (lower.contains(term)) matched++;
    }
    return matched / terms.length;
  }

  static double _cosine(List<double> a, List<double> b) {
    if (a.length != b.length || a.isEmpty) return -1;
    var dot = 0.0;
    var a2 = 0.0;
    var b2 = 0.0;
    for (var i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      a2 += a[i] * a[i];
      b2 += b[i] * b[i];
    }
    if (a2 == 0 || b2 == 0) return -1;
    return dot / (math.sqrt(a2) * math.sqrt(b2));
  }
}

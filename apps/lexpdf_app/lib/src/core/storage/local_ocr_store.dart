import 'dart:convert';

import 'local_database.dart';

class OcrTextLine {
  const OcrTextLine({
    required this.text,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  final String text;
  final double x;
  final double y;
  final double width;
  final double height;

  Map<String, dynamic> toJson() => {
        'text': text,
        'x': x,
        'y': y,
        'width': width,
        'height': height,
      };

  static OcrTextLine fromJson(Map<String, dynamic> json) => OcrTextLine(
        text: json['text'] as String? ?? '',
        x: (json['x'] as num?)?.toDouble() ?? 0,
        y: (json['y'] as num?)?.toDouble() ?? 0,
        width: (json['width'] as num?)?.toDouble() ?? 0,
        height: (json['height'] as num?)?.toDouble() ?? 0,
      );
}

class OcrPageResult {
  const OcrPageResult({
    required this.documentId,
    required this.pageNumber,
    required this.text,
    required this.engine,
    required this.processedAt,
    this.lines = const [],
  });

  final String documentId;
  final int pageNumber;
  final String text;
  final String engine;
  final DateTime processedAt;
  final List<OcrTextLine> lines;
}

class LocalOcrStore {
  LocalOcrStore(this.db) {
    db.database.execute('''
      CREATE TABLE IF NOT EXISTS ocr_page_results (
        document_id TEXT NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
        page_number INTEGER NOT NULL CHECK(page_number >= 1),
        text TEXT NOT NULL,
        engine TEXT NOT NULL,
        processed_at TEXT NOT NULL,
        layout_json TEXT NOT NULL DEFAULT '[]',
        PRIMARY KEY(document_id, page_number)
      );
    ''');
    final columns = db.database
        .select('PRAGMA table_info(ocr_page_results);')
        .map((row) => row['name'] as String)
        .toSet();
    if (!columns.contains('layout_json')) {
      db.database.execute(
        "ALTER TABLE ocr_page_results ADD COLUMN layout_json TEXT NOT NULL DEFAULT '[]';",
      );
    }
    db.database.execute('''
      CREATE INDEX IF NOT EXISTS ocr_page_results_document_idx
      ON ocr_page_results(document_id, page_number);
    ''');
  }

  final LocalDatabase db;

  Future<void> upsert(OcrPageResult result) async {
    if (result.pageNumber < 1) {
      throw ArgumentError.value(result.pageNumber, 'pageNumber', 'Must be >= 1');
    }
    db.database.execute('''
      INSERT INTO ocr_page_results(
        document_id, page_number, text, engine, processed_at, layout_json
      ) VALUES (?, ?, ?, ?, ?, ?)
      ON CONFLICT(document_id, page_number) DO UPDATE SET
        text = excluded.text,
        engine = excluded.engine,
        processed_at = excluded.processed_at,
        layout_json = excluded.layout_json;
    ''', [
      result.documentId,
      result.pageNumber,
      result.text,
      result.engine,
      result.processedAt.toUtc().toIso8601String(),
      jsonEncode(result.lines.map((line) => line.toJson()).toList(growable: false)),
    ]);
  }

  Future<List<OcrPageResult>> listForDocument(String documentId) async {
    final rows = db.database.select('''
      SELECT * FROM ocr_page_results
      WHERE document_id = ? ORDER BY page_number;
    ''', [documentId]);
    return rows.map(_fromRow).toList(growable: false);
  }

  /// Returns only tiny resume metadata instead of hydrating OCR text/layout for
  /// thousands of pages. The bool indicates whether the stored page has text.
  Future<Map<int, bool>> processedPageState(
    String documentId, {
    required Set<String> acceptedEngines,
  }) async {
    if (acceptedEngines.isEmpty) return const <int, bool>{};
    final placeholders = List.filled(acceptedEngines.length, '?').join(', ');
    final rows = db.database.select('''
      SELECT page_number, length(trim(text)) AS has_text
      FROM ocr_page_results
      WHERE document_id = ? AND engine IN ($placeholders)
      ORDER BY page_number;
    ''', [documentId, ...acceptedEngines]);
    return {
      for (final row in rows)
        row['page_number'] as int: ((row['has_text'] as int?) ?? 0) > 0,
    };
  }

  Future<OcrPageResult?> getPage(String documentId, int pageNumber) async {
    final rows = db.database.select('''
      SELECT * FROM ocr_page_results
      WHERE document_id = ? AND page_number = ? LIMIT 1;
    ''', [documentId, pageNumber]);
    return rows.isEmpty ? null : _fromRow(rows.first);
  }

  OcrPageResult _fromRow(dynamic row) {
    List<OcrTextLine> lines = const [];
    try {
      final decoded = jsonDecode(row['layout_json'] as String? ?? '[]');
      if (decoded is List) {
        lines = decoded
            .whereType<Map>()
            .map(
              (value) => OcrTextLine.fromJson(
                value.map((key, value) => MapEntry(key.toString(), value)),
              ),
            )
            .toList(growable: false);
      }
    } catch (_) {
      lines = const [];
    }
    return OcrPageResult(
      documentId: row['document_id'] as String,
      pageNumber: row['page_number'] as int,
      text: row['text'] as String,
      engine: row['engine'] as String,
      processedAt: DateTime.parse(row['processed_at'] as String),
      lines: lines,
    );
  }

  Future<void> clearDocument(String documentId) async {
    db.database.execute(
      'DELETE FROM ocr_page_results WHERE document_id = ?;',
      [documentId],
    );
  }
}

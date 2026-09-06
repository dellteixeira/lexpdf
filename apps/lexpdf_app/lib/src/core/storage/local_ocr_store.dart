import 'local_database.dart';

class OcrPageResult {
  const OcrPageResult({
    required this.documentId,
    required this.pageNumber,
    required this.text,
    required this.engine,
    required this.processedAt,
  });

  final String documentId;
  final int pageNumber;
  final String text;
  final String engine;
  final DateTime processedAt;
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
        PRIMARY KEY(document_id, page_number)
      );
    ''');
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
      INSERT INTO ocr_page_results(document_id, page_number, text, engine, processed_at)
      VALUES (?, ?, ?, ?, ?)
      ON CONFLICT(document_id, page_number) DO UPDATE SET
        text = excluded.text,
        engine = excluded.engine,
        processed_at = excluded.processed_at;
    ''', [
      result.documentId,
      result.pageNumber,
      result.text,
      result.engine,
      result.processedAt.toUtc().toIso8601String(),
    ]);
  }

  Future<List<OcrPageResult>> listForDocument(String documentId) async {
    final rows = db.database.select('''
      SELECT * FROM ocr_page_results
      WHERE document_id = ? ORDER BY page_number;
    ''', [documentId]);
    return rows
        .map(
          (row) => OcrPageResult(
            documentId: row['document_id'] as String,
            pageNumber: row['page_number'] as int,
            text: row['text'] as String,
            engine: row['engine'] as String,
            processedAt: DateTime.parse(row['processed_at'] as String),
          ),
        )
        .toList(growable: false);
  }

  Future<void> clearDocument(String documentId) async {
    db.database.execute(
      'DELETE FROM ocr_page_results WHERE document_id = ?;',
      [documentId],
    );
  }
}

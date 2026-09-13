import 'local_database.dart';

class NotebookPageDocumentRecord {
  const NotebookPageDocumentRecord({
    required this.pageId,
    required this.documentJson,
    required this.migratedLegacyText,
    required this.createdAt,
    required this.updatedAt,
  });

  final String pageId;
  final String documentJson;
  final bool migratedLegacyText;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class LocalNotebookDocumentStore {
  const LocalNotebookDocumentStore(this.db);

  final LocalDatabase db;

  Future<NotebookPageDocumentRecord?> read(String pageId) async {
    final rows = db.database.select(
      'SELECT * FROM notebook_page_documents WHERE page_id = ? LIMIT 1;',
      [pageId],
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    return NotebookPageDocumentRecord(
      pageId: row['page_id'] as String,
      documentJson: row['document_json'] as String,
      migratedLegacyText: (row['migrated_legacy_text'] as int? ?? 0) != 0,
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }

  Future<void> upsert({
    required String pageId,
    required String documentJson,
    required bool migratedLegacyText,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    db.database.execute(
      '''
      INSERT INTO notebook_page_documents(
        page_id, document_json, migrated_legacy_text, created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?)
      ON CONFLICT(page_id) DO UPDATE SET
        document_json = excluded.document_json,
        migrated_legacy_text = excluded.migrated_legacy_text,
        updated_at = excluded.updated_at;
      ''',
      [pageId, documentJson, migratedLegacyText ? 1 : 0, now, now],
    );
  }

  Future<void> copyPageDocument(
    String sourcePageId,
    String targetPageId,
  ) async {
    final source = await read(sourcePageId);
    if (source == null) return;
    await upsert(
      pageId: targetPageId,
      documentJson: source.documentJson,
      migratedLegacyText: source.migratedLegacyText,
    );
  }

  Future<void> delete(String pageId) async {
    db.database.execute(
      'DELETE FROM notebook_page_documents WHERE page_id = ?;',
      [pageId],
    );
  }
}

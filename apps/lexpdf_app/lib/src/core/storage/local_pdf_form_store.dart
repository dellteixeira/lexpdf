import 'dart:convert';

import 'local_database.dart';

class LocalPdfFormStore {
  LocalPdfFormStore(this.db) {
    db.database.execute('''
      CREATE TABLE IF NOT EXISTS pdf_form_values (
        document_id TEXT NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
        field_name TEXT NOT NULL,
        value_json TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        PRIMARY KEY(document_id, field_name)
      );
    ''');
    db.database.execute('''
      CREATE INDEX IF NOT EXISTS pdf_form_values_document_idx
      ON pdf_form_values(document_id, updated_at DESC);
    ''');
  }

  final LocalDatabase db;

  Future<Map<String, dynamic>> load(String documentId) async {
    final rows = db.database.select(
      'SELECT field_name, value_json FROM pdf_form_values WHERE document_id = ?;',
      [documentId],
    );
    final result = <String, dynamic>{};
    for (final row in rows) {
      result[row['field_name'] as String] = jsonDecode(row['value_json'] as String);
    }
    return result;
  }

  Future<void> setValue({
    required String documentId,
    required String fieldName,
    required dynamic value,
  }) async {
    final name = fieldName.trim();
    if (name.isEmpty) throw ArgumentError('fieldName cannot be empty');
    db.database.execute('''
      INSERT INTO pdf_form_values(document_id, field_name, value_json, updated_at)
      VALUES (?, ?, ?, ?)
      ON CONFLICT(document_id, field_name) DO UPDATE SET
        value_json = excluded.value_json,
        updated_at = excluded.updated_at;
    ''', [
      documentId,
      name,
      jsonEncode(value),
      DateTime.now().toUtc().toIso8601String(),
    ]);
  }

  Future<void> replaceAll({
    required String documentId,
    required Map<String, dynamic> values,
  }) async {
    db.database.execute('BEGIN IMMEDIATE;');
    try {
      db.database.execute(
        'DELETE FROM pdf_form_values WHERE document_id = ?;',
        [documentId],
      );
      final now = DateTime.now().toUtc().toIso8601String();
      for (final entry in values.entries) {
        if (entry.key.trim().isEmpty) continue;
        db.database.execute('''
          INSERT INTO pdf_form_values(document_id, field_name, value_json, updated_at)
          VALUES (?, ?, ?, ?);
        ''', [documentId, entry.key, jsonEncode(entry.value), now]);
      }
      db.database.execute('COMMIT;');
    } catch (_) {
      db.database.execute('ROLLBACK;');
      rethrow;
    }
  }

  Future<void> clear(String documentId) async {
    db.database.execute(
      'DELETE FROM pdf_form_values WHERE document_id = ?;',
      [documentId],
    );
  }
}

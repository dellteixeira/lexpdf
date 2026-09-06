import '../annotations/saved_signature.dart';
import 'local_database.dart';

class LocalSignatureStore {
  const LocalSignatureStore(this.db);

  final LocalDatabase db;

  Future<List<SavedSignature>> listAll() async {
    final rows = db.database.select('''
      SELECT * FROM saved_signatures
      ORDER BY updated_at DESC, created_at DESC;
    ''');
    return rows.map(_fromRow).toList(growable: false);
  }

  Future<SavedSignature?> getById(String id) async {
    final rows = db.database.select(
      'SELECT * FROM saved_signatures WHERE id = ? LIMIT 1;',
      [id],
    );
    if (rows.isEmpty) return null;
    return _fromRow(rows.first);
  }

  Future<void> upsert(SavedSignature signature) async {
    signature.validate();
    db.database.execute('''
      INSERT INTO saved_signatures(
        id, name, strokes_json, color_value, stroke_width, created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        name = excluded.name,
        strokes_json = excluded.strokes_json,
        color_value = excluded.color_value,
        stroke_width = excluded.stroke_width,
        updated_at = excluded.updated_at;
    ''', [
      signature.id,
      signature.name.trim(),
      signature.strokesJson,
      signature.colorValue,
      signature.strokeWidth,
      signature.createdAt.toUtc().toIso8601String(),
      signature.updatedAt.toUtc().toIso8601String(),
    ]);
  }

  Future<void> delete(String id) async {
    db.database.execute('DELETE FROM saved_signatures WHERE id = ?;', [id]);
  }

  SavedSignature _fromRow(dynamic row) => SavedSignature(
        id: row['id'] as String,
        name: row['name'] as String,
        strokes: SavedSignature.decodeStrokes(row['strokes_json'] as String),
        colorValue: row['color_value'] as int,
        strokeWidth: (row['stroke_width'] as num).toDouble(),
        createdAt: DateTime.parse(row['created_at'] as String),
        updatedAt: DateTime.parse(row['updated_at'] as String),
      );
}

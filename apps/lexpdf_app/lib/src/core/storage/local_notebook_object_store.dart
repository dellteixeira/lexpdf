import '../notebook/notebook_object_models.dart';
import 'local_database.dart';

class LocalNotebookObjectStore {
  const LocalNotebookObjectStore(this.db);

  final LocalDatabase db;

  Future<List<NotebookObject>> listObjects(String pageId) async {
    final rows = db.database.select(
      'SELECT * FROM notebook_objects WHERE page_id = ? ORDER BY created_at ASC;',
      [pageId],
    );
    return rows.map(_fromRow).toList(growable: false);
  }

  Future<void> upsert(NotebookObject object) async {
    db.database.execute('''
      INSERT OR REPLACE INTO notebook_objects(
        id, page_id, type, x, y, width, height, rotation, color_value,
        fill_color_value, stroke_width, text_value, font_size, image_path,
        created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
    ''', [
      object.id,
      object.pageId,
      object.type.dbValue,
      object.x,
      object.y,
      object.width,
      object.height,
      object.rotation,
      object.colorValue,
      object.fillColorValue,
      object.strokeWidth,
      object.textValue,
      object.fontSize,
      object.imagePath,
      object.createdAt.toUtc().toIso8601String(),
      object.updatedAt.toUtc().toIso8601String(),
    ]);
  }

  Future<void> delete(String id) async {
    db.database.execute('DELETE FROM notebook_objects WHERE id = ?;', [id]);
  }

  Future<void> clearPage(String pageId) async {
    db.database.execute('DELETE FROM notebook_objects WHERE page_id = ?;', [pageId]);
  }

  NotebookObject _fromRow(dynamic row) => NotebookObject(
        id: row['id'] as String,
        pageId: row['page_id'] as String,
        type: NotebookObjectType.fromDb(row['type'] as String),
        x: (row['x'] as num).toDouble(),
        y: (row['y'] as num).toDouble(),
        width: (row['width'] as num).toDouble(),
        height: (row['height'] as num).toDouble(),
        rotation: (row['rotation'] as num).toDouble(),
        colorValue: row['color_value'] as int,
        fillColorValue: row['fill_color_value'] as int?,
        strokeWidth: (row['stroke_width'] as num).toDouble(),
        textValue: row['text_value'] as String?,
        fontSize: (row['font_size'] as num?)?.toDouble(),
        imagePath: row['image_path'] as String?,
        createdAt: DateTime.parse(row['created_at'] as String),
        updatedAt: DateTime.parse(row['updated_at'] as String),
      );
}

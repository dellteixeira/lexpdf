import '../annotations/pdf_annotation_object.dart';
import 'local_database.dart';

class LocalPdfAnnotationObjectStore {
  const LocalPdfAnnotationObjectStore(this.db);

  final LocalDatabase db;

  Future<List<PdfAnnotationObject>> listForDocument(String documentId) async {
    final rows = db.database.select('''
      SELECT * FROM pdf_annotation_objects
      WHERE document_id = ?
      ORDER BY page_number, created_at;
    ''', [documentId]);
    return rows.map(_fromRow).toList(growable: false);
  }

  Future<List<PdfAnnotationObject>> listForPage(
    String documentId,
    int pageNumber,
  ) async {
    final rows = db.database.select('''
      SELECT * FROM pdf_annotation_objects
      WHERE document_id = ? AND page_number = ?
      ORDER BY created_at;
    ''', [documentId, pageNumber]);
    return rows.map(_fromRow).toList(growable: false);
  }

  Future<void> upsert(PdfAnnotationObject object) async {
    object.validate();
    db.database.execute('''
      INSERT INTO pdf_annotation_objects(
        id, document_id, page_number, type,
        x, y, width, height, rotation,
        color_value, fill_color_value, opacity, stroke_width,
        text_value, created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        page_number = excluded.page_number,
        type = excluded.type,
        x = excluded.x,
        y = excluded.y,
        width = excluded.width,
        height = excluded.height,
        rotation = excluded.rotation,
        color_value = excluded.color_value,
        fill_color_value = excluded.fill_color_value,
        opacity = excluded.opacity,
        stroke_width = excluded.stroke_width,
        text_value = excluded.text_value,
        updated_at = excluded.updated_at;
    ''', [
      object.id,
      object.documentId,
      object.pageNumber,
      PdfAnnotationObject.typeToDb(object.type),
      object.x,
      object.y,
      object.width,
      object.height,
      object.rotation,
      object.colorValue,
      object.fillColorValue,
      object.opacity,
      object.strokeWidth,
      object.textValue,
      object.createdAt.toUtc().toIso8601String(),
      object.updatedAt.toUtc().toIso8601String(),
    ]);
  }

  Future<void> delete(String id) async {
    db.database.execute('DELETE FROM pdf_annotation_objects WHERE id = ?;', [id]);
  }

  Future<void> deleteForDocument(String documentId) async {
    db.database.execute(
      'DELETE FROM pdf_annotation_objects WHERE document_id = ?;',
      [documentId],
    );
  }

  PdfAnnotationObject _fromRow(dynamic row) => PdfAnnotationObject(
        id: row['id'] as String,
        documentId: row['document_id'] as String,
        pageNumber: row['page_number'] as int,
        type: PdfAnnotationObject.typeFromDb(row['type'] as String),
        x: (row['x'] as num).toDouble(),
        y: (row['y'] as num).toDouble(),
        width: (row['width'] as num).toDouble(),
        height: (row['height'] as num).toDouble(),
        rotation: (row['rotation'] as num).toDouble(),
        colorValue: row['color_value'] as int,
        fillColorValue: row['fill_color_value'] as int?,
        opacity: (row['opacity'] as num).toDouble(),
        strokeWidth: (row['stroke_width'] as num).toDouble(),
        textValue: row['text_value'] as String?,
        createdAt: DateTime.parse(row['created_at'] as String),
        updatedAt: DateTime.parse(row['updated_at'] as String),
      );
}

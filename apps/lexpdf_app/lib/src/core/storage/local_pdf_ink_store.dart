import '../ink/ink_models.dart';
import '../ink/pdf_ink_models.dart';
import 'local_database.dart';

class LocalPdfInkStore {
  const LocalPdfInkStore(this.db);

  final LocalDatabase db;

  Future<void> addStroke(PdfInkStroke stroke) async {
    db.database.execute('''
      INSERT OR REPLACE INTO pdf_ink_strokes(
        id, document_id, page_number, tool, color_value,
        opacity, width, points_json, created_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
    ''', [
      stroke.id,
      stroke.documentId,
      stroke.pageNumber,
      _toolToDb(stroke.tool),
      stroke.colorValue,
      stroke.opacity,
      stroke.width,
      stroke.encodePoints(),
      stroke.createdAt.toUtc().toIso8601String(),
    ]);
  }

  Future<List<PdfInkStroke>> listForDocument(String documentId) async {
    final rows = db.database.select('''
      SELECT * FROM pdf_ink_strokes
      WHERE document_id = ?
      ORDER BY page_number ASC, created_at ASC;
    ''', [documentId]);
    return rows.map(_fromRow).toList(growable: false);
  }

  Future<List<PdfInkStroke>> listForPage(
    String documentId,
    int pageNumber,
  ) async {
    final rows = db.database.select('''
      SELECT * FROM pdf_ink_strokes
      WHERE document_id = ? AND page_number = ?
      ORDER BY created_at ASC;
    ''', [documentId, pageNumber]);
    return rows.map(_fromRow).toList(growable: false);
  }

  Future<void> deleteStroke(String id) async {
    db.database.execute('DELETE FROM pdf_ink_strokes WHERE id = ?;', [id]);
  }

  Future<void> clearPage(String documentId, int pageNumber) async {
    db.database.execute(
      'DELETE FROM pdf_ink_strokes WHERE document_id = ? AND page_number = ?;',
      [documentId, pageNumber],
    );
  }

  PdfInkStroke _fromRow(dynamic row) => PdfInkStroke(
        id: row['id'] as String,
        documentId: row['document_id'] as String,
        pageNumber: row['page_number'] as int,
        tool: _toolFromDb(row['tool'] as String),
        colorValue: row['color_value'] as int,
        opacity: (row['opacity'] as num).toDouble(),
        width: (row['width'] as num).toDouble(),
        points: InkStroke.decodePoints(row['points_json'] as String),
        createdAt: DateTime.parse(row['created_at'] as String),
      );

  static String _toolToDb(InkTool tool) => switch (tool) {
        InkTool.pen => 'pen',
        InkTool.pencil => 'pencil',
        InkTool.highlighter => 'highlighter',
      };

  static InkTool _toolFromDb(String value) => switch (value) {
        'pen' => InkTool.pen,
        'pencil' => InkTool.pencil,
        'highlighter' => InkTool.highlighter,
        _ => throw StateError('Ferramenta de tinta desconhecida: $value'),
      };
}

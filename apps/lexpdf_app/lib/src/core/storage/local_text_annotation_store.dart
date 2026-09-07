import 'local_database.dart';
import 'local_pdf_annotation_object_store.dart';

enum TextAnnotationType {
  highlight,
  underline,
  strikeout,
}

class LocalTextAnnotation {
  const LocalTextAnnotation({
    required this.id,
    required this.documentId,
    required this.pageNumber,
    required this.startIndex,
    required this.endIndex,
    required this.type,
    required this.colorValue,
    required this.opacity,
    required this.createdAt,
    required this.updatedAt,
    this.selectedText,
  });

  final String id;
  final String documentId;
  final int pageNumber;
  final int startIndex;
  final int endIndex;
  final TextAnnotationType type;
  final String? selectedText;
  final int colorValue;
  final double opacity;
  final DateTime createdAt;
  final DateTime updatedAt;

  LocalTextAnnotation copyWith({
    TextAnnotationType? type,
    int? colorValue,
    double? opacity,
    String? selectedText,
  }) {
    return LocalTextAnnotation(
      id: id,
      documentId: documentId,
      pageNumber: pageNumber,
      startIndex: startIndex,
      endIndex: endIndex,
      type: type ?? this.type,
      selectedText: selectedText ?? this.selectedText,
      colorValue: colorValue ?? this.colorValue,
      opacity: opacity ?? this.opacity,
      createdAt: createdAt,
      updatedAt: DateTime.now().toUtc(),
    );
  }
}

class LocalTextAnnotationStore {
  LocalTextAnnotationStore(this.db) {
    db.database.execute('''
      CREATE INDEX IF NOT EXISTS annotations_document_page_range_idx
      ON annotations(document_id, page_number, start_index);
    ''');
  }

  final LocalDatabase db;

  LocalPdfAnnotationObjectStore get objectStore =>
      LocalPdfAnnotationObjectStore(db);

  Future<List<LocalTextAnnotation>> listForDocument(String documentId) async {
    final rows = db.database.select(
      '''
      SELECT * FROM annotations
      WHERE document_id = ?
      ORDER BY page_number, start_index, created_at;
      ''',
      [documentId],
    );
    return rows.map(_fromRow).toList(growable: false);
  }

  Future<List<LocalTextAnnotation>> listForPage(
    String documentId,
    int pageNumber,
  ) async {
    final rows = db.database.select(
      '''
      SELECT * FROM annotations
      WHERE document_id = ? AND page_number = ?
      ORDER BY start_index, created_at;
      ''',
      [documentId, pageNumber],
    );
    return rows.map(_fromRow).toList(growable: false);
  }

  Future<List<LocalTextAnnotation>> listForPageRange(
    String documentId,
    int startPage,
    int endPage,
  ) async {
    if (endPage < startPage) return const [];
    final rows = db.database.select(
      '''
      SELECT * FROM annotations
      WHERE document_id = ? AND page_number BETWEEN ? AND ?
      ORDER BY page_number, start_index, created_at;
      ''',
      [documentId, startPage, endPage],
    );
    return rows.map(_fromRow).toList(growable: false);
  }

  Future<int> countForDocument(String documentId) async {
    final row = db.database.select(
      'SELECT COUNT(*) AS value FROM annotations WHERE document_id = ?;',
      [documentId],
    ).single;
    return row['value'] as int;
  }

  Future<void> upsert(LocalTextAnnotation annotation) async {
    if (annotation.pageNumber < 1) {
      throw ArgumentError.value(
        annotation.pageNumber,
        'pageNumber',
        'Must be >= 1',
      );
    }
    if (annotation.startIndex < 0 || annotation.endIndex < annotation.startIndex) {
      throw ArgumentError('Invalid text range.');
    }
    if (annotation.opacity < 0 || annotation.opacity > 1) {
      throw ArgumentError.value(
        annotation.opacity,
        'opacity',
        'Must be between 0 and 1',
      );
    }

    db.database.execute('''
      INSERT INTO annotations (
        id, document_id, page_number, start_index, end_index, type,
        selected_text, color_value, opacity, created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        page_number = excluded.page_number,
        start_index = excluded.start_index,
        end_index = excluded.end_index,
        type = excluded.type,
        selected_text = excluded.selected_text,
        color_value = excluded.color_value,
        opacity = excluded.opacity,
        updated_at = excluded.updated_at;
    ''', [
      annotation.id,
      annotation.documentId,
      annotation.pageNumber,
      annotation.startIndex,
      annotation.endIndex,
      _typeToDb(annotation.type),
      annotation.selectedText,
      annotation.colorValue,
      annotation.opacity,
      annotation.createdAt.toUtc().toIso8601String(),
      annotation.updatedAt.toUtc().toIso8601String(),
    ]);
  }

  Future<void> delete(String id) async {
    db.database.execute('DELETE FROM annotations WHERE id = ?;', [id]);
  }

  Future<void> deleteForDocument(String documentId) async {
    db.database.execute(
      'DELETE FROM annotations WHERE document_id = ?;',
      [documentId],
    );
  }

  LocalTextAnnotation _fromRow(dynamic row) {
    return LocalTextAnnotation(
      id: row['id'] as String,
      documentId: row['document_id'] as String,
      pageNumber: row['page_number'] as int,
      startIndex: row['start_index'] as int,
      endIndex: row['end_index'] as int,
      type: _typeFromDb(row['type'] as String),
      selectedText: row['selected_text'] as String?,
      colorValue: row['color_value'] as int,
      opacity: (row['opacity'] as num).toDouble(),
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }

  static String _typeToDb(TextAnnotationType type) => switch (type) {
        TextAnnotationType.highlight => 'highlight',
        TextAnnotationType.underline => 'underline',
        TextAnnotationType.strikeout => 'strikeout',
      };

  static TextAnnotationType _typeFromDb(String value) => switch (value) {
        'highlight' => TextAnnotationType.highlight,
        'underline' => TextAnnotationType.underline,
        'strikeout' => TextAnnotationType.strikeout,
        _ => throw StateError('Unknown annotation type: $value'),
      };
}

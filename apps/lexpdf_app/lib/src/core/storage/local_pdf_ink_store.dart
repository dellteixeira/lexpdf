import 'dart:convert';

import '../ink/ink_models.dart';
import '../ink/pdf_ink_models.dart';
import 'local_database.dart';

class PdfInkHistoryResult {
  const PdfInkHistoryResult({
    required this.documentId,
    required this.pageNumber,
    required this.changed,
  });

  final String documentId;
  final int pageNumber;
  final bool changed;
}

class LocalPdfInkStore {
  LocalPdfInkStore(this.db) {
    db.database.execute('''
      CREATE INDEX IF NOT EXISTS pdf_ink_document_page_range_idx
      ON pdf_ink_strokes(document_id, page_number, created_at);
    ''');
    db.database.execute('''
      CREATE TABLE IF NOT EXISTS pdf_ink_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        document_id TEXT NOT NULL,
        page_number INTEGER NOT NULL,
        before_json TEXT NOT NULL,
        after_json TEXT NOT NULL,
        undone INTEGER NOT NULL DEFAULT 0 CHECK(undone IN (0, 1)),
        created_at TEXT NOT NULL
      );
    ''');
    db.database.execute('''
      CREATE INDEX IF NOT EXISTS pdf_ink_history_document_state_idx
      ON pdf_ink_history(document_id, undone, id);
    ''');
  }

  final LocalDatabase db;

  Future<void> addStroke(PdfInkStroke stroke) async {
    final existing = _findById(stroke.id);
    await _applyUserMutation(
      documentId: stroke.documentId,
      pageNumber: stroke.pageNumber,
      before: existing == null ? const <PdfInkStroke>[] : <PdfInkStroke>[existing],
      after: <PdfInkStroke>[stroke],
    );
  }

  Future<void> replaceStrokeWithFragments(
    PdfInkStroke original,
    List<PdfInkStroke> fragments,
  ) async {
    for (final fragment in fragments) {
      if (fragment.documentId != original.documentId ||
          fragment.pageNumber != original.pageNumber) {
        throw ArgumentError('Fragmento não pertence ao mesmo documento/página.');
      }
    }

    final persisted = _findById(original.id) ?? original;
    await _applyUserMutation(
      documentId: original.documentId,
      pageNumber: original.pageNumber,
      before: <PdfInkStroke>[persisted],
      after: fragments,
    );
  }

  void _insertStroke(PdfInkStroke stroke) {
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

  Future<List<PdfInkStroke>> listForPageRange(
    String documentId,
    int startPage,
    int endPage,
  ) async {
    if (endPage < startPage) return const [];
    final rows = db.database.select('''
      SELECT * FROM pdf_ink_strokes
      WHERE document_id = ? AND page_number BETWEEN ? AND ?
      ORDER BY page_number ASC, created_at ASC;
    ''', [documentId, startPage, endPage]);
    return rows.map(_fromRow).toList(growable: false);
  }

  Future<int> countForDocument(String documentId) async {
    final row = db.database.select(
      'SELECT COUNT(*) AS value FROM pdf_ink_strokes WHERE document_id = ?;',
      [documentId],
    ).single;
    return row['value'] as int;
  }

  Future<List<int>> pagesWithInk(String documentId) async {
    final rows = db.database.select('''
      SELECT DISTINCT page_number FROM pdf_ink_strokes
      WHERE document_id = ? ORDER BY page_number;
    ''', [documentId]);
    return rows.map((row) => row['page_number'] as int).toList(growable: false);
  }

  Future<void> deleteStroke(String id) async {
    final existing = _findById(id);
    if (existing == null) return;
    await _applyUserMutation(
      documentId: existing.documentId,
      pageNumber: existing.pageNumber,
      before: <PdfInkStroke>[existing],
      after: const <PdfInkStroke>[],
    );
  }

  Future<void> clearPage(String documentId, int pageNumber) async {
    final existing = await listForPage(documentId, pageNumber);
    if (existing.isEmpty) return;
    await _applyUserMutation(
      documentId: documentId,
      pageNumber: pageNumber,
      before: existing,
      after: const <PdfInkStroke>[],
    );
  }

  Future<bool> canUndo(String documentId) async => _historyExists(
        documentId: documentId,
        undone: false,
      );

  Future<bool> canRedo(String documentId) async => _historyExists(
        documentId: documentId,
        undone: true,
      );

  Future<PdfInkHistoryResult> undo(String documentId) async {
    final rows = db.database.select('''
      SELECT id, page_number, before_json, after_json
      FROM pdf_ink_history
      WHERE document_id = ? AND undone = 0
      ORDER BY id DESC
      LIMIT 1;
    ''', [documentId]);
    if (rows.isEmpty) {
      return PdfInkHistoryResult(
        documentId: documentId,
        pageNumber: 1,
        changed: false,
      );
    }

    final row = rows.first;
    final before = _decodeStrokeList(row['before_json'] as String);
    final after = _decodeStrokeList(row['after_json'] as String);
    db.database.execute('BEGIN IMMEDIATE;');
    try {
      _applyHistoryState(target: before, counterpart: after);
      db.database.execute(
        'UPDATE pdf_ink_history SET undone = 1 WHERE id = ?;',
        [row['id']],
      );
      db.database.execute('COMMIT;');
    } catch (_) {
      db.database.execute('ROLLBACK;');
      rethrow;
    }
    return PdfInkHistoryResult(
      documentId: documentId,
      pageNumber: row['page_number'] as int,
      changed: true,
    );
  }

  Future<PdfInkHistoryResult> redo(String documentId) async {
    final rows = db.database.select('''
      SELECT id, page_number, before_json, after_json
      FROM pdf_ink_history
      WHERE document_id = ? AND undone = 1
      ORDER BY id ASC
      LIMIT 1;
    ''', [documentId]);
    if (rows.isEmpty) {
      return PdfInkHistoryResult(
        documentId: documentId,
        pageNumber: 1,
        changed: false,
      );
    }

    final row = rows.first;
    final before = _decodeStrokeList(row['before_json'] as String);
    final after = _decodeStrokeList(row['after_json'] as String);
    db.database.execute('BEGIN IMMEDIATE;');
    try {
      _applyHistoryState(target: after, counterpart: before);
      db.database.execute(
        'UPDATE pdf_ink_history SET undone = 0 WHERE id = ?;',
        [row['id']],
      );
      db.database.execute('COMMIT;');
    } catch (_) {
      db.database.execute('ROLLBACK;');
      rethrow;
    }
    return PdfInkHistoryResult(
      documentId: documentId,
      pageNumber: row['page_number'] as int,
      changed: true,
    );
  }

  Future<void> _applyUserMutation({
    required String documentId,
    required int pageNumber,
    required List<PdfInkStroke> before,
    required List<PdfInkStroke> after,
  }) async {
    if (pageNumber < 1) {
      throw ArgumentError.value(pageNumber, 'pageNumber', 'Must be >= 1');
    }
    db.database.execute('BEGIN IMMEDIATE;');
    try {
      // A new edit after Undo creates a new branch of history. Discard the old
      // redo tail just like desktop editors do.
      db.database.execute(
        'DELETE FROM pdf_ink_history WHERE document_id = ? AND undone = 1;',
        [documentId],
      );
      _applyHistoryState(target: after, counterpart: before);
      db.database.execute('''
        INSERT INTO pdf_ink_history(
          document_id, page_number, before_json, after_json, undone, created_at
        ) VALUES (?, ?, ?, ?, 0, ?);
      ''', [
        documentId,
        pageNumber,
        _encodeStrokeList(before),
        _encodeStrokeList(after),
        DateTime.now().toUtc().toIso8601String(),
      ]);
      db.database.execute('COMMIT;');
    } catch (_) {
      db.database.execute('ROLLBACK;');
      rethrow;
    }
  }

  void _applyHistoryState({
    required List<PdfInkStroke> target,
    required List<PdfInkStroke> counterpart,
  }) {
    final ids = <String>{
      for (final stroke in target) stroke.id,
      for (final stroke in counterpart) stroke.id,
    };
    for (final id in ids) {
      db.database.execute('DELETE FROM pdf_ink_strokes WHERE id = ?;', [id]);
    }
    for (final stroke in target) {
      _insertStroke(stroke);
    }
  }

  Future<bool> _historyExists({
    required String documentId,
    required bool undone,
  }) async {
    final rows = db.database.select(
      'SELECT 1 FROM pdf_ink_history '
      'WHERE document_id = ? AND undone = ? LIMIT 1;',
      [documentId, undone ? 1 : 0],
    );
    return rows.isNotEmpty;
  }

  PdfInkStroke? _findById(String id) {
    final rows = db.database.select(
      'SELECT * FROM pdf_ink_strokes WHERE id = ? LIMIT 1;',
      [id],
    );
    return rows.isEmpty ? null : _fromRow(rows.first);
  }

  String _encodeStrokeList(List<PdfInkStroke> strokes) => jsonEncode(
        strokes.map(_strokeToJson).toList(growable: false),
      );

  List<PdfInkStroke> _decodeStrokeList(String value) {
    final decoded = jsonDecode(value);
    if (decoded is! List) return const <PdfInkStroke>[];
    return decoded
        .whereType<Map>()
        .map((item) => _strokeFromJson(item.cast<String, Object?>()))
        .toList(growable: false);
  }

  Map<String, Object?> _strokeToJson(PdfInkStroke stroke) => <String, Object?>{
        'id': stroke.id,
        'documentId': stroke.documentId,
        'pageNumber': stroke.pageNumber,
        'tool': _toolToDb(stroke.tool),
        'colorValue': stroke.colorValue,
        'opacity': stroke.opacity,
        'width': stroke.width,
        'pointsJson': stroke.encodePoints(),
        'createdAt': stroke.createdAt.toUtc().toIso8601String(),
      };

  PdfInkStroke _strokeFromJson(Map<String, Object?> json) => PdfInkStroke(
        id: json['id'] as String,
        documentId: json['documentId'] as String,
        pageNumber: (json['pageNumber'] as num).toInt(),
        tool: _toolFromDb(json['tool'] as String),
        colorValue: (json['colorValue'] as num).toInt(),
        opacity: (json['opacity'] as num).toDouble(),
        width: (json['width'] as num).toDouble(),
        points: InkStroke.decodePoints(json['pointsJson'] as String),
        createdAt: DateTime.parse(json['createdAt'] as String),
      );

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

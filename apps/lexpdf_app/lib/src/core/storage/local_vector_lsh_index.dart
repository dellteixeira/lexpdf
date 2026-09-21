import 'dart:math' as math;
import 'dart:typed_data';

import 'local_database.dart';

class LocalVectorLshIndex {
  LocalVectorLshIndex(this.db) {
    _ensureTable();
  }

  final LocalDatabase db;

  static const int _signatureBits = 12;
  static const int _linearThreshold = 700;
  static const int _maxBucketRows = 900;

  void _ensureTable() {
    db.database.execute('''
      CREATE TABLE IF NOT EXISTS local_vector_lsh (
        namespace TEXT NOT NULL,
        source_key TEXT NOT NULL,
        model TEXT NOT NULL,
        dimensions INTEGER NOT NULL,
        signature_a INTEGER NOT NULL,
        signature_b INTEGER NOT NULL,
        vector_blob BLOB NOT NULL,
        updated_at TEXT NOT NULL,
        PRIMARY KEY(namespace, source_key)
      );
    ''');
    db.database.execute('''
      CREATE INDEX IF NOT EXISTS local_vector_lsh_lookup_a_idx
      ON local_vector_lsh(namespace, model, dimensions, signature_a);
    ''');
    db.database.execute('''
      CREATE INDEX IF NOT EXISTS local_vector_lsh_lookup_b_idx
      ON local_vector_lsh(namespace, model, dimensions, signature_b);
    ''');
  }

  void upsert({
    required String namespace,
    required String sourceKey,
    required String model,
    required List<double> vector,
  }) {
    if (vector.isEmpty) return;
    db.database.execute('''
      INSERT INTO local_vector_lsh(
        namespace, source_key, model, dimensions, signature_a, signature_b,
        vector_blob, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(namespace, source_key) DO UPDATE SET
        model = excluded.model,
        dimensions = excluded.dimensions,
        signature_a = excluded.signature_a,
        signature_b = excluded.signature_b,
        vector_blob = excluded.vector_blob,
        updated_at = excluded.updated_at;
    ''', [
      namespace,
      sourceKey,
      model,
      vector.length,
      _signature(vector, 0x13579bdf),
      _signature(vector, 0x2468ace1),
      _encode(vector),
      DateTime.now().toUtc().toIso8601String(),
    ]);
  }

  /// Null means this model has no accelerated index yet; callers may use
  /// their backwards-compatible linear path for older persisted embeddings.
  List<String>? candidateKeys({
    required String namespace,
    required String model,
    required List<double> queryVector,
    int maxResults = 96,
  }) {
    if (queryVector.isEmpty) return const [];
    final countRows = db.database.select('''
      SELECT COUNT(*) AS c FROM local_vector_lsh
      WHERE namespace = ? AND model = ? AND dimensions = ?;
    ''', [namespace, model, queryVector.length]);
    final count = countRows.single['c'] as int? ?? 0;
    if (count == 0) return null;

    List<dynamic> rows;
    if (count <= _linearThreshold) {
      rows = db.database.select('''
        SELECT source_key, vector_blob FROM local_vector_lsh
        WHERE namespace = ? AND model = ? AND dimensions = ?;
      ''', [namespace, model, queryVector.length]);
    } else {
      final a = _neighbors(_signature(queryVector, 0x13579bdf));
      final b = _neighbors(_signature(queryVector, 0x2468ace1));
      final aMarks = List.filled(a.length, '?').join(',');
      final bMarks = List.filled(b.length, '?').join(',');
      rows = db.database.select('''
        SELECT source_key, vector_blob FROM local_vector_lsh
        WHERE namespace = ? AND model = ? AND dimensions = ?
          AND (signature_a IN ($aMarks) OR signature_b IN ($bMarks))
        LIMIT ?;
      ''', [
        namespace,
        model,
        queryVector.length,
        ...a,
        ...b,
        _maxBucketRows,
      ]);
      if (rows.isEmpty) {
        rows = db.database.select('''
          SELECT source_key, vector_blob FROM local_vector_lsh
          WHERE namespace = ? AND model = ? AND dimensions = ?
          ORDER BY updated_at DESC
          LIMIT ?;
        ''', [namespace, model, queryVector.length, _linearThreshold]);
      }
    }

    final scored = <({String key, double score})>[];
    for (final row in rows) {
      final blob = row['vector_blob'];
      if (blob is! Uint8List) continue;
      final vector = _decode(blob);
      if (vector.length != queryVector.length) continue;
      scored.add((
        key: row['source_key'] as String,
        score: _cosine(queryVector, vector),
      ));
    }
    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored
        .take(maxResults)
        .map((item) => item.key)
        .toList(growable: false);
  }

  int count({required String namespace, String? model}) {
    final rows = model == null
        ? db.database.select(
            'SELECT COUNT(*) AS c FROM local_vector_lsh WHERE namespace = ?;',
            [namespace],
          )
        : db.database.select('''
            SELECT COUNT(*) AS c FROM local_vector_lsh
            WHERE namespace = ? AND model = ?;
          ''', [namespace, model]);
    return rows.single['c'] as int? ?? 0;
  }

  static Uint8List _encode(List<double> vector) {
    final data = ByteData(vector.length * 4);
    for (var i = 0; i < vector.length; i++) {
      data.setFloat32(i * 4, vector[i], Endian.little);
    }
    return data.buffer.asUint8List();
  }

  static List<double> _decode(Uint8List bytes) {
    if (bytes.lengthInBytes % 4 != 0) return const [];
    final data = ByteData.sublistView(bytes);
    return List<double>.generate(
      bytes.lengthInBytes ~/ 4,
      (index) => data.getFloat32(index * 4, Endian.little),
      growable: false,
    );
  }

  static int _signature(List<double> vector, int seed) {
    var signature = 0;
    for (var bit = 0; bit < _signatureBits; bit++) {
      var projection = 0.0;
      for (var index = 0; index < vector.length; index++) {
        final mixed = _mix32(index ^ seed ^ (bit * 0x9e3779b9));
        projection += vector[index] * ((mixed & 1) == 0 ? 1 : -1);
      }
      if (projection >= 0) signature |= 1 << bit;
    }
    return signature;
  }

  static List<int> _neighbors(int signature) => <int>[
        signature,
        for (var bit = 0; bit < _signatureBits; bit++) signature ^ (1 << bit),
      ];

  static int _mix32(int value) {
    var x = value & 0xffffffff;
    x = (x ^ (x >> 16)) & 0xffffffff;
    x = (x * 0x7feb352d) & 0xffffffff;
    x = (x ^ (x >> 15)) & 0xffffffff;
    x = (x * 0x846ca68b) & 0xffffffff;
    return (x ^ (x >> 16)) & 0xffffffff;
  }

  static double _cosine(List<double> a, List<double> b) {
    if (a.length != b.length || a.isEmpty) return -1;
    var dot = 0.0;
    var aa = 0.0;
    var bb = 0.0;
    for (var i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      aa += a[i] * a[i];
      bb += b[i] * b[i];
    }
    if (aa == 0 || bb == 0) return -1;
    return dot / (math.sqrt(aa) * math.sqrt(bb));
  }
}

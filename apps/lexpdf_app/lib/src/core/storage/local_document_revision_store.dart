import 'dart:io';

import 'package:crypto/crypto.dart';

import '../documents/document_provider.dart';
import 'local_database.dart';

class LocalDocumentRevision {
  const LocalDocumentRevision({
    required this.id,
    required this.documentId,
    required this.documentTitle,
    required this.reason,
    required this.snapshotPath,
    required this.checksum,
    required this.localVersion,
    required this.sizeBytes,
    required this.createdAt,
    this.provider,
    this.remoteVersion,
  });

  final String id;
  final String documentId;
  final String documentTitle;
  final String reason;
  final String snapshotPath;
  final String checksum;
  final int localVersion;
  final int sizeBytes;
  final DateTime createdAt;
  final String? provider;
  final String? remoteVersion;
}

class LocalDocumentRevisionStore {
  LocalDocumentRevisionStore(this.db) {
    _ensureTable();
  }

  final LocalDatabase db;

  static const int defaultMaxRevisionsPerDocument = 20;
  static const int defaultMaxBytesPerDocument = 512 * 1024 * 1024;

  void _ensureTable() {
    db.database.execute('''
      CREATE TABLE IF NOT EXISTS local_document_revisions (
        id TEXT PRIMARY KEY,
        document_id TEXT NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
        document_title TEXT NOT NULL,
        reason TEXT NOT NULL,
        snapshot_path TEXT NOT NULL,
        checksum TEXT NOT NULL,
        local_version INTEGER NOT NULL,
        provider TEXT,
        remote_version TEXT,
        size_bytes INTEGER NOT NULL,
        created_at TEXT NOT NULL
      );
    ''');
    db.database.execute('''
      CREATE INDEX IF NOT EXISTS local_document_revisions_document_idx
      ON local_document_revisions(document_id, created_at DESC);
    ''');
  }

  Future<LocalDocumentRevision?> capture(
    DocumentRef document, {
    required String reason,
    String? provider,
    String? remoteVersion,
    String? checksum,
  }) async {
    final path = document.localPath;
    if (path == null || path.trim().isEmpty) return null;
    final source = File(path);
    if (!await source.exists()) return null;

    final actualChecksum = checksum ?? await _sha256File(source);
    final existingRows = db.database.select('''
      SELECT * FROM local_document_revisions
      WHERE document_id = ? AND checksum = ?
      ORDER BY created_at DESC
      LIMIT 1;
    ''', [document.id, actualChecksum]);
    if (existingRows.isNotEmpty) {
      final existing = _fromRow(existingRows.first);
      if (await File(existing.snapshotPath).exists()) return existing;
      db.database.execute(
        'DELETE FROM local_document_revisions WHERE id = ?;',
        [existing.id],
      );
    }

    final now = DateTime.now().toUtc();
    final revisionId =
        'revision-${now.microsecondsSinceEpoch.toRadixString(36)}';
    final directory = Directory(
      '${source.parent.path}${Platform.pathSeparator}.lexpdf-revisions'
      '${Platform.pathSeparator}${_safeId(document.id)}',
    );
    await directory.create(recursive: true);
    final extension = _extension(source.path);
    final snapshot = File(
      '${directory.path}${Platform.pathSeparator}'
      '${now.microsecondsSinceEpoch}-${actualChecksum.substring(0, 12)}'
      '$extension',
    );
    await source.copy(snapshot.path);
    final size = await snapshot.length();

    db.database.execute('''
      INSERT INTO local_document_revisions(
        id, document_id, document_title, reason, snapshot_path, checksum,
        local_version, provider, remote_version, size_bytes, created_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
    ''', [
      revisionId,
      document.id,
      document.name,
      reason,
      snapshot.path,
      actualChecksum,
      document.localVersion,
      provider,
      remoteVersion,
      size,
      now.toIso8601String(),
    ]);

    await pruneDocument(document.id);
    return (await get(revisionId));
  }

  Future<LocalDocumentRevision?> get(String id) async {
    final rows = db.database.select(
      'SELECT * FROM local_document_revisions WHERE id = ? LIMIT 1;',
      [id],
    );
    return rows.isEmpty ? null : _fromRow(rows.first);
  }

  Future<List<LocalDocumentRevision>> listRecent({
    String? documentId,
    int limit = 100,
  }) async {
    final rows = documentId == null
        ? db.database.select('''
            SELECT * FROM local_document_revisions
            ORDER BY created_at DESC LIMIT ?;
          ''', [limit])
        : db.database.select('''
            SELECT * FROM local_document_revisions
            WHERE document_id = ?
            ORDER BY created_at DESC LIMIT ?;
          ''', [documentId, limit]);
    final result = <LocalDocumentRevision>[];
    for (final row in rows) {
      final item = _fromRow(row);
      if (await File(item.snapshotPath).exists()) {
        result.add(item);
      } else {
        db.database.execute(
          'DELETE FROM local_document_revisions WHERE id = ?;',
          [item.id],
        );
      }
    }
    return result;
  }

  Future<String> restore(
    LocalDocumentRevision revision, {
    required String targetPath,
  }) async {
    final source = File(revision.snapshotPath);
    if (!await source.exists()) {
      throw FileSystemException(
        'O snapshot desta versão não está mais disponível.',
        revision.snapshotPath,
      );
    }
    final checksum = await _sha256File(source);
    if (checksum != revision.checksum) {
      throw StateError('Checksum da versão histórica não confere.');
    }

    final target = File(targetPath);
    await target.parent.create(recursive: true);
    final token = DateTime.now().toUtc().microsecondsSinceEpoch;
    final partial = File('$targetPath.lexpdf-restore-partial-$token');
    final backup = File('$targetPath.lexpdf-restore-backup-$token');
    var parked = false;
    try {
      await source.openRead().pipe(partial.openWrite());
      final partialChecksum = await _sha256File(partial);
      if (partialChecksum != revision.checksum) {
        throw StateError('Falha de integridade ao restaurar a versão.');
      }
      if (await target.exists()) {
        await target.rename(backup.path);
        parked = true;
      }
      try {
        await partial.rename(target.path);
      } catch (_) {
        if (parked && await backup.exists()) {
          await backup.rename(target.path);
          parked = false;
        }
        rethrow;
      }
      if (await backup.exists()) await backup.delete();
      parked = false;
      return revision.checksum;
    } finally {
      if (await partial.exists()) await partial.delete();
      if (parked && await backup.exists() && !await target.exists()) {
        await backup.rename(target.path);
      } else if (await backup.exists()) {
        await backup.delete();
      }
    }
  }

  Future<void> pruneDocument(
    String documentId, {
    int maxRevisions = defaultMaxRevisionsPerDocument,
    int maxBytes = defaultMaxBytesPerDocument,
  }) async {
    final rows = db.database.select('''
      SELECT * FROM local_document_revisions
      WHERE document_id = ?
      ORDER BY created_at DESC;
    ''', [documentId]);
    var kept = 0;
    var bytes = 0;
    for (final row in rows) {
      final item = _fromRow(row);
      final file = File(item.snapshotPath);
      final exists = await file.exists();
      final shouldKeep =
          exists && kept < maxRevisions && bytes + item.sizeBytes <= maxBytes;
      if (shouldKeep) {
        kept++;
        bytes += item.sizeBytes;
        continue;
      }
      if (exists) {
        try {
          await file.delete();
        } catch (_) {}
      }
      db.database.execute(
        'DELETE FROM local_document_revisions WHERE id = ?;',
        [item.id],
      );
    }
  }

  Future<void> delete(LocalDocumentRevision revision) async {
    final file = File(revision.snapshotPath);
    if (await file.exists()) {
      try {
        await file.delete();
      } catch (_) {}
    }
    db.database.execute(
      'DELETE FROM local_document_revisions WHERE id = ?;',
      [revision.id],
    );
  }

  static Future<String> _sha256File(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }

  static String _extension(String path) {
    final slash = path.lastIndexOf(RegExp(r'[\\/]'));
    final dot = path.lastIndexOf('.');
    if (dot <= slash) return '';
    final ext = path.substring(dot);
    return ext.length <= 12 ? ext : '';
  }

  static String _safeId(String value) =>
      value.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');

  LocalDocumentRevision _fromRow(dynamic row) => LocalDocumentRevision(
        id: row['id'] as String,
        documentId: row['document_id'] as String,
        documentTitle: row['document_title'] as String,
        reason: row['reason'] as String,
        snapshotPath: row['snapshot_path'] as String,
        checksum: row['checksum'] as String,
        localVersion: row['local_version'] as int,
        provider: row['provider'] as String?,
        remoteVersion: row['remote_version'] as String?,
        sizeBytes: row['size_bytes'] as int,
        createdAt: DateTime.parse(row['created_at'] as String),
      );
}

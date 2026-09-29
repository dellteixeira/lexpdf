import 'dart:io';

import '../documents/document_provider.dart';
import '../documents/local_document_identity.dart';
import 'local_database.dart';

class LocalDocumentCatalog {
  LocalDocumentCatalog(this.db) {
    _ensureIdentitySchema();
  }

  static const String _legacySystemFileProvider = 'i' 'cloud';

  final LocalDatabase db;
  static const LocalDocumentIdentity _identity = LocalDocumentIdentity();

  void _ensureIdentitySchema() {
    db.database.execute('''
      CREATE TABLE IF NOT EXISTS local_document_identity_aliases (
        fingerprint TEXT PRIMARY KEY,
        document_id TEXT NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
        updated_at TEXT NOT NULL
      );
    ''');
    db.database.execute('''
      CREATE INDEX IF NOT EXISTS local_document_identity_document_idx
      ON local_document_identity_aliases(document_id);
    ''');
  }

  Future<DocumentRef> resolveLocalDocument(DocumentRef incoming) async {
    if (incoming.provider != DocumentProviderKind.local ||
        !incoming.hasLocalPath) {
      await upsert(incoming);
      return await getById(incoming.id) ?? incoming;
    }

    final path = incoming.localPath!;
    var fingerprint = _identity.fingerprintFromId(incoming.id);
    fingerprint ??= await _identity.fingerprintFile(path);

    final byId = await getById(incoming.id);
    if (byId != null) {
      final merged = byId.copyWith(
        name: incoming.name,
        localPath: path,
        availableOffline: true,
      );
      await upsert(merged);
      _upsertIdentityAlias(fingerprint, merged.id);
      return merged;
    }

    final byPath = _getByLocalPath(path);
    if (byPath != null) {
      final merged = byPath.copyWith(
        name: incoming.name,
        localPath: path,
        availableOffline: true,
      );
      await upsert(merged);
      _upsertIdentityAlias(fingerprint, merged.id);
      return merged;
    }

    final aliasedId = _documentIdForFingerprint(fingerprint);
    if (aliasedId != null) {
      final aliased = await getById(aliasedId);
      if (aliased != null) {
        final merged = aliased.copyWith(
          name: incoming.name,
          localPath: path,
          availableOffline: true,
        );
        await upsert(merged);
        _upsertIdentityAlias(fingerprint, merged.id);
        return merged;
      }
    }

    await upsert(incoming);
    _upsertIdentityAlias(fingerprint, incoming.id);
    return await getById(incoming.id) ?? incoming;
  }

  Future<void> backfillLocalIdentityAliases() async {
    final documents = await list(limit: 1000);
    for (final document in documents) {
      if (document.provider != DocumentProviderKind.local ||
          !document.hasLocalPath) {
        continue;
      }
      final path = document.localPath!;
      if (!File(path).isFileSync()) continue;
      try {
        final fingerprint = await _identity.fingerprintFile(path);
        _upsertIdentityAlias(fingerprint, document.id);
      } catch (_) {
        // Identity backfill is advisory and must never block library startup.
      }
      await Future<void>.delayed(Duration.zero);
    }
  }

  DocumentRef? _getByLocalPath(String path) {
    final rows = db.database.select(
      'SELECT * FROM documents WHERE local_path = ? LIMIT 1;',
      [path],
    );
    return rows.isEmpty ? null : _fromRow(rows.first);
  }

  String? _documentIdForFingerprint(String fingerprint) {
    final rows = db.database.select(
      'SELECT document_id FROM local_document_identity_aliases '
      'WHERE fingerprint = ? LIMIT 1;',
      [fingerprint],
    );
    return rows.isEmpty ? null : rows.first['document_id'] as String;
  }

  void _upsertIdentityAlias(String fingerprint, String documentId) {
    db.database.execute('''
      INSERT INTO local_document_identity_aliases(
        fingerprint, document_id, updated_at
      ) VALUES (?, ?, ?)
      ON CONFLICT(fingerprint) DO UPDATE SET
        document_id = excluded.document_id,
        updated_at = excluded.updated_at;
    ''', [
      fingerprint,
      documentId,
      DateTime.now().toUtc().toIso8601String(),
    ]);
  }

  Future<void> upsert(DocumentRef document) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final filename = document.name;

    db.database.execute('''
      INSERT INTO documents (
        id, title, filename, provider, provider_file_id, local_path,
        remote_path, checksum, remote_version, local_version,
        is_available_offline, sync_status, is_favorite,
        created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        title = excluded.title,
        filename = excluded.filename,
        provider = excluded.provider,
        provider_file_id = excluded.provider_file_id,
        local_path = excluded.local_path,
        remote_path = excluded.remote_path,
        checksum = excluded.checksum,
        remote_version = excluded.remote_version,
        local_version = excluded.local_version,
        is_available_offline = excluded.is_available_offline,
        sync_status = excluded.sync_status,
        updated_at = excluded.updated_at;
    ''', [
      document.id,
      document.name,
      filename,
      _providerToDb(document.provider),
      document.remoteId,
      document.localPath,
      document.remotePath,
      document.checksum,
      document.remoteVersion,
      document.localVersion,
      document.availableOffline ? 1 : 0,
      _syncToDb(document.syncState),
      document.favorite ? 1 : 0,
      now,
      now,
    ]);
  }

  Future<DocumentRef?> getById(String id) async {
    final rows = db.database.select('SELECT * FROM documents WHERE id = ? LIMIT 1;', [id]);
    if (rows.isEmpty) return null;
    return _fromRow(rows.first);
  }

  Future<List<DocumentRef>> list({int limit = 200}) async {
    final rows = db.database.select(
      'SELECT * FROM documents ORDER BY COALESCE(last_opened_at, updated_at) DESC LIMIT ?;',
      [limit],
    );
    return rows.map(_fromRow).toList(growable: false);
  }

  Future<List<DocumentRef>> listRecent({int limit = 200}) async {
    final rows = db.database.select('''
      SELECT * FROM documents
      WHERE last_opened_at IS NOT NULL
      ORDER BY last_opened_at DESC
      LIMIT ?;
    ''', [limit]);
    return rows.map(_fromRow).toList(growable: false);
  }

  Future<List<DocumentRef>> listFavorites({int limit = 200}) async {
    final rows = db.database.select('''
      SELECT * FROM documents WHERE is_favorite = 1
      ORDER BY COALESCE(last_opened_at, updated_at) DESC LIMIT ?;
    ''', [limit]);
    return rows.map(_fromRow).toList(growable: false);
  }

  Future<void> setFavorite(String id, bool favorite) async {
    db.database.execute(
      'UPDATE documents SET is_favorite = ?, updated_at = ? WHERE id = ?;',
      [favorite ? 1 : 0, DateTime.now().toUtc().toIso8601String(), id],
    );
  }

  Future<bool> isFavorite(String id) async {
    final rows = db.database.select('SELECT is_favorite FROM documents WHERE id = ? LIMIT 1;', [id]);
    return rows.isNotEmpty && (rows.first['is_favorite'] as int) == 1;
  }

  Future<void> markOpened(String id) async {
    final now = DateTime.now().toUtc().toIso8601String();
    db.database.execute(
      'UPDATE documents SET last_opened_at = ?, updated_at = ? WHERE id = ?;',
      [now, now, id],
    );
  }

  Future<void> updateSyncMetadata({
    required String id,
    String? checksum,
    String? remoteVersion,
    int? localVersion,
    DocumentSyncState? state,
  }) async {
    final current = await getById(id);
    if (current == null) return;
    await upsert(current.copyWith(
      checksum: checksum,
      remoteVersion: remoteVersion,
      localVersion: localVersion,
      syncState: state,
    ));
  }

  Future<void> incrementLocalVersion(String id) async {
    db.database.execute('''
      UPDATE documents
      SET local_version = local_version + 1,
          sync_status = 'sync_pending',
          updated_at = ?
      WHERE id = ?;
    ''', [DateTime.now().toUtc().toIso8601String(), id]);
  }

  Future<void> remove(String id) async {
    db.database.execute('DELETE FROM documents WHERE id = ?;', [id]);
  }

  DocumentRef _fromRow(dynamic row) => DocumentRef(
        id: row['id'] as String,
        name: row['title'] as String,
        provider: _providerFromDb(row['provider'] as String),
        localPath: row['local_path'] as String?,
        remoteId: row['provider_file_id'] as String?,
        remotePath: row['remote_path'] as String?,
        checksum: row['checksum'] as String?,
        remoteVersion: row['remote_version'] as String?,
        localVersion: row['local_version'] as int,
        availableOffline: (row['is_available_offline'] as int) == 1,
        favorite: (row['is_favorite'] as int) == 1,
        syncState: _syncFromDb(row['sync_status'] as String),
      );

  static String _providerToDb(DocumentProviderKind value) => switch (value) {
        DocumentProviderKind.local => 'local',
        DocumentProviderKind.googleDrive => 'google_drive',
        DocumentProviderKind.oneDrive => 'onedrive',
        DocumentProviderKind.systemFile => 'system_file',
        DocumentProviderKind.r2 => 'r2',
      };

  static DocumentProviderKind _providerFromDb(String value) => switch (value) {
        'local' => DocumentProviderKind.local,
        'google_drive' => DocumentProviderKind.googleDrive,
        'onedrive' => DocumentProviderKind.oneDrive,
        _legacySystemFileProvider => DocumentProviderKind.systemFile,
        'system_file' => DocumentProviderKind.systemFile,
        'r2' => DocumentProviderKind.r2,
        _ => throw StateError('Provedor desconhecido no banco local: $value'),
      };

  static String _syncToDb(DocumentSyncState value) => switch (value) {
        DocumentSyncState.localOnly => 'local_only',
        DocumentSyncState.remoteOnly => 'remote_only',
        DocumentSyncState.synced => 'synced',
        DocumentSyncState.syncPending => 'sync_pending',
        DocumentSyncState.downloading => 'downloading',
        DocumentSyncState.uploading => 'uploading',
        DocumentSyncState.conflict => 'conflict',
        DocumentSyncState.error => 'error',
      };

  static DocumentSyncState _syncFromDb(String value) => switch (value) {
        'local_only' => DocumentSyncState.localOnly,
        'remote_only' => DocumentSyncState.remoteOnly,
        'synced' => DocumentSyncState.synced,
        'sync_pending' => DocumentSyncState.syncPending,
        'downloading' => DocumentSyncState.downloading,
        'uploading' => DocumentSyncState.uploading,
        'conflict' => DocumentSyncState.conflict,
        'error' => DocumentSyncState.error,
        _ => throw StateError('Estado de sincronização desconhecido: $value'),
      };
}

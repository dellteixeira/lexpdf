import '../documents/document_provider.dart';
import 'local_database.dart';

class LocalDocumentCatalog {
  const LocalDocumentCatalog(this.db);

  final LocalDatabase db;

  Future<void> upsert(DocumentRef document) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final filename = document.name;

    db.database.execute('''
      INSERT INTO documents (
        id, title, filename, provider, provider_file_id, local_path,
        remote_path, is_available_offline, sync_status, is_favorite,
        created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        title = excluded.title,
        filename = excluded.filename,
        provider = excluded.provider,
        provider_file_id = excluded.provider_file_id,
        local_path = excluded.local_path,
        remote_path = excluded.remote_path,
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
      document.availableOffline ? 1 : 0,
      _syncToDb(document.syncState),
      document.favorite ? 1 : 0,
      now,
      now,
    ]);
  }

  Future<DocumentRef?> getById(String id) async {
    final rows = db.database.select(
      'SELECT * FROM documents WHERE id = ? LIMIT 1;',
      [id],
    );
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

  Future<List<DocumentRef>> listFavorites({int limit = 200}) async {
    final rows = db.database.select(
      '''
      SELECT * FROM documents
      WHERE is_favorite = 1
      ORDER BY COALESCE(last_opened_at, updated_at) DESC
      LIMIT ?;
      ''',
      [limit],
    );
    return rows.map(_fromRow).toList(growable: false);
  }

  Future<void> setFavorite(String id, bool favorite) async {
    final now = DateTime.now().toUtc().toIso8601String();
    db.database.execute(
      'UPDATE documents SET is_favorite = ?, updated_at = ? WHERE id = ?;',
      [favorite ? 1 : 0, now, id],
    );
  }

  Future<bool> isFavorite(String id) async {
    final rows = db.database.select(
      'SELECT is_favorite FROM documents WHERE id = ? LIMIT 1;',
      [id],
    );
    if (rows.isEmpty) return false;
    return (rows.first['is_favorite'] as int) == 1;
  }

  Future<void> markOpened(String id) async {
    final now = DateTime.now().toUtc().toIso8601String();
    db.database.execute(
      'UPDATE documents SET last_opened_at = ?, updated_at = ? WHERE id = ?;',
      [now, now, id],
    );
  }

  Future<void> remove(String id) async {
    db.database.execute('DELETE FROM documents WHERE id = ?;', [id]);
  }

  DocumentRef _fromRow(dynamic row) {
    return DocumentRef(
      id: row['id'] as String,
      name: row['title'] as String,
      provider: _providerFromDb(row['provider'] as String),
      localPath: row['local_path'] as String?,
      remoteId: row['provider_file_id'] as String?,
      remotePath: row['remote_path'] as String?,
      availableOffline: (row['is_available_offline'] as int) == 1,
      favorite: (row['is_favorite'] as int) == 1,
      syncState: _syncFromDb(row['sync_status'] as String),
    );
  }

  static String _providerToDb(DocumentProviderKind value) => switch (value) {
        DocumentProviderKind.local => 'local',
        DocumentProviderKind.googleDrive => 'google_drive',
        DocumentProviderKind.oneDrive => 'onedrive',
        DocumentProviderKind.iCloud => 'icloud',
        DocumentProviderKind.r2 => 'r2',
      };

  static DocumentProviderKind _providerFromDb(String value) => switch (value) {
        'local' => DocumentProviderKind.local,
        'google_drive' => DocumentProviderKind.googleDrive,
        'onedrive' => DocumentProviderKind.oneDrive,
        'icloud' => DocumentProviderKind.iCloud,
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

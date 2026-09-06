import 'local_database.dart';

class LocalBackendMapStore {
  LocalBackendMapStore(this.db) {
    db.database.execute('''
      CREATE TABLE IF NOT EXISTS backend_entity_map (
        local_id TEXT NOT NULL,
        entity_type TEXT NOT NULL,
        remote_id TEXT NOT NULL,
        remote_version TEXT,
        updated_at TEXT NOT NULL,
        PRIMARY KEY(local_id, entity_type),
        UNIQUE(remote_id, entity_type)
      );
    ''');
  }

  final LocalDatabase db;

  Future<String?> remoteId(String entityType, String localId) async {
    final rows = db.database.select('''
      SELECT remote_id FROM backend_entity_map
      WHERE local_id = ? AND entity_type = ? LIMIT 1;
    ''', [localId, entityType]);
    return rows.isEmpty ? null : rows.first['remote_id'] as String;
  }

  Future<void> upsert({
    required String entityType,
    required String localId,
    required String remoteId,
    String? remoteVersion,
  }) async {
    db.database.execute('''
      INSERT INTO backend_entity_map(
        local_id, entity_type, remote_id, remote_version, updated_at
      ) VALUES (?, ?, ?, ?, ?)
      ON CONFLICT(local_id, entity_type) DO UPDATE SET
        remote_id = excluded.remote_id,
        remote_version = excluded.remote_version,
        updated_at = excluded.updated_at;
    ''', [
      localId,
      entityType,
      remoteId,
      remoteVersion,
      DateTime.now().toUtc().toIso8601String(),
    ]);
  }
}

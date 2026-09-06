import 'dart:convert';

import 'local_database.dart';

enum LocalSyncOperation { upload, download, delete, metadata }
enum LocalSyncStatus { pending, running, retry, done, failed }
enum ConflictResolution { keepLocal, keepRemote, keepBoth }

class LocalSyncItem {
  const LocalSyncItem({
    required this.id,
    required this.entityId,
    required this.provider,
    required this.operation,
    required this.payload,
    required this.status,
    required this.attempts,
    required this.createdAt,
    required this.updatedAt,
    this.nextRetryAt,
    this.lastError,
  });

  final String id;
  final String entityId;
  final String provider;
  final LocalSyncOperation operation;
  final Map<String, dynamic> payload;
  final LocalSyncStatus status;
  final int attempts;
  final DateTime? nextRetryAt;
  final String? lastError;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class LocalSyncConflict {
  const LocalSyncConflict({
    required this.id,
    required this.entityId,
    required this.provider,
    required this.localVersion,
    required this.remoteVersion,
    required this.localChecksum,
    required this.remoteChecksum,
    required this.createdAt,
    this.resolution,
    this.resolvedAt,
  });

  final String id;
  final String entityId;
  final String provider;
  final String? localVersion;
  final String? remoteVersion;
  final String? localChecksum;
  final String? remoteChecksum;
  final ConflictResolution? resolution;
  final DateTime createdAt;
  final DateTime? resolvedAt;
}

class LocalSyncStore {
  LocalSyncStore(this.db) {
    _ensureTables();
  }

  final LocalDatabase db;

  void _ensureTables() {
    db.database.execute('''
      CREATE TABLE IF NOT EXISTS local_sync_queue (
        id TEXT PRIMARY KEY,
        entity_id TEXT NOT NULL,
        provider TEXT NOT NULL,
        operation TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        status TEXT NOT NULL,
        attempts INTEGER NOT NULL DEFAULT 0,
        next_retry_at TEXT,
        last_error TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      );
    ''');
    db.database.execute('''
      CREATE INDEX IF NOT EXISTS local_sync_queue_ready_idx
      ON local_sync_queue(status, next_retry_at, created_at);
    ''');
    db.database.execute('''
      CREATE TABLE IF NOT EXISTS local_sync_conflicts (
        id TEXT PRIMARY KEY,
        entity_id TEXT NOT NULL,
        provider TEXT NOT NULL,
        local_version TEXT,
        remote_version TEXT,
        local_checksum TEXT,
        remote_checksum TEXT,
        resolution TEXT,
        resolved_at TEXT,
        created_at TEXT NOT NULL
      );
    ''');
  }

  Future<LocalSyncItem> enqueue({
    required String entityId,
    required String provider,
    required LocalSyncOperation operation,
    Map<String, dynamic> payload = const {},
  }) async {
    final now = DateTime.now().toUtc();
    final id = 'sync-${now.microsecondsSinceEpoch.toRadixString(36)}-${entityId.hashCode.toUnsigned(32).toRadixString(36)}';
    db.database.execute('''
      INSERT INTO local_sync_queue(
        id, entity_id, provider, operation, payload_json, status,
        attempts, created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, 'pending', 0, ?, ?);
    ''', [
      id,
      entityId,
      provider,
      operation.name,
      jsonEncode(payload),
      now.toIso8601String(),
      now.toIso8601String(),
    ]);
    return (await get(id))!;
  }

  Future<LocalSyncItem?> get(String id) async {
    final rows = db.database.select(
      'SELECT * FROM local_sync_queue WHERE id = ? LIMIT 1;',
      [id],
    );
    return rows.isEmpty ? null : _itemFromRow(rows.first);
  }

  Future<List<LocalSyncItem>> ready({int limit = 25, DateTime? now}) async {
    final instant = (now ?? DateTime.now().toUtc()).toIso8601String();
    final rows = db.database.select('''
      SELECT * FROM local_sync_queue
      WHERE status IN ('pending', 'retry')
        AND (next_retry_at IS NULL OR next_retry_at <= ?)
      ORDER BY created_at ASC
      LIMIT ?;
    ''', [instant, limit]);
    return rows.map(_itemFromRow).toList(growable: false);
  }

  Future<List<LocalSyncItem>> list({int limit = 200}) async {
    final rows = db.database.select('''
      SELECT * FROM local_sync_queue ORDER BY created_at DESC LIMIT ?;
    ''', [limit]);
    return rows.map(_itemFromRow).toList(growable: false);
  }

  Future<void> markRunning(String id) async => _updateStatus(
        id,
        LocalSyncStatus.running,
      );

  Future<void> markDone(String id) async => _updateStatus(
        id,
        LocalSyncStatus.done,
        clearRetry: true,
      );

  Future<void> markFailed(
    String id,
    Object error, {
    required int maxAttempts,
    required Duration retryAfter,
  }) async {
    final current = await get(id);
    if (current == null) return;
    final attempts = current.attempts + 1;
    final terminal = attempts >= maxAttempts;
    final now = DateTime.now().toUtc();
    db.database.execute('''
      UPDATE local_sync_queue
      SET status = ?, attempts = ?, next_retry_at = ?, last_error = ?, updated_at = ?
      WHERE id = ?;
    ''', [
      terminal ? 'failed' : 'retry',
      attempts,
      terminal ? null : now.add(retryAfter).toIso8601String(),
      error.toString(),
      now.toIso8601String(),
      id,
    ]);
  }

  Future<void> retryNow(String id) async {
    final now = DateTime.now().toUtc().toIso8601String();
    db.database.execute('''
      UPDATE local_sync_queue
      SET status = 'pending', next_retry_at = NULL, last_error = NULL, updated_at = ?
      WHERE id = ?;
    ''', [now, id]);
  }

  Future<LocalSyncConflict> addConflict({
    required String entityId,
    required String provider,
    String? localVersion,
    String? remoteVersion,
    String? localChecksum,
    String? remoteChecksum,
  }) async {
    final now = DateTime.now().toUtc();
    final id = 'conflict-${now.microsecondsSinceEpoch.toRadixString(36)}';
    db.database.execute('''
      INSERT INTO local_sync_conflicts(
        id, entity_id, provider, local_version, remote_version,
        local_checksum, remote_checksum, created_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?);
    ''', [
      id,
      entityId,
      provider,
      localVersion,
      remoteVersion,
      localChecksum,
      remoteChecksum,
      now.toIso8601String(),
    ]);
    return (await listConflicts()).firstWhere((item) => item.id == id);
  }

  Future<List<LocalSyncConflict>> listConflicts({bool unresolvedOnly = false}) async {
    final rows = db.database.select('''
      SELECT * FROM local_sync_conflicts
      ${unresolvedOnly ? 'WHERE resolution IS NULL' : ''}
      ORDER BY created_at DESC;
    ''');
    return rows.map(_conflictFromRow).toList(growable: false);
  }

  Future<void> resolveConflict(String id, ConflictResolution resolution) async {
    db.database.execute('''
      UPDATE local_sync_conflicts
      SET resolution = ?, resolved_at = ? WHERE id = ?;
    ''', [
      resolution.name,
      DateTime.now().toUtc().toIso8601String(),
      id,
    ]);
  }

  Future<void> _updateStatus(
    String id,
    LocalSyncStatus status, {
    bool clearRetry = false,
  }) async {
    db.database.execute('''
      UPDATE local_sync_queue
      SET status = ?, next_retry_at = ${clearRetry ? 'NULL' : 'next_retry_at'},
          last_error = ${clearRetry ? 'NULL' : 'last_error'}, updated_at = ?
      WHERE id = ?;
    ''', [status.name, DateTime.now().toUtc().toIso8601String(), id]);
  }

  LocalSyncItem _itemFromRow(dynamic row) => LocalSyncItem(
        id: row['id'] as String,
        entityId: row['entity_id'] as String,
        provider: row['provider'] as String,
        operation: LocalSyncOperation.values.byName(row['operation'] as String),
        payload: (jsonDecode(row['payload_json'] as String) as Map)
            .cast<String, dynamic>(),
        status: LocalSyncStatus.values.byName(row['status'] as String),
        attempts: row['attempts'] as int,
        nextRetryAt: row['next_retry_at'] == null
            ? null
            : DateTime.parse(row['next_retry_at'] as String),
        lastError: row['last_error'] as String?,
        createdAt: DateTime.parse(row['created_at'] as String),
        updatedAt: DateTime.parse(row['updated_at'] as String),
      );

  LocalSyncConflict _conflictFromRow(dynamic row) => LocalSyncConflict(
        id: row['id'] as String,
        entityId: row['entity_id'] as String,
        provider: row['provider'] as String,
        localVersion: row['local_version'] as String?,
        remoteVersion: row['remote_version'] as String?,
        localChecksum: row['local_checksum'] as String?,
        remoteChecksum: row['remote_checksum'] as String?,
        resolution: row['resolution'] == null
            ? null
            : ConflictResolution.values.byName(row['resolution'] as String),
        createdAt: DateTime.parse(row['created_at'] as String),
        resolvedAt: row['resolved_at'] == null
            ? null
            : DateTime.parse(row['resolved_at'] as String),
      );
}

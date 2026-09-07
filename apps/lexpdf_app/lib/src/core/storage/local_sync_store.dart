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

class LocalSyncCheckpoint {
  const LocalSyncCheckpoint({
    required this.entityId,
    required this.provider,
    required this.localVersion,
    required this.localChecksum,
    required this.remoteVersion,
    required this.remoteChecksum,
    required this.syncedAt,
  });

  final String entityId;
  final String provider;
  final int localVersion;
  final String? localChecksum;
  final String? remoteVersion;
  final String? remoteChecksum;
  final DateTime syncedAt;
}

class LocalSyncBinding {
  const LocalSyncBinding({
    required this.entityId,
    required this.provider,
    required this.accountId,
  });

  final String entityId;
  final String provider;
  final String accountId;
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
    db.database.execute('''
      CREATE TABLE IF NOT EXISTS local_sync_checkpoints (
        entity_id TEXT NOT NULL,
        provider TEXT NOT NULL,
        local_version INTEGER NOT NULL,
        local_checksum TEXT,
        remote_version TEXT,
        remote_checksum TEXT,
        synced_at TEXT NOT NULL,
        PRIMARY KEY(entity_id, provider)
      );
    ''');
    db.database.execute('''
      CREATE TABLE IF NOT EXISTS local_sync_bindings (
        entity_id TEXT PRIMARY KEY,
        provider TEXT NOT NULL,
        account_id TEXT NOT NULL,
        updated_at TEXT NOT NULL
      );
    ''');
  }

  Future<LocalSyncItem> enqueue({
    required String entityId,
    required String provider,
    required LocalSyncOperation operation,
    Map<String, dynamic> payload = const {},
  }) async {
    final existing = db.database.select('''
      SELECT id FROM local_sync_queue
      WHERE entity_id = ? AND provider = ? AND operation = ?
        AND status IN ('pending', 'retry', 'running')
      ORDER BY created_at DESC LIMIT 1;
    ''', [entityId, provider, operation.name]);
    if (existing.isNotEmpty) {
      return (await get(existing.first['id'] as String))!;
    }

    final now = DateTime.now().toUtc();
    final id =
        'sync-${now.microsecondsSinceEpoch.toRadixString(36)}-${entityId.hashCode.toUnsigned(32).toRadixString(36)}';
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

  Future<void> recoverInterrupted() async {
    final now = DateTime.now().toUtc().toIso8601String();
    db.database.execute('''
      UPDATE local_sync_queue
      SET status = 'pending',
          last_error = 'Recovered after interrupted run',
          updated_at = ?
      WHERE status = 'running';
    ''', [now]);
  }

  Future<LocalSyncItem?> get(String id) async {
    final rows = db.database.select(
      'SELECT * FROM local_sync_queue WHERE id = ? LIMIT 1;',
      [id],
    );
    return rows.isEmpty ? null : _itemFromRow(rows.first);
  }

  Future<List<LocalSyncItem>> ready({
    int limit = 25,
    DateTime? now,
  }) async {
    final instant = (now ?? DateTime.now().toUtc()).toIso8601String();
    final rows = db.database.select('''
      SELECT * FROM local_sync_queue
      WHERE status IN ('pending', 'retry')
        AND (next_retry_at IS NULL OR next_retry_at <= ?)
      ORDER BY created_at ASC LIMIT ?;
    ''', [instant, limit]);
    return rows.map(_itemFromRow).toList(growable: false);
  }

  Future<List<LocalSyncItem>> list({int limit = 200}) async {
    final rows = db.database.select(
      'SELECT * FROM local_sync_queue ORDER BY created_at DESC LIMIT ?;',
      [limit],
    );
    return rows.map(_itemFromRow).toList(growable: false);
  }

  Future<void> markRunning(String id) =>
      _updateStatus(id, LocalSyncStatus.running);

  Future<void> markDone(String id) =>
      _updateStatus(id, LocalSyncStatus.done, clearRetry: true);

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
    final unresolved = db.database.select('''
      SELECT id FROM local_sync_conflicts
      WHERE entity_id = ? AND provider = ? AND resolution IS NULL
      LIMIT 1;
    ''', [entityId, provider]);
    if (unresolved.isNotEmpty) {
      return (await listConflicts())
          .firstWhere((item) => item.id == unresolved.first['id']);
    }
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

  Future<List<LocalSyncConflict>> listConflicts({
    bool unresolvedOnly = false,
  }) async {
    final rows = db.database.select('''
      SELECT * FROM local_sync_conflicts
      ${unresolvedOnly ? 'WHERE resolution IS NULL' : ''}
      ORDER BY created_at DESC;
    ''');
    return rows.map(_conflictFromRow).toList(growable: false);
  }

  Future<void> resolveConflict(
    String id,
    ConflictResolution resolution,
  ) async {
    db.database.execute('''
      UPDATE local_sync_conflicts
      SET resolution = ?, resolved_at = ?
      WHERE id = ?;
    ''', [
      resolution.name,
      DateTime.now().toUtc().toIso8601String(),
      id,
    ]);
  }

  Future<LocalSyncCheckpoint?> checkpoint(
    String entityId,
    String provider,
  ) async {
    final rows = db.database.select('''
      SELECT * FROM local_sync_checkpoints
      WHERE entity_id = ? AND provider = ? LIMIT 1;
    ''', [entityId, provider]);
    if (rows.isEmpty) return null;
    final row = rows.first;
    return LocalSyncCheckpoint(
      entityId: row['entity_id'] as String,
      provider: row['provider'] as String,
      localVersion: row['local_version'] as int,
      localChecksum: row['local_checksum'] as String?,
      remoteVersion: row['remote_version'] as String?,
      remoteChecksum: row['remote_checksum'] as String?,
      syncedAt: DateTime.parse(row['synced_at'] as String),
    );
  }

  Future<void> saveCheckpoint(LocalSyncCheckpoint value) async {
    db.database.execute('''
      INSERT INTO local_sync_checkpoints(
        entity_id, provider, local_version, local_checksum,
        remote_version, remote_checksum, synced_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(entity_id, provider) DO UPDATE SET
        local_version = excluded.local_version,
        local_checksum = excluded.local_checksum,
        remote_version = excluded.remote_version,
        remote_checksum = excluded.remote_checksum,
        synced_at = excluded.synced_at;
    ''', [
      value.entityId,
      value.provider,
      value.localVersion,
      value.localChecksum,
      value.remoteVersion,
      value.remoteChecksum,
      value.syncedAt.toUtc().toIso8601String(),
    ]);
  }

  Future<void> bindAccount({
    required String entityId,
    required String provider,
    required String accountId,
  }) async {
    final normalizedAccount = accountId.trim();
    if (normalizedAccount.isEmpty) {
      throw ArgumentError('accountId cannot be empty.');
    }
    final existing = await bindingFor(entityId);
    final changed = existing != null &&
        (existing.provider != provider || existing.accountId != normalizedAccount);
    final now = DateTime.now().toUtc().toIso8601String();

    db.database.execute('BEGIN IMMEDIATE;');
    try {
      if (changed) {
        // A document has exactly one managed-sync binding. When the user
        // moves it to another provider/account, all state derived from the
        // previous remote must be discarded so it cannot be compared with
        // or uploaded to the new account by mistake.
        db.database.execute(
          'DELETE FROM local_sync_checkpoints WHERE entity_id = ?;',
          [entityId],
        );
        db.database.execute('''
          DELETE FROM local_sync_queue
          WHERE entity_id = ? AND status IN ('pending', 'retry', 'running');
        ''', [entityId]);
        db.database.execute('''
          DELETE FROM local_sync_conflicts
          WHERE entity_id = ? AND resolution IS NULL;
        ''', [entityId]);
      }
      db.database.execute('''
        INSERT INTO local_sync_bindings(entity_id, provider, account_id, updated_at)
        VALUES (?, ?, ?, ?)
        ON CONFLICT(entity_id) DO UPDATE SET
          provider = excluded.provider,
          account_id = excluded.account_id,
          updated_at = excluded.updated_at;
      ''', [entityId, provider, normalizedAccount, now]);
      db.database.execute('COMMIT;');
    } catch (_) {
      db.database.execute('ROLLBACK;');
      rethrow;
    }
  }

  Future<LocalSyncBinding?> bindingFor(String entityId) async {
    final rows = db.database.select('''
      SELECT entity_id, provider, account_id
      FROM local_sync_bindings
      WHERE entity_id = ? LIMIT 1;
    ''', [entityId]);
    if (rows.isEmpty) return null;
    final row = rows.first;
    return LocalSyncBinding(
      entityId: row['entity_id'] as String,
      provider: row['provider'] as String,
      accountId: row['account_id'] as String,
    );
  }

  Future<List<LocalSyncBinding>> listBindings() async {
    final rows = db.database.select('''
      SELECT entity_id, provider, account_id
      FROM local_sync_bindings ORDER BY updated_at DESC;
    ''');
    return rows
        .map(
          (row) => LocalSyncBinding(
            entityId: row['entity_id'] as String,
            provider: row['provider'] as String,
            accountId: row['account_id'] as String,
          ),
        )
        .toList(growable: false);
  }

  Future<void> _updateStatus(
    String id,
    LocalSyncStatus status, {
    bool clearRetry = false,
  }) async {
    db.database.execute('''
      UPDATE local_sync_queue
      SET status = ?,
          next_retry_at = ${clearRetry ? 'NULL' : 'next_retry_at'},
          last_error = ${clearRetry ? 'NULL' : 'last_error'},
          updated_at = ?
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

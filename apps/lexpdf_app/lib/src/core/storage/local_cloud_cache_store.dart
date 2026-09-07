import 'dart:io';

import 'local_database.dart';

class CloudCacheEntry {
  const CloudCacheEntry({
    required this.documentId,
    required this.provider,
    required this.accountId,
    required this.localPath,
    required this.sizeBytes,
    required this.pinned,
    required this.lastAccessedAt,
  });

  final String documentId;
  final String provider;
  final String accountId;
  final String localPath;
  final int sizeBytes;
  final bool pinned;
  final DateTime lastAccessedAt;
}

class LocalCloudCacheStore {
  LocalCloudCacheStore(this.db) {
    db.database.execute('''
      CREATE TABLE IF NOT EXISTS cloud_cache_entries (
        document_id TEXT NOT NULL,
        provider TEXT NOT NULL,
        account_id TEXT NOT NULL,
        local_path TEXT NOT NULL,
        size_bytes INTEGER NOT NULL DEFAULT 0,
        pinned INTEGER NOT NULL DEFAULT 0 CHECK(pinned IN (0,1)),
        last_accessed_at TEXT NOT NULL,
        PRIMARY KEY(document_id, provider, account_id)
      );
    ''');
    db.database.execute('''
      CREATE INDEX IF NOT EXISTS cloud_cache_entries_lru_idx
      ON cloud_cache_entries(pinned, last_accessed_at);
    ''');
  }

  final LocalDatabase db;

  Future<void> upsert({
    required String documentId,
    required String provider,
    required String accountId,
    required String localPath,
    bool pinned = false,
  }) async {
    final file = File(localPath);
    final size = await file.exists() ? await file.length() : 0;
    db.database.execute('''
      INSERT INTO cloud_cache_entries(
        document_id, provider, account_id, local_path, size_bytes, pinned, last_accessed_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(document_id, provider, account_id) DO UPDATE SET
        local_path = excluded.local_path,
        size_bytes = excluded.size_bytes,
        pinned = MAX(cloud_cache_entries.pinned, excluded.pinned),
        last_accessed_at = excluded.last_accessed_at;
    ''', [
      documentId,
      provider,
      accountId,
      localPath,
      size,
      pinned ? 1 : 0,
      DateTime.now().toUtc().toIso8601String(),
    ]);
  }

  Future<void> touch(String documentId, String provider, String accountId) async {
    db.database.execute('''
      UPDATE cloud_cache_entries SET last_accessed_at = ?
      WHERE document_id = ? AND provider = ? AND account_id = ?;
    ''', [
      DateTime.now().toUtc().toIso8601String(),
      documentId,
      provider,
      accountId,
    ]);
  }

  Future<void> setPinned(
    String documentId,
    String provider,
    String accountId,
    bool pinned,
  ) async {
    db.database.execute('''
      UPDATE cloud_cache_entries SET pinned = ?
      WHERE document_id = ? AND provider = ? AND account_id = ?;
    ''', [pinned ? 1 : 0, documentId, provider, accountId]);
  }

  Future<List<CloudCacheEntry>> list() async {
    final rows = db.database.select('''
      SELECT * FROM cloud_cache_entries
      ORDER BY pinned DESC, last_accessed_at DESC;
    ''');
    return rows.map(_fromRow).toList(growable: false);
  }

  Future<int> totalBytes() async {
    final rows = db.database.select(
      'SELECT COALESCE(SUM(size_bytes), 0) AS total FROM cloud_cache_entries;',
    );
    return rows.first['total'] as int;
  }

  Future<int> evictToLimit(int maxBytes) async {
    if (maxBytes < 0) throw ArgumentError.value(maxBytes, 'maxBytes');
    var total = await totalBytes();
    var removed = 0;
    if (total <= maxBytes) return removed;
    final candidates = db.database.select('''
      SELECT * FROM cloud_cache_entries
      WHERE pinned = 0 ORDER BY last_accessed_at ASC;
    ''');
    for (final row in candidates) {
      if (total <= maxBytes) break;
      final entry = _fromRow(row);
      final file = File(entry.localPath);
      if (await file.exists()) await file.delete();
      db.database.execute('''
        DELETE FROM cloud_cache_entries
        WHERE document_id = ? AND provider = ? AND account_id = ?;
      ''', [entry.documentId, entry.provider, entry.accountId]);
      total -= entry.sizeBytes;
      removed++;
    }
    return removed;
  }

  Future<void> pruneMissingFiles() async {
    final entries = await list();
    for (final entry in entries) {
      if (!await File(entry.localPath).exists()) {
        db.database.execute('''
          DELETE FROM cloud_cache_entries
          WHERE document_id = ? AND provider = ? AND account_id = ?;
        ''', [entry.documentId, entry.provider, entry.accountId]);
      }
    }
  }

  CloudCacheEntry _fromRow(dynamic row) => CloudCacheEntry(
        documentId: row['document_id'] as String,
        provider: row['provider'] as String,
        accountId: row['account_id'] as String,
        localPath: row['local_path'] as String,
        sizeBytes: row['size_bytes'] as int,
        pinned: (row['pinned'] as int) == 1,
        lastAccessedAt: DateTime.parse(row['last_accessed_at'] as String),
      );
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lexpdf_app/src/core/storage/local_cloud_cache_store.dart';
import 'package:lexpdf_app/src/core/storage/local_database.dart';

void main() {
  test('evicts oldest unpinned files while preserving pinned cache', () async {
    final db = LocalDatabase.inMemory();
    addTearDown(db.close);
    final directory = await Directory.systemTemp.createTemp('lexpdf-cache-test');
    addTearDown(() => directory.delete(recursive: true));

    final first = File('${directory.path}/first.pdf');
    final second = File('${directory.path}/second.pdf');
    final pinned = File('${directory.path}/pinned.pdf');
    await first.writeAsBytes(List.filled(20, 1));
    await Future<void>.delayed(const Duration(milliseconds: 2));
    await second.writeAsBytes(List.filled(20, 2));
    await pinned.writeAsBytes(List.filled(20, 3));

    final store = LocalCloudCacheStore(db);
    await store.upsert(
      documentId: 'first',
      provider: 'google_drive',
      accountId: 'a',
      localPath: first.path,
    );
    await Future<void>.delayed(const Duration(milliseconds: 2));
    await store.upsert(
      documentId: 'second',
      provider: 'google_drive',
      accountId: 'a',
      localPath: second.path,
    );
    await store.upsert(
      documentId: 'pinned',
      provider: 'onedrive',
      accountId: 'b',
      localPath: pinned.path,
      pinned: true,
    );

    expect(await store.totalBytes(), 60);
    final removed = await store.evictToLimit(40);
    expect(removed, 1);
    expect(await first.exists(), isFalse);
    expect(await second.exists(), isTrue);
    expect(await pinned.exists(), isTrue);
    expect((await store.list()).any((entry) => entry.documentId == 'pinned' && entry.pinned), isTrue);
  });

  test('migrates legacy system-file cache identifiers', () async {
    final db = LocalDatabase.inMemory();
    addTearDown(db.close);
    const legacyProvider = 'i' 'cloud';
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
      INSERT INTO cloud_cache_entries(
        document_id, provider, account_id, local_path,
        size_bytes, pinned, last_accessed_at
      ) VALUES ('legacy', ?, 'file-provider', '/cache/legacy.pdf', 10, 1, ?);
    ''', [legacyProvider, DateTime.now().toUtc().toIso8601String()]);

    final store = LocalCloudCacheStore(db);
    final items = await store.list();
    expect(items, hasLength(1));
    expect(items.single.provider, 'system_file');
  });

  test('prunes cache metadata when file is missing', () async {
    final db = LocalDatabase.inMemory();
    addTearDown(db.close);
    final store = LocalCloudCacheStore(db);
    await store.upsert(
      documentId: 'missing',
      provider: 'r2',
      accountId: 'default',
      localPath: '/definitely/missing/lexpdf.pdf',
    );
    expect(await store.list(), hasLength(1));
    await store.pruneMissingFiles();
    expect(await store.list(), isEmpty);
  });
}

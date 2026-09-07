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

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lexxpdf_app/src/core/storage/local_database.dart';
import 'package:lexxpdf_app/src/core/storage/local_sync_store.dart';
import 'package:lexxpdf_app/src/core/sync/sync_engine.dart';

void main() {
  test('sync engine drains ready jobs and computes stable checksums', () async {
    final db = LocalDatabase.inMemory();
    addTearDown(db.close);
    final store = LocalSyncStore(db);
    await store.enqueue(
      entityId: 'doc-1',
      provider: 'test',
      operation: LocalSyncOperation.upload,
    );
    var calls = 0;
    final engine = SyncEngine(
      store: store,
      executors: {
        'test': (item) async {
          calls++;
          expect(item.entityId, 'doc-1');
        },
      },
    );
    expect(await engine.drain(), 1);
    expect(calls, 1);
    expect((await store.list()).single.status, LocalSyncStatus.done);

    final directory = await Directory.systemTemp.createTemp('lexpdf-sync-test');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/a.txt');
    await file.writeAsString('lexpdf');
    expect(await SyncEngine.sha256File(file.path), SyncEngine.sha256Bytes('lexpdf'.codeUnits));
    expect(
      SyncEngine.canonicalJsonChecksum({'b': 2, 'a': 1}),
      SyncEngine.canonicalJsonChecksum({'a': 1, 'b': 2}),
    );
  });
}

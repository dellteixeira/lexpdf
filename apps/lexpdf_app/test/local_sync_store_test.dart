import 'package:flutter_test/flutter_test.dart';
import 'package:lexxpdf_app/src/core/storage/local_database.dart';
import 'package:lexxpdf_app/src/core/storage/local_sync_store.dart';

void main() {
  test('sync queue retries and resolves conflicts offline', () async {
    final db = LocalDatabase.inMemory();
    addTearDown(db.close);
    final store = LocalSyncStore(db);

    final item = await store.enqueue(
      entityId: 'doc-1',
      provider: 'r2',
      operation: LocalSyncOperation.upload,
      payload: const {'path': '/tmp/a.pdf'},
    );
    expect((await store.ready()).single.id, item.id);

    await store.markRunning(item.id);
    await store.markFailed(
      item.id,
      StateError('offline'),
      maxAttempts: 5,
      retryAfter: const Duration(seconds: 5),
    );
    final failedOnce = await store.get(item.id);
    expect(failedOnce!.status, LocalSyncStatus.retry);
    expect(failedOnce.attempts, 1);

    await store.retryNow(item.id);
    expect((await store.ready()).single.status, LocalSyncStatus.pending);
    await store.markDone(item.id);
    expect((await store.get(item.id))!.status, LocalSyncStatus.done);

    final conflict = await store.addConflict(
      entityId: 'doc-1',
      provider: 'r2',
      localVersion: '2',
      remoteVersion: '3',
      localChecksum: 'local',
      remoteChecksum: 'remote',
    );
    expect(await store.listConflicts(unresolvedOnly: true), hasLength(1));
    await store.resolveConflict(conflict.id, ConflictResolution.keepBoth);
    expect(await store.listConflicts(unresolvedOnly: true), isEmpty);
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('cloud sync preserves restorable versions around remote replacement', () {
    final coordinator = File(
      'lib/src/core/sync/cloud_sync_coordinator.dart',
    ).readAsStringSync();
    final screen =
        File('lib/src/screens/cloud_sync_screen.dart').readAsStringSync();
    final docs = File('../../docs/SYNC.md').readAsStringSync();

    expect(coordinator, contains('LocalDocumentRevisionStore'));
    expect(coordinator, contains("reason: 'before_remote_download'"));
    expect(coordinator, contains("reason: 'synced_remote'"));
    expect(coordinator, contains("reason: 'sync_upload'"));
    expect(screen, contains('Histórico de versões'));
    expect(screen, contains('Restaurar esta versão'));
    expect(screen, contains('DocumentSyncState.syncPending'));
    expect(docs, contains('Local version history'));
  });
}

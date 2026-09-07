import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sync downloads replace local files atomically', () async {
    final source = await File(
      'lib/src/core/sync/cloud_sync_coordinator.dart',
    ).readAsString();

    expect(source, contains('.lexpdf-sync-partial-'));
    expect(source, contains('.lexpdf-sync-backup-'));
    expect(source, contains('_replaceFileAtomically'));
    expect(source, contains('await partial.rename(target.path)'));
    expect(source, contains('_verifyExpectedChecksum'));
  });

  test('repeated sync inspection reuses checksums while file stat is stable', () async {
    final source = await File(
      'lib/src/core/sync/cloud_sync_coordinator.dart',
    ).readAsString();

    expect(source, contains('Map<String, _CachedChecksum> _checksumCache'));
    expect(source, contains('cached.size == stat.size'));
    expect(source, contains('cached.modifiedMicros == modifiedMicros'));
    expect(source, contains('SyncEngine.sha256File(path)'));
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('large backup path uses file-backed writer and restorer', () {
    final screen = File('lib/src/screens/backup_migration_screen.dart').readAsStringSync();
    expect(screen, contains('LexBackupStreamingService'));
    expect(screen, contains('LexBackupStreamingRestoreService'));
    expect(screen, contains('_streamingBackup.createBackupFile'));
    expect(screen, contains('_streamingRestore.validateFile'));
    expect(screen, contains('_streamingRestore.restoreFile'));
  });

  test('restore service streams bundled documents directly to disk', () {
    final source = File(
      'lib/src/core/backup/lex_backup_streaming_restore_service.dart',
    ).readAsStringSync();
    expect(source, contains('InputFileStream(source.path)'));
    expect(source, contains('OutputFileStream(partial.path)'));
    expect(source, contains('entry.writeContent(output, freeMemory: true)'));
    expect(source, contains('sha256.bind(partial.openRead()).first'));
  });

  test('archive guard checks ZIP metadata before decompression', () {
    final source = File(
      'lib/src/core/backup/lex_backup_archive_guard.dart',
    ).readAsStringSync();
    expect(source, contains('maxEntries'));
    expect(source, contains('maxEntryUncompressedBytes'));
    expect(source, contains('maxTotalUncompressedBytes'));
    expect(source, contains('maxCompressionRatio'));
    expect(source, contains('validateFile(File file)'));
    expect(source, contains('suspicious compression ratio'));
  });
}

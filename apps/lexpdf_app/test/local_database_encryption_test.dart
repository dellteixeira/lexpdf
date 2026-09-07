import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lexpdf_app/src/core/storage/local_database.dart';
import 'package:lexpdf_app/src/core/storage/local_database_key_manager.dart';

void main() {
  const key =
      '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

  test('new persistent local database is encrypted at rest', () async {
    final directory = await Directory.systemTemp.createTemp('lexpdf-sqlcipher-');
    final path = '${directory.path}${Platform.pathSeparator}lexpdf.sqlite3';
    try {
      final database = LocalDatabase.openEncrypted(path, key);
      database.database.execute(
        "INSERT INTO app_metadata(key, value) VALUES ('secret-marker', 'private-value');",
      );
      database.close();

      expect(
        await LocalDatabaseKeyManager.hasPlaintextSqliteHeader(path),
        isFalse,
      );
      final bytes = await File(path).readAsBytes();
      final text = String.fromCharCodes(bytes);
      expect(text.contains('private-value'), isFalse);

      final reopened = LocalDatabase.openEncrypted(path, key);
      expect(
        reopened.database.select(
          "SELECT value FROM app_metadata WHERE key = 'secret-marker';",
        ).single['value'],
        'private-value',
      );
      reopened.close();
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test('legacy plaintext database migrates once without losing data', () async {
    final directory = await Directory.systemTemp.createTemp('lexpdf-plaintext-');
    final path = '${directory.path}${Platform.pathSeparator}lexpdf.sqlite3';
    try {
      final legacy = LocalDatabase.open(path);
      legacy.database.execute(
        "INSERT INTO app_metadata(key, value) VALUES ('legacy-marker', 'preserved');",
      );
      legacy.close();
      expect(
        await LocalDatabaseKeyManager.hasPlaintextSqliteHeader(path),
        isTrue,
      );

      final migrated = LocalDatabase.openEncrypted(path, key);
      expect(
        migrated.database.select(
          "SELECT value FROM app_metadata WHERE key = 'legacy-marker';",
        ).single['value'],
        'preserved',
      );
      migrated.close();
      expect(
        await LocalDatabaseKeyManager.hasPlaintextSqliteHeader(path),
        isFalse,
      );
      expect(File('$path.plaintext-backup').existsSync(), isFalse);
    } finally {
      await directory.delete(recursive: true);
    }
  });
}

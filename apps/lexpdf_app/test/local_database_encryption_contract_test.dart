import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('production startup requires the encrypted local database path', () {
    final mainSource = File('lib/main.dart').readAsStringSync();
    final databaseSource =
        File('lib/src/core/storage/local_database.dart').readAsStringSync();
    final keySource = File(
      'lib/src/core/storage/local_database_key_manager.dart',
    ).readAsStringSync();
    final pubspec = File('pubspec.yaml').readAsStringSync();

    expect(mainSource, contains('LocalDatabase.openEncrypted'));
    expect(mainSource, contains('LocalDatabaseKeyManager'));
    expect(databaseSource, contains('PRAGMA cipher_version'));
    expect(databaseSource, contains('PRAGMA cipher_memory_security = ON'));
    expect(databaseSource, contains("sqlcipher_export('encrypted')"));
    expect(keySource, contains('Random.secure()'));
    expect(keySource, contains('FlutterSecureStorage'));
    expect(pubspec, contains('sqlcipher_flutter_libs: 0.6.8'));
    expect(pubspec, isNot(contains('sqlite3_flutter_libs:')));
  });
}

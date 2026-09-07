import 'dart:io';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class LocalDatabaseKeyManager {
  const LocalDatabaseKeyManager({
    FlutterSecureStorage storage = const FlutterSecureStorage(),
  }) : _storage = storage;

  static const storageKey = 'lexpdf.local_database.key.v1';
  static const _sqliteHeader = <int>[
    0x53,
    0x51,
    0x4c,
    0x69,
    0x74,
    0x65,
    0x20,
    0x66,
    0x6f,
    0x72,
    0x6d,
    0x61,
    0x74,
    0x20,
    0x33,
    0x00,
  ];

  final FlutterSecureStorage _storage;

  Future<String> loadOrCreate(String databasePath) async {
    final stored = await _storage.read(key: storageKey);
    if (stored != null && _isValidKey(stored)) return stored;

    final file = File(databasePath);
    if (await file.exists() && await file.length() > 0) {
      final isPlaintext = await hasPlaintextSqliteHeader(databasePath);
      if (!isPlaintext) {
        throw StateError(
          'A chave do banco local criptografado não está disponível no armazenamento seguro.',
        );
      }
    }

    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    final key = bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();
    await _storage.write(key: storageKey, value: key);
    return key;
  }

  static Future<bool> hasPlaintextSqliteHeader(String path) async {
    final file = File(path);
    if (!await file.exists() || await file.length() < _sqliteHeader.length) {
      return false;
    }
    final handle = await file.open();
    try {
      final header = await handle.read(_sqliteHeader.length);
      if (header.length != _sqliteHeader.length) return false;
      for (var index = 0; index < _sqliteHeader.length; index++) {
        if (header[index] != _sqliteHeader[index]) return false;
      }
      return true;
    } finally {
      await handle.close();
    }
  }

  static bool _isValidKey(String value) {
    if (value.length != 64) return false;
    return RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(value);
  }
}

import 'dart:io';

import 'package:sqlcipher_flutter_libs/sqlcipher_flutter_libs.dart';
import 'package:sqlite3/open.dart';
import 'package:sqlite3/sqlite3.dart';

class LocalDatabase {
  LocalDatabase._(this.database) {
    _configure();
    _migrate();
  }

  final Database database;

  static bool _cipherPlatformConfigured = false;

  static void configureCipherPlatform() {
    if (_cipherPlatformConfigured) return;
    open.overrideFor(OperatingSystem.android, openCipherOnAndroid);
    _cipherPlatformConfigured = true;
  }

  factory LocalDatabase.open(String path) {
    return LocalDatabase._(sqlite3.open(path));
  }

  factory LocalDatabase.openEncrypted(String path, String keyHex) {
    configureCipherPlatform();
    _validateEncryptionKey(keyHex);
    _migratePlaintextDatabaseIfNeeded(path, keyHex);

    final db = sqlite3.open(path);
    try {
      _requireCipher(db);
      _applyKey(db, keyHex);
      db.select('SELECT count(*) FROM sqlite_master;');
      return LocalDatabase._(db);
    } catch (_) {
      db.dispose();
      rethrow;
    }
  }

  factory LocalDatabase.inMemory() {
    return LocalDatabase._(sqlite3.openInMemory());
  }

  static const int schemaVersion = 8;
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

  static void _validateEncryptionKey(String keyHex) {
    if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(keyHex)) {
      throw ArgumentError.value(
        keyHex,
        'keyHex',
        'A chave SQLCipher deve conter exatamente 32 bytes em hexadecimal.',
      );
    }
  }

  static void _requireCipher(Database db) {
    final rows = db.select('PRAGMA cipher_version;');
    if (rows.isEmpty || rows.first.values.first?.toString().trim().isEmpty != false) {
      throw StateError(
        'SQLCipher não está disponível; o LexPDF se recusa a abrir o banco local sem criptografia.',
      );
    }
  }

  static void _applyKey(Database db, String keyHex) {
    db.execute("PRAGMA key = \"x'$keyHex'\";");
    db.execute('PRAGMA cipher_memory_security = ON;');
  }

  static bool _hasPlaintextHeader(String path) {
    final file = File(path);
    if (!file.existsSync() || file.lengthSync() < _sqliteHeader.length) return false;
    final handle = file.openSync();
    try {
      final header = handle.readSync(_sqliteHeader.length);
      if (header.length != _sqliteHeader.length) return false;
      for (var index = 0; index < _sqliteHeader.length; index++) {
        if (header[index] != _sqliteHeader[index]) return false;
      }
      return true;
    } finally {
      handle.closeSync();
    }
  }

  static void _migratePlaintextDatabaseIfNeeded(String path, String keyHex) {
    final sourceFile = File(path);
    if (!sourceFile.existsSync() || sourceFile.lengthSync() == 0) return;
    if (!_hasPlaintextHeader(path)) return;

    final encryptedPath = '$path.sqlcipher-migration';
    final backupPath = '$path.plaintext-backup';
    final encryptedFile = File(encryptedPath);
    final backupFile = File(backupPath);
    if (encryptedFile.existsSync()) encryptedFile.deleteSync();
    if (backupFile.existsSync()) backupFile.deleteSync();

    final source = sqlite3.open(path);
    try {
      _requireCipher(source);
      source.execute('PRAGMA wal_checkpoint(TRUNCATE);');
      final escapedPath = encryptedPath.replaceAll("'", "''");
      source.execute(
        "ATTACH DATABASE '$escapedPath' AS encrypted KEY \"x'$keyHex'\";",
      );
      try {
        source.select("SELECT sqlcipher_export('encrypted');");
        source.execute('PRAGMA encrypted.user_version = ${source.userVersion};');
      } finally {
        source.execute('DETACH DATABASE encrypted;');
      }
    } catch (_) {
      if (encryptedFile.existsSync()) encryptedFile.deleteSync();
      rethrow;
    } finally {
      source.dispose();
    }

    final verification = sqlite3.open(encryptedPath);
    try {
      _requireCipher(verification);
      _applyKey(verification, keyHex);
      verification.select('SELECT count(*) FROM sqlite_master;');
    } finally {
      verification.dispose();
    }

    sourceFile.renameSync(backupPath);
    try {
      encryptedFile.renameSync(path);
      backupFile.deleteSync();
      final wal = File('$path-wal');
      final shm = File('$path-shm');
      if (wal.existsSync()) wal.deleteSync();
      if (shm.existsSync()) shm.deleteSync();
    } catch (_) {
      if (File(path).existsSync()) File(path).deleteSync();
      if (backupFile.existsSync()) backupFile.renameSync(path);
      rethrow;
    }
  }

  void _configure() {
    database.execute('PRAGMA foreign_keys = ON;');
    database.execute('PRAGMA journal_mode = WAL;');
    database.execute('PRAGMA synchronous = NORMAL;');
  }

  void _migrate() {
    var version = database.userVersion;
    if (version > schemaVersion) {
      throw StateError(
        'Banco local criado por uma versão mais nova do LexPDF: $version.',
      );
    }

    if (version == 0) {
      database.execute('BEGIN IMMEDIATE;');
      try {
        database.execute('''
          CREATE TABLE documents (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            filename TEXT NOT NULL,
            mime_type TEXT NOT NULL DEFAULT 'application/pdf',
            provider TEXT NOT NULL DEFAULT 'local',
            provider_file_id TEXT,
            local_path TEXT,
            remote_path TEXT,
            file_size INTEGER,
            page_count INTEGER,
            checksum TEXT,
            remote_version TEXT,
            local_version INTEGER NOT NULL DEFAULT 1,
            is_available_offline INTEGER NOT NULL DEFAULT 1,
            sync_status TEXT NOT NULL DEFAULT 'local_only',
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            last_opened_at TEXT
          );
        ''');
        database.execute('CREATE INDEX documents_updated_idx ON documents(updated_at DESC);');
        database.execute('CREATE INDEX documents_provider_idx ON documents(provider, provider_file_id);');
        database.execute('''
          CREATE TABLE reading_progress (
            document_id TEXT PRIMARY KEY REFERENCES documents(id) ON DELETE CASCADE,
            page_number INTEGER NOT NULL DEFAULT 1,
            zoom REAL NOT NULL DEFAULT 1.0,
            scroll_offset REAL NOT NULL DEFAULT 0,
            view_mode TEXT NOT NULL DEFAULT 'continuous',
            updated_at TEXT NOT NULL
          );
        ''');
        database.execute('CREATE TABLE app_metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL);');
        database.execute('INSERT INTO app_metadata(key, value) VALUES (?, ?);', ['schema_version', '1']);
        database.userVersion = 1;
        database.execute('COMMIT;');
        version = 1;
      } catch (_) {
        database.execute('ROLLBACK;');
        rethrow;
      }
    }

    if (version < 2) {
      database.execute('BEGIN IMMEDIATE;');
      try {
        database.execute('ALTER TABLE documents ADD COLUMN is_favorite INTEGER NOT NULL DEFAULT 0;');
        database.execute('CREATE INDEX documents_favorite_idx ON documents(is_favorite, COALESCE(last_opened_at, updated_at) DESC);');
        database.execute('UPDATE app_metadata SET value = ? WHERE key = ?;', ['2', 'schema_version']);
        database.userVersion = 2;
        database.execute('COMMIT;');
        version = 2;
      } catch (_) {
        database.execute('ROLLBACK;');
        rethrow;
      }
    }

    if (version < 3) {
      database.execute('BEGIN IMMEDIATE;');
      try {
        database.execute('''
          CREATE TABLE annotations (
            id TEXT PRIMARY KEY,
            document_id TEXT NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
            page_number INTEGER NOT NULL CHECK(page_number >= 1),
            start_index INTEGER NOT NULL CHECK(start_index >= 0),
            end_index INTEGER NOT NULL CHECK(end_index >= start_index),
            type TEXT NOT NULL CHECK(type IN ('highlight', 'underline', 'strikeout')),
            selected_text TEXT,
            color_value INTEGER NOT NULL,
            opacity REAL NOT NULL DEFAULT 1.0 CHECK(opacity >= 0 AND opacity <= 1),
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
          );
        ''');
        database.execute('CREATE INDEX annotations_document_page_idx ON annotations(document_id, page_number);');
        database.execute('UPDATE app_metadata SET value = ? WHERE key = ?;', ['3', 'schema_version']);
        database.userVersion = 3;
        database.execute('COMMIT;');
        version = 3;
      } catch (_) {
        database.execute('ROLLBACK;');
        rethrow;
      }
    }

    if (version < 4) {
      database.execute('BEGIN IMMEDIATE;');
      try {
        database.execute('''
          CREATE TABLE notebooks (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
          );
        ''');
        database.execute('''
          CREATE TABLE notebook_pages (
            id TEXT PRIMARY KEY,
            notebook_id TEXT NOT NULL REFERENCES notebooks(id) ON DELETE CASCADE,
            page_number INTEGER NOT NULL CHECK(page_number >= 1),
            width REAL NOT NULL DEFAULT 1080,
            height REAL NOT NULL DEFAULT 1440,
            background TEXT NOT NULL DEFAULT 'blank',
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            UNIQUE(notebook_id, page_number)
          );
        ''');
        database.execute('''
          CREATE TABLE ink_strokes (
            id TEXT PRIMARY KEY,
            page_id TEXT NOT NULL REFERENCES notebook_pages(id) ON DELETE CASCADE,
            tool TEXT NOT NULL CHECK(tool IN ('pen', 'pencil', 'highlighter')),
            color_value INTEGER NOT NULL,
            opacity REAL NOT NULL DEFAULT 1.0 CHECK(opacity >= 0 AND opacity <= 1),
            width REAL NOT NULL CHECK(width > 0),
            points_json TEXT NOT NULL,
            created_at TEXT NOT NULL
          );
        ''');
        database.execute('CREATE INDEX ink_strokes_page_idx ON ink_strokes(page_id, created_at);');
        database.execute('UPDATE app_metadata SET value = ? WHERE key = ?;', ['4', 'schema_version']);
        database.userVersion = 4;
        database.execute('COMMIT;');
        version = 4;
      } catch (_) {
        database.execute('ROLLBACK;');
        rethrow;
      }
    }

    if (version < 5) {
      database.execute('BEGIN IMMEDIATE;');
      try {
        database.execute('''
          CREATE TABLE pdf_ink_strokes (
            id TEXT PRIMARY KEY,
            document_id TEXT NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
            page_number INTEGER NOT NULL CHECK(page_number >= 1),
            tool TEXT NOT NULL CHECK(tool IN ('pen', 'pencil', 'highlighter')),
            color_value INTEGER NOT NULL,
            opacity REAL NOT NULL DEFAULT 1.0 CHECK(opacity >= 0 AND opacity <= 1),
            width REAL NOT NULL CHECK(width > 0),
            points_json TEXT NOT NULL,
            created_at TEXT NOT NULL
          );
        ''');
        database.execute('''
          CREATE INDEX pdf_ink_strokes_document_page_idx
          ON pdf_ink_strokes(document_id, page_number, created_at);
        ''');
        database.execute('UPDATE app_metadata SET value = ? WHERE key = ?;', ['5', 'schema_version']);
        database.userVersion = 5;
        database.execute('COMMIT;');
        version = 5;
      } catch (_) {
        database.execute('ROLLBACK;');
        rethrow;
      }
    }

    if (version < 6) {
      database.execute('BEGIN IMMEDIATE;');
      try {
        database.execute('''
          CREATE TABLE notebook_objects (
            id TEXT PRIMARY KEY,
            page_id TEXT NOT NULL REFERENCES notebook_pages(id) ON DELETE CASCADE,
            type TEXT NOT NULL CHECK(type IN ('line', 'arrow', 'rectangle', 'ellipse', 'triangle', 'text', 'image')),
            x REAL NOT NULL,
            y REAL NOT NULL,
            width REAL NOT NULL CHECK(width >= 0),
            height REAL NOT NULL CHECK(height >= 0),
            rotation REAL NOT NULL DEFAULT 0,
            color_value INTEGER NOT NULL DEFAULT 4278190080,
            fill_color_value INTEGER,
            stroke_width REAL NOT NULL DEFAULT 2 CHECK(stroke_width > 0),
            text_value TEXT,
            font_size REAL,
            image_path TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
          );
        ''');
        database.execute('''
          CREATE INDEX notebook_objects_page_idx
          ON notebook_objects(page_id, created_at);
        ''');
        database.execute('UPDATE app_metadata SET value = ? WHERE key = ?;', ['6', 'schema_version']);
        database.userVersion = 6;
        database.execute('COMMIT;');
        version = 6;
      } catch (_) {
        database.execute('ROLLBACK;');
        rethrow;
      }
    }

    if (version < 7) {
      database.execute('BEGIN IMMEDIATE;');
      try {
        database.execute('''
          CREATE TABLE pdf_annotation_objects (
            id TEXT PRIMARY KEY,
            document_id TEXT NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
            page_number INTEGER NOT NULL CHECK(page_number >= 1),
            type TEXT NOT NULL CHECK(type IN ('note', 'text', 'line', 'arrow', 'rectangle', 'ellipse', 'stamp', 'signature')),
            x REAL NOT NULL CHECK(x >= 0 AND x <= 1),
            y REAL NOT NULL CHECK(y >= 0 AND y <= 1),
            width REAL NOT NULL CHECK(width >= 0),
            height REAL NOT NULL CHECK(height >= 0),
            rotation REAL NOT NULL DEFAULT 0,
            color_value INTEGER NOT NULL,
            fill_color_value INTEGER,
            opacity REAL NOT NULL DEFAULT 1 CHECK(opacity >= 0 AND opacity <= 1),
            stroke_width REAL NOT NULL DEFAULT 2 CHECK(stroke_width > 0),
            text_value TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
          );
        ''');
        database.execute('''
          CREATE INDEX pdf_annotation_objects_document_page_idx
          ON pdf_annotation_objects(document_id, page_number, created_at);
        ''');
        database.execute('UPDATE app_metadata SET value = ? WHERE key = ?;', ['7', 'schema_version']);
        database.userVersion = 7;
        database.execute('COMMIT;');
        version = 7;
      } catch (_) {
        database.execute('ROLLBACK;');
        rethrow;
      }
    }

    if (version < 8) {
      database.execute('BEGIN IMMEDIATE;');
      try {
        database.execute('''
          CREATE TABLE notebook_layers (
            id TEXT PRIMARY KEY,
            page_id TEXT NOT NULL REFERENCES notebook_pages(id) ON DELETE CASCADE,
            name TEXT NOT NULL,
            sort_order INTEGER NOT NULL CHECK(sort_order >= 0),
            is_visible INTEGER NOT NULL DEFAULT 1 CHECK(is_visible IN (0, 1)),
            is_locked INTEGER NOT NULL DEFAULT 0 CHECK(is_locked IN (0, 1)),
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            UNIQUE(page_id, sort_order)
          );
        ''');
        database.execute('''
          CREATE INDEX notebook_layers_page_idx
          ON notebook_layers(page_id, sort_order);
        ''');
        database.execute('''
          CREATE TABLE notebook_layer_items (
            layer_id TEXT NOT NULL REFERENCES notebook_layers(id) ON DELETE CASCADE,
            item_type TEXT NOT NULL CHECK(item_type IN ('stroke', 'object')),
            item_id TEXT NOT NULL,
            created_at TEXT NOT NULL,
            PRIMARY KEY(item_type, item_id)
          );
        ''');
        database.execute('''
          CREATE INDEX notebook_layer_items_layer_idx
          ON notebook_layer_items(layer_id, item_type);
        ''');

        final now = DateTime.now().toUtc().toIso8601String();
        database.execute('''
          INSERT INTO notebook_layers(
            id, page_id, name, sort_order, is_visible, is_locked, created_at, updated_at
          )
          SELECT 'layer-' || id, id, 'Camada 1', 0, 1, 0, ?, ?
          FROM notebook_pages;
        ''', [now, now]);
        database.execute('''
          INSERT INTO notebook_layer_items(layer_id, item_type, item_id, created_at)
          SELECT 'layer-' || page_id, 'stroke', id, ? FROM ink_strokes;
        ''', [now]);
        database.execute('''
          INSERT INTO notebook_layer_items(layer_id, item_type, item_id, created_at)
          SELECT 'layer-' || page_id, 'object', id, ? FROM notebook_objects;
        ''', [now]);
        database.execute('''
          CREATE TRIGGER notebook_layer_items_cleanup_stroke
          AFTER DELETE ON ink_strokes
          BEGIN
            DELETE FROM notebook_layer_items
            WHERE item_type = 'stroke' AND item_id = OLD.id;
          END;
        ''');
        database.execute('''
          CREATE TRIGGER notebook_layer_items_cleanup_object
          AFTER DELETE ON notebook_objects
          BEGIN
            DELETE FROM notebook_layer_items
            WHERE item_type = 'object' AND item_id = OLD.id;
          END;
        ''');
        database.execute('UPDATE app_metadata SET value = ? WHERE key = ?;', ['8', 'schema_version']);
        database.userVersion = 8;
        database.execute('COMMIT;');
      } catch (_) {
        database.execute('ROLLBACK;');
        rethrow;
      }
    }
  }

  void close() => database.dispose();
}

import 'package:sqlite3/sqlite3.dart';

class LocalDatabase {
  LocalDatabase._(this.database) {
    _configure();
    _migrate();
  }

  final Database database;

  factory LocalDatabase.open(String path) {
    return LocalDatabase._(sqlite3.open(path));
  }

  factory LocalDatabase.inMemory() {
    return LocalDatabase._(sqlite3.openInMemory());
  }

  static const int schemaVersion = 1;

  void _configure() {
    database.execute('PRAGMA foreign_keys = ON;');
    database.execute('PRAGMA journal_mode = WAL;');
    database.execute('PRAGMA synchronous = NORMAL;');
  }

  void _migrate() {
    final version = database.userVersion;
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

        database.execute('''
          CREATE INDEX documents_updated_idx
          ON documents(updated_at DESC);
        ''');

        database.execute('''
          CREATE INDEX documents_provider_idx
          ON documents(provider, provider_file_id);
        ''');

        database.execute('''
          CREATE TABLE reading_progress (
            document_id TEXT PRIMARY KEY
              REFERENCES documents(id) ON DELETE CASCADE,
            page_number INTEGER NOT NULL DEFAULT 1,
            zoom REAL NOT NULL DEFAULT 1.0,
            scroll_offset REAL NOT NULL DEFAULT 0,
            view_mode TEXT NOT NULL DEFAULT 'continuous',
            updated_at TEXT NOT NULL
          );
        ''');

        database.execute('''
          CREATE TABLE app_metadata (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
          );
        ''');

        database.execute(
          'INSERT INTO app_metadata(key, value) VALUES (?, ?);',
          ['schema_version', schemaVersion.toString()],
        );
        database.userVersion = schemaVersion;
        database.execute('COMMIT;');
      } catch (_) {
        database.execute('ROLLBACK;');
        rethrow;
      }
    }
  }

  void close() => database.dispose();
}

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

  static const int schemaVersion = 7;

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
      } catch (_) {
        database.execute('ROLLBACK;');
        rethrow;
      }
    }
  }

  void close() => database.dispose();
}

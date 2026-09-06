import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';

import '../storage/local_database.dart';

class LexBackupValidation {
  const LexBackupValidation({
    required this.valid,
    required this.format,
    required this.version,
    required this.tableCount,
    required this.fileCount,
    this.error,
  });

  final bool valid;
  final String format;
  final int version;
  final int tableCount;
  final int fileCount;
  final String? error;
}

class LexBackupService {
  const LexBackupService(this.db);

  final LocalDatabase db;
  static const int formatVersion = 1;

  Future<Uint8List> createBackup() async {
    final snapshot = _snapshotDatabase();
    final databaseBytes = utf8.encode(jsonEncode(snapshot));
    final archive = Archive();
    archive.addFile(ArchiveFile.bytes('database.json', databaseBytes));

    final fileEntries = <Map<String, dynamic>>[];
    final documents = db.database.select(
      'SELECT id, local_path FROM documents WHERE local_path IS NOT NULL;',
    );
    for (final row in documents) {
      final path = row['local_path'] as String?;
      if (path == null) continue;
      final file = File(path);
      if (!await file.exists()) continue;
      final bytes = await file.readAsBytes();
      final archivePath = 'documents/${_safeName(row['id'].toString())}.pdf';
      archive.addFile(ArchiveFile.bytes(archivePath, bytes));
      fileEntries.add({
        'documentId': row['id'].toString(),
        'archivePath': archivePath,
        'checksum': sha256.convert(bytes).toString(),
        'size': bytes.length,
      });
    }

    final manifest = <String, dynamic>{
      'format': 'lexbackup',
      'version': formatVersion,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'databaseChecksum': sha256.convert(databaseBytes).toString(),
      'tables': (snapshot['tables'] as Map).keys.toList(),
      'files': fileEntries,
    };
    archive.addFile(
      ArchiveFile.bytes('manifest.json', utf8.encode(jsonEncode(manifest))),
    );
    return ZipEncoder().encodeBytes(archive);
  }

  Future<LexBackupValidation> validate(List<int> bytes) async {
    try {
      final archive = ZipDecoder().decodeBytes(bytes, verify: true);
      final manifestFile = archive.findFile('manifest.json');
      final databaseFile = archive.findFile('database.json');
      if (manifestFile == null || databaseFile == null) {
        return const LexBackupValidation(
          valid: false,
          format: 'unknown',
          version: 0,
          tableCount: 0,
          fileCount: 0,
          error: 'Manifest or database snapshot is missing.',
        );
      }
      final manifest = jsonDecode(utf8.decode(manifestFile.content)) as Map<String, dynamic>;
      final dbBytes = databaseFile.content;
      final expected = manifest['databaseChecksum']?.toString();
      final actual = sha256.convert(dbBytes).toString();
      if (manifest['format'] != 'lexbackup' || manifest['version'] != formatVersion) {
        return LexBackupValidation(
          valid: false,
          format: manifest['format']?.toString() ?? 'unknown',
          version: (manifest['version'] as num?)?.toInt() ?? 0,
          tableCount: 0,
          fileCount: 0,
          error: 'Unsupported backup format/version.',
        );
      }
      if (expected != actual) {
        return const LexBackupValidation(
          valid: false,
          format: 'lexbackup',
          version: formatVersion,
          tableCount: 0,
          fileCount: 0,
          error: 'Database snapshot checksum mismatch.',
        );
      }
      final snapshot = jsonDecode(utf8.decode(dbBytes)) as Map<String, dynamic>;
      final tables = (snapshot['tables'] as Map?) ?? const {};
      final files = (manifest['files'] as List?) ?? const [];
      for (final item in files) {
        final entry = (item as Map).cast<String, dynamic>();
        final file = archive.findFile(entry['archivePath'].toString());
        if (file == null || sha256.convert(file.content).toString() != entry['checksum']) {
          return const LexBackupValidation(
            valid: false,
            format: 'lexbackup',
            version: formatVersion,
            tableCount: 0,
            fileCount: 0,
            error: 'A bundled document is missing or corrupted.',
          );
        }
      }
      return LexBackupValidation(
        valid: true,
        format: 'lexbackup',
        version: formatVersion,
        tableCount: tables.length,
        fileCount: files.length,
      );
    } catch (error) {
      return LexBackupValidation(
        valid: false,
        format: 'unknown',
        version: 0,
        tableCount: 0,
        fileCount: 0,
        error: error.toString(),
      );
    }
  }

  Future<void> restore(
    List<int> bytes, {
    required Directory documentDirectory,
  }) async {
    final validation = await validate(bytes);
    if (!validation.valid) throw FormatException(validation.error ?? 'Invalid backup.');
    final archive = ZipDecoder().decodeBytes(bytes, verify: true);
    final manifest = jsonDecode(
      utf8.decode(archive.findFile('manifest.json')!.content),
    ) as Map<String, dynamic>;
    final snapshot = jsonDecode(
      utf8.decode(archive.findFile('database.json')!.content),
    ) as Map<String, dynamic>;
    final tables = (snapshot['tables'] as Map).cast<String, dynamic>();

    await documentDirectory.create(recursive: true);
    final restoredPaths = <String, String>{};
    for (final raw in (manifest['files'] as List? ?? const [])) {
      final item = (raw as Map).cast<String, dynamic>();
      final documentId = item['documentId'].toString();
      final archived = archive.findFile(item['archivePath'].toString())!;
      final target = File(
        '${documentDirectory.path}${Platform.pathSeparator}${_safeName(documentId)}.pdf',
      );
      await target.writeAsBytes(archived.content, flush: true);
      restoredPaths[documentId] = target.path;
    }

    db.database.execute('PRAGMA foreign_keys = OFF;');
    db.database.execute('BEGIN IMMEDIATE;');
    try {
      final existingTables = db.database
          .select("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' AND sql NOT LIKE 'CREATE VIRTUAL TABLE%';")
          .map((row) => row['name'] as String)
          .toSet();
      for (final table in tables.keys) {
        if (!existingTables.contains(table)) continue;
        db.database.execute('DELETE FROM ${_quote(table)};');
      }
      for (final entry in tables.entries) {
        final table = entry.key;
        if (!existingTables.contains(table)) continue;
        final rows = entry.value as List<dynamic>;
        for (final rawRow in rows) {
          final row = (rawRow as Map).cast<String, dynamic>();
          if (table == 'documents') {
            final id = row['id']?.toString();
            if (id != null && restoredPaths.containsKey(id)) {
              row['local_path'] = restoredPaths[id];
              row['is_available_offline'] = 1;
            }
          }
          if (row.isEmpty) continue;
          final columns = row.keys.toList(growable: false);
          final sql = 'INSERT INTO ${_quote(table)} (${columns.map(_quote).join(', ')}) VALUES (${List.filled(columns.length, '?').join(', ')});';
          db.database.execute(sql, [for (final column in columns) row[column]]);
        }
      }
      final violations = db.database.select('PRAGMA foreign_key_check;');
      if (violations.isNotEmpty) {
        throw StateError('Backup violates ${violations.length} foreign-key constraints.');
      }
      db.database.execute('COMMIT;');
    } catch (_) {
      db.database.execute('ROLLBACK;');
      rethrow;
    } finally {
      db.database.execute('PRAGMA foreign_keys = ON;');
    }
  }

  Uint8List exportNotebook(String notebookId) {
    final notebookRows = db.database.select('SELECT * FROM notebooks WHERE id = ?;', [notebookId]);
    if (notebookRows.isEmpty) throw StateError('Notebook not found.');
    final pages = db.database.select(
      'SELECT * FROM notebook_pages WHERE notebook_id = ? ORDER BY page_number;',
      [notebookId],
    );
    final pageIds = pages.map((row) => row['id'].toString()).toList();
    final strokes = <Map<String, dynamic>>[];
    final objects = <Map<String, dynamic>>[];
    for (final pageId in pageIds) {
      strokes.addAll(db.database.select('SELECT * FROM ink_strokes WHERE page_id = ?;', [pageId]).map(_rowToJson));
      final hasObjects = db.database.select("SELECT name FROM sqlite_master WHERE type='table' AND name='notebook_objects';").isNotEmpty;
      if (hasObjects) {
        objects.addAll(db.database.select('SELECT * FROM notebook_objects WHERE page_id = ?;', [pageId]).map(_rowToJson));
      }
    }
    final payload = {
      'format': 'lexnote',
      'version': 1,
      'notebook': _rowToJson(notebookRows.first),
      'pages': pages.map(_rowToJson).toList(),
      'strokes': strokes,
      'objects': objects,
    };
    return Uint8List.fromList(utf8.encode(jsonEncode(payload)));
  }

  Map<String, dynamic> _snapshotDatabase() {
    final tables = <String, dynamic>{};
    final names = db.database.select("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' AND sql NOT LIKE 'CREATE VIRTUAL TABLE%' ORDER BY name;");
    for (final row in names) {
      final name = row['name'] as String;
      tables[name] = db.database.select('SELECT * FROM ${_quote(name)};').map(_rowToJson).toList(growable: false);
    }
    return {
      'schemaVersion': LocalDatabase.schemaVersion,
      'tables': tables,
    };
  }

  static Map<String, dynamic> _rowToJson(dynamic row) {
    final result = <String, dynamic>{};
    for (final column in row.keys) {
      final value = row[column];
      result[column.toString()] = value is Uint8List ? {'\$blob': base64Encode(value)} : value;
    }
    return result;
  }

  static String _quote(String identifier) => '"${identifier.replaceAll('"', '""')}"';
  static String _safeName(String value) => value.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
}

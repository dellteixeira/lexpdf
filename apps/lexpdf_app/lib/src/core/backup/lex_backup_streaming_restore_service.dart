import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';

import '../storage/local_database.dart';
import 'lex_backup_archive_guard.dart';
import 'lex_backup_service.dart';

/// File-backed validator/restorer for large .lexbackup archives.
///
/// PDFs are decompressed directly to disk through [OutputFileStream]. Only the
/// bounded manifest and database snapshot are materialized in memory.
class LexBackupStreamingRestoreService {
  const LexBackupStreamingRestoreService(this.db);

  final LocalDatabase db;

  static const int formatVersion = 1;
  static const int maxManifestBytes = 16 * 1024 * 1024;
  static const int maxDatabaseSnapshotBytes = 256 * 1024 * 1024;

  Future<LexBackupValidation> validateFile(File source) async {
    try {
      await LexBackupArchiveGuard.validateFile(source);
      final input = InputFileStream(source.path);
      try {
        final archive = ZipDecoder().decodeStream(input, verify: true);
        final manifestFile = archive.findFile('manifest.json');
        final databaseFile = archive.findFile('database.json');
        if (manifestFile == null || databaseFile == null) {
          return _invalid('Manifest or database snapshot is missing.');
        }
        if (!manifestFile.isFile || manifestFile.size > maxManifestBytes) {
          return _invalid('Backup manifest exceeds the safety limit.');
        }
        if (!databaseFile.isFile || databaseFile.size > maxDatabaseSnapshotBytes) {
          return _invalid('Database snapshot exceeds the safety limit.');
        }

        final manifestBytes = manifestFile.readBytes();
        final databaseBytes = databaseFile.readBytes();
        if (manifestBytes == null || databaseBytes == null) {
          return _invalid('Backup metadata could not be decoded.');
        }
        final manifest = jsonDecode(utf8.decode(manifestBytes)) as Map<String, dynamic>;
        final version = (manifest['version'] as num?)?.toInt() ?? 0;
        if (manifest['format'] != 'lexbackup' || version != formatVersion) {
          return LexBackupValidation(
            valid: false,
            format: manifest['format']?.toString() ?? 'unknown',
            version: version,
            tableCount: 0,
            fileCount: 0,
            error: 'Unsupported backup format/version.',
          );
        }
        if (manifest['databaseChecksum']?.toString() != sha256.convert(databaseBytes).toString()) {
          return _invalid('Database snapshot checksum mismatch.', version: version);
        }

        final snapshot = jsonDecode(utf8.decode(databaseBytes)) as Map<String, dynamic>;
        final schemaVersion = (snapshot['schemaVersion'] as num?)?.toInt() ?? 0;
        if (schemaVersion < 1 || schemaVersion > LocalDatabase.schemaVersion) {
          return _invalid(
            'Backup database schema $schemaVersion is not supported by this LexPDF build.',
            version: version,
          );
        }
        final rawTables = snapshot['tables'];
        if (rawTables is! Map) {
          return _invalid('Database tables payload is invalid.', version: version);
        }
        final tables = rawTables.cast<String, dynamic>();
        for (final entry in tables.entries) {
          if (entry.value is! List) {
            return _invalid('Table ${entry.key} has an invalid row payload.', version: version);
          }
        }

        final files = (manifest['files'] as List?) ?? const [];
        if (files.length > LexBackupArchiveGuard.maxEntries - 2) {
          return _invalid('Backup contains too many bundled documents.', version: version);
        }
        final seen = <String>{};
        for (final raw in files) {
          if (raw is! Map) {
            return _invalid('Backup file manifest is invalid.', version: version);
          }
          final item = raw.cast<String, dynamic>();
          final path = item['archivePath']?.toString() ?? '';
          final expectedSize = (item['size'] as num?)?.toInt();
          final expectedChecksum = item['checksum']?.toString() ?? '';
          if (!_isSafeDocumentPath(path) || !seen.add(path)) {
            return _invalid('Unsafe or duplicate bundled document path.', version: version);
          }
          final entry = archive.findFile(path);
          if (entry == null ||
              !entry.isFile ||
              expectedSize == null ||
              expectedSize < 0 ||
              expectedSize != entry.size ||
              expectedSize > LexBackupArchiveGuard.maxEntryUncompressedBytes ||
              expectedChecksum.length != 64) {
            return _invalid('A bundled document is missing or invalid.', version: version);
          }
        }

        return LexBackupValidation(
          valid: true,
          format: 'lexbackup',
          version: version,
          tableCount: tables.length,
          fileCount: files.length,
        );
      } finally {
        input.closeSync();
      }
    } catch (error) {
      return _invalid(error.toString());
    }
  }

  Future<void> restoreFile(
    File source, {
    required Directory documentDirectory,
    bool Function()? isCancelled,
    void Function(int completed, int total)? onProgress,
  }) async {
    final validation = await validateFile(source);
    if (!validation.valid) {
      throw FormatException(validation.error ?? 'Invalid backup.');
    }
    await LexBackupArchiveGuard.validateFile(source);

    final input = InputFileStream(source.path);
    final createdFiles = <File>[];
    try {
      final archive = ZipDecoder().decodeStream(input, verify: true);
      final manifestEntry = archive.findFile('manifest.json')!;
      final databaseEntry = archive.findFile('database.json')!;
      final manifestBytes = manifestEntry.readBytes()!;
      final databaseBytes = databaseEntry.readBytes()!;
      final manifest = jsonDecode(utf8.decode(manifestBytes)) as Map<String, dynamic>;
      final snapshot = jsonDecode(utf8.decode(databaseBytes)) as Map<String, dynamic>;
      final tables = (snapshot['tables'] as Map).cast<String, dynamic>();
      final files = (manifest['files'] as List? ?? const []);

      await documentDirectory.create(recursive: true);
      final restoredPaths = <String, String>{};
      for (var index = 0; index < files.length; index++) {
        if (isCancelled?.call() == true) throw StateError('Restauração cancelada.');
        final item = (files[index] as Map).cast<String, dynamic>();
        final documentId = item['documentId'].toString();
        final archivePath = item['archivePath'].toString();
        final checksum = item['checksum'].toString();
        final expectedSize = (item['size'] as num).toInt();
        final entry = archive.findFile(archivePath)!;
        final target = File(
          '${documentDirectory.path}${Platform.pathSeparator}${_safeName(documentId)}-${checksum.substring(0, 12)}.pdf',
        );
        final partial = File('${target.path}.partial');
        if (await partial.exists()) await partial.delete();

        final output = OutputFileStream(partial.path);
        try {
          entry.writeContent(output, freeMemory: true);
        } finally {
          output.closeSync();
        }
        if (await partial.length() != expectedSize) {
          throw const FormatException('Restored document size mismatch.');
        }
        final actualChecksum = await sha256.bind(partial.openRead()).first;
        if (actualChecksum.toString() != checksum) {
          throw const FormatException('Restored document checksum mismatch.');
        }
        if (await target.exists()) await target.delete();
        await partial.rename(target.path);
        createdFiles.add(target);
        restoredPaths[documentId] = target.path;
        onProgress?.call(index + 1, files.length);
        if ((index + 1) % 4 == 0) await Future<void>.delayed(Duration.zero);
      }

      db.database.execute('PRAGMA foreign_keys = OFF;');
      db.database.execute('BEGIN IMMEDIATE;');
      try {
        final existingTables = db.database
            .select("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' AND sql NOT LIKE 'CREATE VIRTUAL TABLE%';")
            .map((row) => row['name'] as String)
            .toSet();
        for (final table in tables.keys) {
          if (existingTables.contains(table)) {
            db.database.execute('DELETE FROM ${_quote(table)};');
          }
        }
        for (final entry in tables.entries) {
          if (!existingTables.contains(entry.key)) continue;
          for (final rawRow in entry.value as List<dynamic>) {
            final row = (rawRow as Map).cast<String, dynamic>();
            if (entry.key == 'documents') {
              final id = row['id']?.toString();
              if (id != null && restoredPaths.containsKey(id)) {
                row['local_path'] = restoredPaths[id];
                row['is_available_offline'] = 1;
              }
            }
            _insertRow(entry.key, row);
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
    } catch (_) {
      for (final file in createdFiles.reversed) {
        if (await file.exists()) {
          try {
            await file.delete();
          } catch (_) {}
        }
      }
      rethrow;
    } finally {
      input.closeSync();
    }
  }

  void _insertRow(String table, Map<String, dynamic> row) {
    if (row.isEmpty) return;
    final columns = row.keys.toList(growable: false);
    final values = [for (final column in columns) _fromJsonValue(row[column])];
    final sql = 'INSERT INTO ${_quote(table)} (${columns.map(_quote).join(', ')}) VALUES (${List.filled(columns.length, '?').join(', ')});';
    db.database.execute(sql, values);
  }

  static dynamic _fromJsonValue(dynamic value) {
    if (value is Map && value.length == 1 && value[r'$blob'] is String) {
      return Uint8List.fromList(base64Decode(value[r'$blob'] as String));
    }
    return value;
  }

  static bool _isSafeDocumentPath(String path) {
    if (!path.startsWith('documents/') || path.contains('..') || path.contains('\\') || path.startsWith('/')) {
      return false;
    }
    final segments = path.split('/');
    return segments.length == 2 && segments.last.isNotEmpty;
  }

  static LexBackupValidation _invalid(String error, {int version = 0}) => LexBackupValidation(
        valid: false,
        format: version == 0 ? 'unknown' : 'lexbackup',
        version: version,
        tableCount: 0,
        fileCount: 0,
        error: error,
      );

  static String _quote(String identifier) => '"${identifier.replaceAll('"', '""')}"';
  static String _safeName(String value) => value.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
}

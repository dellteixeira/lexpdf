import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';

import '../storage/local_database.dart';

/// File-based backup writer for very large libraries.
///
/// Unlike the legacy in-memory API, bundled PDFs are read by ZipFileEncoder
/// directly from disk and are never all resident in Dart heap at once.
class LexBackupStreamingService {
  const LexBackupStreamingService(this.db);

  final LocalDatabase db;

  static const int formatVersion = 1;
  static const int maxBundledDocuments = 10000;

  Future<File> createBackupFile(
    String outputPath, {
    bool Function()? isCancelled,
    void Function(int completed, int total)? onProgress,
  }) async {
    final destination = File(outputPath);
    await destination.parent.create(recursive: true);
    final tempDir = await Directory.systemTemp.createTemp('lexpdf-backup-stream-');
    final tempZip = File('${tempDir.path}${Platform.pathSeparator}backup.lexbackup');
    final databaseFile = File('${tempDir.path}${Platform.pathSeparator}database.json');
    final manifestFile = File('${tempDir.path}${Platform.pathSeparator}manifest.json');

    try {
      final snapshot = _snapshotDatabase();
      final databaseBytes = utf8.encode(jsonEncode(snapshot));
      await databaseFile.writeAsBytes(databaseBytes, flush: true);

      final rows = db.database.select(
        'SELECT id, local_path FROM documents WHERE local_path IS NOT NULL;',
      );
      if (rows.length > maxBundledDocuments) {
        throw StateError('Biblioteca excede o limite seguro de $maxBundledDocuments documentos por backup.');
      }

      final fileEntries = <Map<String, dynamic>>[];
      final available = <({String id, File file})>[];
      for (final row in rows) {
        final path = row['local_path'] as String?;
        if (path == null) continue;
        final file = File(path);
        if (!await file.exists()) continue;
        available.add((id: row['id'].toString(), file: file));
      }

      for (var index = 0; index < available.length; index++) {
        if (isCancelled?.call() == true) throw StateError('Backup cancelado.');
        final item = available[index];
        final archivePath = 'documents/${_safeName(item.id)}.pdf';
        final checksum = await sha256.bind(item.file.openRead()).first;
        final size = await item.file.length();
        fileEntries.add({
          'documentId': item.id,
          'archivePath': archivePath,
          'checksum': checksum.toString(),
          'size': size,
        });
        onProgress?.call(index + 1, available.length);
      }

      final manifest = <String, dynamic>{
        'format': 'lexbackup',
        'version': formatVersion,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
        'schemaVersion': LocalDatabase.schemaVersion,
        'databaseChecksum': sha256.convert(databaseBytes).toString(),
        'tables': (snapshot['tables'] as Map).keys.toList(),
        'files': fileEntries,
      };
      await manifestFile.writeAsString(jsonEncode(manifest), flush: true);

      final encoder = ZipFileEncoder();
      encoder.create(tempZip.path);
      try {
        await encoder.addFile(databaseFile, 'database.json');
        await encoder.addFile(manifestFile, 'manifest.json');
        for (var index = 0; index < available.length; index++) {
          if (isCancelled?.call() == true) throw StateError('Backup cancelado.');
          final item = available[index];
          await encoder.addFile(item.file, 'documents/${_safeName(item.id)}.pdf');
          if ((index + 1) % 8 == 0) await Future<void>.delayed(Duration.zero);
        }
      } finally {
        await encoder.close();
      }

      final partial = File('$outputPath.partial');
      if (await partial.exists()) await partial.delete();
      await tempZip.copy(partial.path);
      if (await destination.exists()) await destination.delete();
      await partial.rename(destination.path);
      return destination;
    } finally {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    }
  }

  Map<String, dynamic> _snapshotDatabase() {
    final tables = <String, dynamic>{};
    final names = db.database.select(
      "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' AND sql NOT LIKE 'CREATE VIRTUAL TABLE%' ORDER BY name;",
    );
    for (final row in names) {
      final name = row['name'] as String;
      tables[name] = db.database
          .select('SELECT * FROM ${_quote(name)};')
          .map(_rowToJson)
          .toList(growable: false);
    }
    return {'schemaVersion': LocalDatabase.schemaVersion, 'tables': tables};
  }

  static Map<String, dynamic> _rowToJson(dynamic row) {
    final result = <String, dynamic>{};
    for (final column in row.keys) {
      final value = row[column];
      result[column.toString()] = value is Uint8List
          ? {'\$blob': base64Encode(value)}
          : value;
    }
    return result;
  }

  static String _quote(String identifier) =>
      '"${identifier.replaceAll('"', '""')}"';

  static String _safeName(String value) => value
      .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_')
      .replaceAll(RegExp(r'^\.+'), '_');
}

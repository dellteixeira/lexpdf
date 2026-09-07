import 'dart:io';

import 'package:archive/archive.dart';

class SquidImportResult {
  const SquidImportResult({
    required this.importedFiles,
    required this.warnings,
  });

  final List<String> importedFiles;
  final List<String> warnings;
}

class SquidImportService {
  const SquidImportService();

  static const int maxEmbeddedPdfs = 500;

  Future<SquidImportResult> importSafely(
    String sourcePath, {
    required Directory destination,
  }) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw FileSystemException('Squid source not found', sourcePath);
    }
    await destination.create(recursive: true);

    final lower = sourcePath.toLowerCase();
    if (lower.endsWith('.pdf')) {
      final target = await _uniqueTarget(destination, _basename(sourcePath));
      await source.copy(target.path);
      return SquidImportResult(
        importedFiles: [target.path],
        warnings: const [
          'Imported as flattened PDF; Squid editability is not available.',
        ],
      );
    }

    try {
      final archive = ZipDecoder().decodeBytes(await source.readAsBytes(), verify: true);
      final pdfEntries = archive.files
          .where((entry) => entry.isFile && entry.name.toLowerCase().endsWith('.pdf'))
          .take(maxEmbeddedPdfs + 1)
          .toList(growable: false);
      if (pdfEntries.length > maxEmbeddedPdfs) {
        throw const FormatException(
          'Squid container has too many embedded PDFs to import safely.',
        );
      }
      if (pdfEntries.isEmpty) {
        throw const FormatException(
          'No safely importable PDF payload was found. The source was left unchanged.',
        );
      }

      final imported = <String>[];
      final created = <File>[];
      try {
        for (final entry in pdfEntries) {
          final target = await _uniqueTarget(destination, _basename(entry.name));
          await target.writeAsBytes(entry.content, flush: true);
          created.add(target);
          imported.add(target.path);
        }
      } catch (_) {
        for (final file in created.reversed) {
          if (await file.exists()) {
            try {
              await file.delete();
            } catch (_) {}
          }
        }
        rethrow;
      }

      return SquidImportResult(
        importedFiles: imported,
        warnings: const [
          'Only embedded PDFs were imported. Proprietary Squid layers were not modified or guessed.',
        ],
      );
    } catch (error) {
      if (error is FormatException) rethrow;
      throw FormatException(
        'Unsupported Squid container. No data was changed: $error',
      );
    }
  }

  static Future<File> _uniqueTarget(Directory destination, String sourceName) async {
    final safe = _safeName(sourceName);
    final dot = safe.lastIndexOf('.');
    final stem = dot > 0 ? safe.substring(0, dot) : safe;
    final extension = dot > 0 ? safe.substring(dot) : '';
    var candidate = File('${destination.path}${Platform.pathSeparator}$safe');
    var counter = 2;
    while (await candidate.exists()) {
      candidate = File(
        '${destination.path}${Platform.pathSeparator}$stem ($counter)$extension',
      );
      counter++;
    }
    return candidate;
  }

  static String _basename(String path) => path.replaceAll('\\', '/').split('/').last;
  static String _safeName(String value) => value.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
}

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

  Future<SquidImportResult> importSafely(
    String sourcePath, {
    required Directory destination,
  }) async {
    final source = File(sourcePath);
    if (!await source.exists()) throw FileSystemException('Squid source not found', sourcePath);
    await destination.create(recursive: true);

    final lower = sourcePath.toLowerCase();
    if (lower.endsWith('.pdf')) {
      final target = await source.copy(
        '${destination.path}${Platform.pathSeparator}${_safeName(_basename(sourcePath))}',
      );
      return SquidImportResult(
        importedFiles: [target.path],
        warnings: const ['Imported as flattened PDF; Squid editability is not available.'],
      );
    }

    try {
      final archive = ZipDecoder().decodeBytes(await source.readAsBytes(), verify: true);
      final imported = <String>[];
      for (final entry in archive.files) {
        if (!entry.isFile || !entry.name.toLowerCase().endsWith('.pdf')) continue;
        final target = File(
          '${destination.path}${Platform.pathSeparator}${_safeName(_basename(entry.name))}',
        );
        await target.writeAsBytes(entry.content, flush: true);
        imported.add(target.path);
      }
      if (imported.isEmpty) {
        throw const FormatException(
          'No safely importable PDF payload was found. The source was left unchanged.',
        );
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

  static String _basename(String path) => path.replaceAll('\\', '/').split('/').last;
  static String _safeName(String value) => value.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
}

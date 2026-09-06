import 'dart:io';
import 'dart:typed_data';

import 'package:pdfrx/pdfrx.dart';

typedef PdfFileValidator = Future<void> Function(String path);

class SafePdfWriter {
  const SafePdfWriter({this.validator});

  final PdfFileValidator? validator;

  Future<String> saveAs({
    required Uint8List bytes,
    required String destinationPath,
    bool replaceExisting = false,
  }) async {
    if (bytes.isEmpty) throw ArgumentError('PDF bytes cannot be empty.');
    final destination = File(destinationPath);
    if (await destination.exists() && !replaceExisting) {
      throw StateError('Destination already exists. Use an explicit replace operation.');
    }

    final stamp = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final temp = File('$destinationPath.lexpdf-$stamp.tmp');
    File? backup;
    try {
      await temp.writeAsBytes(bytes, flush: true);
      await (validator ?? _validatePdf)(temp.path);

      if (await destination.exists()) {
        backup = File('$destinationPath.lexpdf-$stamp.bak');
        await destination.rename(backup.path);
      }
      await temp.rename(destinationPath);
      if (backup != null && await backup.exists()) {
        await backup.delete();
      }
      return destinationPath;
    } catch (_) {
      if (await temp.exists()) await temp.delete();
      if (backup != null && await backup.exists()) {
        if (await destination.exists()) await destination.delete();
        await backup.rename(destinationPath);
      }
      rethrow;
    }
  }

  static Future<void> _validatePdf(String path) async {
    final document = await PdfDocument.openFile(path);
    try {
      if (document.pages.isEmpty) {
        throw StateError('Generated PDF contains no pages.');
      }
    } finally {
      await document.dispose();
    }
  }
}

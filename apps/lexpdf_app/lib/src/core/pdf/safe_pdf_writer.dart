import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:pdfrx/pdfrx.dart';

typedef PdfFileValidator = Future<void> Function(String path);

class SafePdfWriter {
  const SafePdfWriter({this.validator});

  final PdfFileValidator? validator;

  String recoveryJournalPath(String destinationPath) =>
      '$destinationPath.lexpdf-recovery.json';

  Future<bool> recoverPending(String destinationPath) async {
    final journal = File(recoveryJournalPath(destinationPath));
    if (!await journal.exists()) return false;

    Map<String, dynamic> payload;
    try {
      payload = jsonDecode(await journal.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      await journal.delete();
      return false;
    }

    final destination = File(destinationPath);
    final tempPath = payload['tempPath'] as String?;
    final backupPath = payload['backupPath'] as String?;
    final temp = tempPath == null ? null : File(tempPath);
    final backup = backupPath == null ? null : File(backupPath);

    if (await destination.exists() && await _isValid(destination.path)) {
      if (temp != null && await temp.exists()) await temp.delete();
      if (backup != null && await backup.exists()) await backup.delete();
      await journal.delete();
      return true;
    }

    if (temp != null && await temp.exists() && await _isValid(temp.path)) {
      if (await destination.exists()) await destination.delete();
      await temp.rename(destinationPath);
      if (backup != null && await backup.exists()) await backup.delete();
      await journal.delete();
      return true;
    }

    if (backup != null && await backup.exists() && await _isValid(backup.path)) {
      if (await destination.exists()) await destination.delete();
      await backup.rename(destinationPath);
      if (temp != null && await temp.exists()) await temp.delete();
      await journal.delete();
      return true;
    }

    if (temp != null && await temp.exists()) await temp.delete();
    if (backup != null && await backup.exists()) await backup.delete();
    await journal.delete();
    return false;
  }

  Future<String> saveAs({
    required Uint8List bytes,
    required String destinationPath,
    bool replaceExisting = false,
  }) async {
    if (bytes.isEmpty) throw ArgumentError('PDF bytes cannot be empty.');
    await recoverPending(destinationPath);

    final destination = File(destinationPath);
    if (await destination.exists() && !replaceExisting) {
      throw StateError('Destination already exists. Use an explicit replace operation.');
    }

    final stamp = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final temp = File('$destinationPath.lexpdf-$stamp.tmp');
    File? backup;
    final journal = File(recoveryJournalPath(destinationPath));

    Future<void> writeJournal(String stage) async {
      await journal.writeAsString(
        jsonEncode({
          'version': 1,
          'stage': stage,
          'destinationPath': destinationPath,
          'tempPath': temp.path,
          'backupPath': backup?.path,
          'updatedAt': DateTime.now().toUtc().toIso8601String(),
        }),
        flush: true,
      );
    }

    try {
      await temp.writeAsBytes(bytes, flush: true);
      await (validator ?? _validatePdf)(temp.path);
      await writeJournal('temp_validated');

      if (await destination.exists()) {
        backup = File('$destinationPath.lexpdf-$stamp.bak');
        await writeJournal('before_backup');
        await destination.rename(backup.path);
        await writeJournal('backup_created');
      }

      await temp.rename(destinationPath);
      await writeJournal('destination_replaced');
      await (validator ?? _validatePdf)(destinationPath);

      if (backup != null && await backup.exists()) await backup.delete();
      if (await journal.exists()) await journal.delete();
      return destinationPath;
    } catch (_) {
      final recovered = await recoverPending(destinationPath);
      if (!recovered) {
        if (await temp.exists()) await temp.delete();
        if (backup != null && await backup.exists()) {
          if (await destination.exists()) await destination.delete();
          await backup.rename(destinationPath);
        }
        if (await journal.exists()) await journal.delete();
      }
      rethrow;
    }
  }

  Future<bool> _isValid(String path) async {
    try {
      await (validator ?? _validatePdf)(path);
      return true;
    } catch (_) {
      return false;
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

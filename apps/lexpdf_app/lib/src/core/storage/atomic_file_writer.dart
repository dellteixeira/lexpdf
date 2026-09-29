import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

typedef AtomicFileValidator = Future<void> Function(String path);

/// Crash-resilient replacement for user-owned files.
///
/// Temporary data and backups live beside the destination so replacement stays
/// on one filesystem. A recovery journal repairs an interrupted write before a
/// later save touches the same document again.
class AtomicFileWriter {
  const AtomicFileWriter();

  String recoveryJournalPath(String destinationPath) =>
      '$destinationPath.lexpdf-file-recovery.json';

  Future<bool> recoverPending(
    String destinationPath, {
    AtomicFileValidator? validator,
  }) async {
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

    if (await _isValid(destination, validator)) {
      await _deleteIfExists(temp);
      await _deleteIfExists(backup);
      await journal.delete();
      return true;
    }
    if (temp != null && await _isValid(temp, validator)) {
      await _deleteIfExists(destination);
      await temp.rename(destinationPath);
      await _deleteIfExists(backup);
      await journal.delete();
      return true;
    }
    if (backup != null && await _isValid(backup, validator)) {
      await _deleteIfExists(destination);
      await backup.rename(destinationPath);
      await _deleteIfExists(temp);
      await journal.delete();
      return true;
    }

    await _deleteIfExists(temp);
    await _deleteIfExists(backup);
    await _deleteIfExists(journal);
    return false;
  }

  Future<String> writeBytes({
    required List<int> bytes,
    required String destinationPath,
    bool replaceExisting = false,
    AtomicFileValidator? validator,
  }) async {
    final destination = File(destinationPath);
    await recoverPending(destinationPath, validator: validator);

    if (await destination.exists() && !replaceExisting) {
      throw StateError(
        'O destino já existe. A substituição precisa ser explícita.',
      );
    }

    final stamp = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final temp = File('$destinationPath.lexpdf-$stamp.tmp');
    File? backup;
    final journal = File(recoveryJournalPath(destinationPath));

    Future<void> writeJournal(String stage) async {
      await journal.writeAsString(
        jsonEncode(<String, Object?>{
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
      await temp.writeAsBytes(Uint8List.fromList(bytes), flush: true);
      if (validator != null) await validator(temp.path);
      await writeJournal('temp_validated');

      if (await destination.exists()) {
        backup = File('$destinationPath.lexpdf-$stamp.bak');
        await writeJournal('before_backup');
        await destination.rename(backup.path);
        await writeJournal('backup_created');
      }

      await temp.rename(destinationPath);
      await writeJournal('destination_replaced');
      if (validator != null) await validator(destinationPath);

      await _deleteIfExists(backup);
      await _deleteIfExists(journal);
      return destinationPath;
    } catch (_) {
      final recovered = await recoverPending(
        destinationPath,
        validator: validator,
      );
      if (!recovered) {
        await _deleteIfExists(temp);
        if (backup != null && await backup.exists()) {
          await _deleteIfExists(destination);
          await backup.rename(destinationPath);
        }
        await _deleteIfExists(journal);
      }
      rethrow;
    }
  }

  Future<bool> _isValid(
    File file,
    AtomicFileValidator? validator,
  ) async {
    if (!await file.exists()) return false;
    try {
      if (validator != null) await validator(file.path);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _deleteIfExists(File? file) async {
    if (file != null && await file.exists()) {
      await file.delete();
    }
  }
}

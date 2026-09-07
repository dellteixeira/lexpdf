import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lexxpdf_app/src/core/pdf/safe_pdf_writer.dart';

void main() {
  test('writes only after validation succeeds', () async {
    final directory = await Directory.systemTemp.createTemp('lexpdf-writer-');
    addTearDown(() => directory.delete(recursive: true));
    final target = File('${directory.path}${Platform.pathSeparator}out.pdf');
    var validated = false;
    final writer = SafePdfWriter(
      validator: (path) async {
        validated = true;
        expect(await File(path).readAsBytes(), [1, 2, 3]);
      },
    );

    await writer.saveAs(
      bytes: Uint8List.fromList([1, 2, 3]),
      destinationPath: target.path,
    );

    expect(validated, isTrue);
    expect(await target.readAsBytes(), [1, 2, 3]);
    expect(File(writer.recoveryJournalPath(target.path)).existsSync(), isFalse);
  });

  test('restores existing destination when validation fails', () async {
    final directory = await Directory.systemTemp.createTemp('lexpdf-writer-');
    addTearDown(() => directory.delete(recursive: true));
    final target = File('${directory.path}${Platform.pathSeparator}out.pdf');
    await target.writeAsBytes([9, 9, 9]);
    final writer = SafePdfWriter(
      validator: (path) async {
        final bytes = await File(path).readAsBytes();
        if (bytes.first == 1) throw StateError('invalid pdf');
      },
    );

    await expectLater(
      writer.saveAs(
        bytes: Uint8List.fromList([1, 2, 3]),
        destinationPath: target.path,
        replaceExisting: true,
      ),
      throwsStateError,
    );
    expect(await target.readAsBytes(), [9, 9, 9]);
    expect(
      directory.listSync().where((entry) => entry.path.endsWith('.tmp')),
      isEmpty,
    );
  });

  test('does not overwrite an existing file without explicit replace', () async {
    final directory = await Directory.systemTemp.createTemp('lexpdf-writer-');
    addTearDown(() => directory.delete(recursive: true));
    final target = File('${directory.path}${Platform.pathSeparator}out.pdf');
    await target.writeAsBytes([7]);
    final writer = SafePdfWriter(validator: (_) async {});

    await expectLater(
      writer.saveAs(
        bytes: Uint8List.fromList([1]),
        destinationPath: target.path,
      ),
      throwsStateError,
    );
    expect(await target.readAsBytes(), [7]);
  });

  test('recovers a validated temp file after an interrupted replacement', () async {
    final directory = await Directory.systemTemp.createTemp('lexpdf-recovery-');
    addTearDown(() => directory.delete(recursive: true));
    final target = File('${directory.path}${Platform.pathSeparator}out.pdf');
    final temp = File('${target.path}.lexpdf-temp.tmp');
    await temp.writeAsBytes([4, 5, 6]);
    final writer = SafePdfWriter(
      validator: (path) async {
        final bytes = await File(path).readAsBytes();
        if (bytes.isEmpty) throw StateError('invalid');
      },
    );
    final journal = File(writer.recoveryJournalPath(target.path));
    await journal.writeAsString(
      jsonEncode({
        'version': 1,
        'stage': 'backup_created',
        'destinationPath': target.path,
        'tempPath': temp.path,
        'backupPath': null,
      }),
    );

    expect(await writer.recoverPending(target.path), isTrue);
    expect(await target.readAsBytes(), [4, 5, 6]);
    expect(temp.existsSync(), isFalse);
    expect(journal.existsSync(), isFalse);
  });

  test('restores a valid backup when temp recovery is invalid', () async {
    final directory = await Directory.systemTemp.createTemp('lexpdf-recovery-');
    addTearDown(() => directory.delete(recursive: true));
    final target = File('${directory.path}${Platform.pathSeparator}out.pdf');
    final temp = File('${target.path}.lexpdf-temp.tmp');
    final backup = File('${target.path}.lexpdf-backup.bak');
    await temp.writeAsBytes([0]);
    await backup.writeAsBytes([8, 8]);
    final writer = SafePdfWriter(
      validator: (path) async {
        final bytes = await File(path).readAsBytes();
        if (bytes.isEmpty || bytes.first == 0) throw StateError('invalid');
      },
    );
    final journal = File(writer.recoveryJournalPath(target.path));
    await journal.writeAsString(
      jsonEncode({
        'version': 1,
        'stage': 'backup_created',
        'destinationPath': target.path,
        'tempPath': temp.path,
        'backupPath': backup.path,
      }),
    );

    expect(await writer.recoverPending(target.path), isTrue);
    expect(await target.readAsBytes(), [8, 8]);
    expect(temp.existsSync(), isFalse);
    expect(backup.existsSync(), isFalse);
    expect(journal.existsSync(), isFalse);
  });
}

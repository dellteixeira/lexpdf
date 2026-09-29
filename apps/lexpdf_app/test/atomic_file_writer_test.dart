import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lexpdf_app/src/core/storage/atomic_file_writer.dart';

void main() {
  test('atomic writer replaces a document without leaving recovery artifacts', () async {
    final dir = await Directory.systemTemp.createTemp('lexpdf-atomic-writer-');
    addTearDown(() => dir.delete(recursive: true));

    final path = '${dir.path}${Platform.pathSeparator}document.docx';
    final destination = File(path)..writeAsStringSync('OLD');
    const writer = AtomicFileWriter();

    await writer.writeBytes(
      bytes: const [0x50, 0x4B, 0x03, 0x04, 1, 2, 3],
      destinationPath: path,
      replaceExisting: true,
      validator: (candidate) async {
        final bytes = await File(candidate).readAsBytes();
        if (bytes.length < 2 || bytes[0] != 0x50 || bytes[1] != 0x4B) {
          throw StateError('invalid docx');
        }
      },
    );

    final bytes = await destination.readAsBytes();
    expect(bytes.take(2), orderedEquals(const [0x50, 0x4B]));
    expect(File(writer.recoveryJournalPath(path)).existsSync(), isFalse);
    expect(
      dir.listSync().whereType<File>().where((f) => f.path.endsWith('.bak')),
      isEmpty,
    );
  });

  test('validator failure preserves an existing destination', () async {
    final dir = await Directory.systemTemp.createTemp('lexpdf-atomic-failure-');
    addTearDown(() => dir.delete(recursive: true));

    final path = '${dir.path}${Platform.pathSeparator}document.pdf';
    final destination = File(path)..writeAsStringSync('ORIGINAL');
    const writer = AtomicFileWriter();

    await expectLater(
      writer.writeBytes(
        bytes: const [1, 2, 3],
        destinationPath: path,
        replaceExisting: true,
        validator: (_) async => throw StateError('invalid export'),
      ),
      throwsStateError,
    );

    expect(destination.readAsStringSync(), 'ORIGINAL');
  });
}

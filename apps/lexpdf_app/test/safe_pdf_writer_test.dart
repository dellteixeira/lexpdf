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
  });

  test('restores existing destination when validation fails', () async {
    final directory = await Directory.systemTemp.createTemp('lexpdf-writer-');
    addTearDown(() => directory.delete(recursive: true));
    final target = File('${directory.path}${Platform.pathSeparator}out.pdf');
    await target.writeAsBytes([9, 9, 9]);
    final writer = SafePdfWriter(
      validator: (_) async => throw StateError('invalid pdf'),
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
}

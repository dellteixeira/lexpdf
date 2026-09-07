import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lexpdf_app/src/core/documents/local_document_provider.dart';

void main() {
  test('lists only PDF files and resolves a local copy', () async {
    final temp = await Directory.systemTemp.createTemp('lexpdf_test_');
    addTearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });

    final pdf = File('${temp.path}${Platform.pathSeparator}sample.pdf');
    final text = File('${temp.path}${Platform.pathSeparator}ignore.txt');
    await pdf.writeAsBytes([0x25, 0x50, 0x44, 0x46]);
    await text.writeAsString('ignore');

    const provider = LocalDocumentProvider();
    final documents = await provider.list(parentId: temp.path);

    expect(documents, hasLength(1));
    expect(documents.single.name, 'sample.pdf');
    expect(documents.single.availableOffline, isTrue);
    expect(await provider.ensureLocalCopy(documents.single), pdf.path);
  });
}

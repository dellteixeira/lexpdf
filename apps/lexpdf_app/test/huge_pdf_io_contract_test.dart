import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('searchable export is chunked and uses bounded rendering', () async {
    final source = await File(
      'lib/src/core/ocr/searchable_pdf_exporter.dart',
    ).readAsString();
    expect(source, contains('pagesPerChunk = 16'));
    expect(source, contains('HugePdfPolicy.boundedRenderSize'));
    expect(source, contains('ocrStore.getPage'));
    expect(source, contains('createTemp(\'lexpdf-searchable-export-\')'));
    expect(source, isNot(contains('ocrStore.listForDocument(documentId)')));
  });

  test('page splitting writes each page directly to disk', () async {
    final source = await File(
      'lib/src/core/pdf/pdf_page_manipulation_service.dart',
    ).readAsString();
    expect(source, contains('splitEveryPageToDirectory'));
    expect(source, contains("await target.writeAsBytes(bytes, flush: true)"));
    expect(source, contains('Future<void>.delayed(Duration.zero)'));
  });

  test('huge backup creation streams PDFs through ZipFileEncoder', () async {
    final source = await File(
      'lib/src/core/backup/lex_backup_streaming_service.dart',
    ).readAsString();
    expect(source, contains('ZipFileEncoder'));
    expect(source, contains('item.file.openRead()'));
    expect(source, contains('await encoder.addFile(item.file'));
    expect(source, isNot(contains('item.file.readAsBytes()')));
  });
}

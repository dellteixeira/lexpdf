import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('searchable export preserves source PDF and appends OCR incrementally', () async {
    final exporter = await File(
      'lib/src/core/ocr/searchable_pdf_exporter.dart',
    ).readAsString();
    final source = await File(
      'lib/src/core/ocr/local_pdf_byte_source.dart',
    ).readAsString();

    expect(exporter, contains('exportToFile'));
    expect(exporter, contains('PdfDocument.openSource'));
    expect(exporter, contains('injectTextLayer'));
    expect(exporter, contains('saveTail()'));
    expect(exporter, contains('sourceFile.openRead().pipe'));
    expect(exporter, contains('FileMode.append'));
    expect(exporter, contains("result.engine == 'embedded-text'"));
    expect(exporter, isNot(contains('page.render(')));
    expect(exporter, isNot(contains('pw.Document')));
    expect(exporter, isNot(contains('encodeJpg')));
    expect(source, contains('implements PdfByteSource'));
    expect(source, contains('RandomAccessFile'));
    expect(source, contains('readRange'));
  });
}

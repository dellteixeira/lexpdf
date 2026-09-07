import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reader hydrates annotations and ink only around the viewport', () async {
    final reader = await File(
      'lib/src/screens/pdf_reader_screen.dart',
    ).readAsString();
    final annotations = await File(
      'lib/src/core/storage/local_text_annotation_store.dart',
    ).readAsString();
    final ink = await File(
      'lib/src/core/storage/local_pdf_ink_store.dart',
    ).readAsString();

    expect(reader, contains('HugePdfPolicy.overlayWindow'));
    expect(reader, contains('listForPageRange'));
    expect(reader, contains('_renderedAnnotations'));
    expect(reader, contains('_pdfInkByPage'));
    expect(reader, contains('removeWhere'));
    expect(reader, isNot(contains('widget.annotations.listForDocument(widget.document.id)')));
    expect(reader, isNot(contains('widget.pdfInkStore.listForDocument(widget.document.id)')));

    expect(annotations, contains('annotations_document_page_range_idx'));
    expect(ink, contains('pdf_ink_document_page_range_idx'));
  });
}

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

    final overlayStart = reader.indexOf('Future<void> _loadOverlayWindow');
    final overlayEnd = reader.indexOf('void _onPdfStrokeCompleted', overlayStart);
    expect(overlayStart, greaterThanOrEqualTo(0));
    expect(overlayEnd, greaterThan(overlayStart));
    final overlayLoader = reader.substring(overlayStart, overlayEnd);
    expect(
      overlayLoader,
      isNot(contains('widget.annotations.listForDocument(widget.document.id)')),
    );
    expect(
      overlayLoader,
      isNot(contains('widget.pdfInkStore.listForDocument(widget.document.id)')),
    );

    // A user-opened annotations panel may intentionally enumerate the complete
    // annotation list. The normal reader/viewport hydration above must not.
    expect(annotations, contains('annotations_document_page_range_idx'));
    expect(ink, contains('pdf_ink_document_page_range_idx'));
  });
}

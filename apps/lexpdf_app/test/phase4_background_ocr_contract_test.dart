import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('OCR remains bounded, resumable, cancellable and range-selective', () async {
    final source = await File(
      'lib/src/core/ocr/mobile_pdf_ocr_service.dart',
    ).readAsString();

    expect(source, contains('int startPage = 1'));
    expect(source, contains('int? endPage'));
    expect(source, contains('processedPageState'));
    expect(source, contains('isCancelled'));
    expect(source, contains('boundedRenderSize'));
    expect(source, contains('rendered.dispose()'));
    expect(source, contains('inspectTextAvailability'));
    expect(source, contains('maxSamplePages = 4'));
    expect(source, isNot(contains('listForDocument(documentId)')));
  });

  test('OCR page persistence updates PDF index and FTS incrementally', () async {
    final ocr = await File(
      'lib/src/core/ocr/mobile_pdf_ocr_service.dart',
    ).readAsString();
    final fts = await File(
      'lib/src/core/storage/local_global_search_fts.dart',
    ).readAsString();

    expect(ocr, contains('_upsertSearchIndex'));
    expect(ocr, contains('fts.upsertPdfPage'));
    expect(fts, contains('Future<void> upsertPdfPage'));
    expect(fts, contains('syncPdfTextOnly'));
    expect(fts, contains("WHERE kind = 'pdf_text' AND owner_id = ? AND page_number = ?"));
  });

  test('workspace offers nonblocking indexing and Ctrl+F uses indexed OCR text', () async {
    final source = await File(
      'lib/src/screens/pdf_workspace_screen.dart',
    ).readAsString();

    expect(source, contains('_inspectActiveDocumentForIndexing'));
    expect(source, contains('_startBackgroundIndexing'));
    expect(source, contains('unawaited(_startBackgroundIndexing'));
    expect(source, contains('hasCompleteDocumentIndex'));
    expect(source, contains('_autoIndexAttempted'));
    expect(source, isNot(contains("label: 'Indexar'")));
    expect(source, contains('cancelRequested'));
    expect(source, contains('LogicalKeyboardKey.keyF'));
    expect(source, contains('pdf_page_text_index'));
    expect(source, isNot(contains('_OcrProgressCard')));
    expect(source, isNot(contains('OCR preparando…')));
    expect(source, isNot(contains('OCR/indexação em segundo plano')));
    expect(source, contains('Silent by design'));
    expect(
      source,
      isNot(contains('task.progress = progress;\n          if (mounted) setState')),
    );
  });

  test('manual OCR screen exposes range, cancellation and resume-friendly processing', () async {
    final source = await File(
      'lib/src/screens/pdf_ocr_screen.dart',
    ).readAsString();

    expect(source, contains("labelText: 'Página inicial'"));
    expect(source, contains("labelText: 'Página final'"));
    expect(source, contains('isCancelled: () => _cancelRequested'));
    expect(source, contains("label: Text(_cancelRequested ? 'Cancelando…' : 'Cancelar')"));
  });
}

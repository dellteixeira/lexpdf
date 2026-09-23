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

  test('workspace defers full indexing on open and Ctrl+F can start it on demand', () async {
    final source = await File(
      'lib/src/screens/pdf_workspace_screen.dart',
    ).readAsString();

    expect(source, contains('_inspectActiveDocumentForIndexing'));
    expect(source, contains('_startBackgroundIndexing'));
    expect(source, contains('unawaited(_startBackgroundIndexing'));
    expect(source, contains('hasCompleteDocumentIndex'));
    expect(source, contains('_autoIndexInspected'));
    final inspectStart =
        source.indexOf('Future<void> _inspectActiveDocumentForIndexing');
    final backgroundStart =
        source.indexOf('Future<void> _startBackgroundIndexing', inspectStart);
    expect(inspectStart, greaterThanOrEqualTo(0));
    expect(backgroundStart, greaterThan(inspectStart));
    final inspectBody = source.substring(inspectStart, backgroundStart);
    expect(inspectBody, isNot(contains('_startBackgroundIndexing(')));
    expect(source, contains('_startLocalizedIndexing'));
    expect(source, contains('HugePdfPolicy.localizedIndexWindow'));
    expect(source, contains('startPage: window.start'));
    expect(source, contains('endPage: window.end'));
    expect(source, contains('currentPage = _tabs[_activeIndex].initialPage'));
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


  test('automatic open-time indexing is localized around the reading page', () async {
    final source = await File(
      'lib/src/screens/pdf_workspace_screen.dart',
    ).readAsString();

    final inspectStart =
        source.indexOf('Future<void> _inspectActiveDocumentForIndexing');
    final localizedStart =
        source.indexOf('Future<void> _startLocalizedIndexing', inspectStart);
    final backgroundStart =
        source.indexOf('Future<void> _startBackgroundIndexing', localizedStart);

    expect(inspectStart, greaterThanOrEqualTo(0));
    expect(localizedStart, greaterThan(inspectStart));
    expect(backgroundStart, greaterThan(localizedStart));

    final inspectBody = source.substring(inspectStart, localizedStart);
    expect(inspectBody, contains('_startLocalizedIndexing('));
    expect(inspectBody, isNot(contains('_startBackgroundIndexing(')));

    final localizedBody = source.substring(localizedStart, backgroundStart);
    expect(localizedBody, contains('startPage: window.start'));
    expect(localizedBody, contains('endPage: window.end'));
    expect(localizedBody, isNot(contains('endPage: pageCount')));
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

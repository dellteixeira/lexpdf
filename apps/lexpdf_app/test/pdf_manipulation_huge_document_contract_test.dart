import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('huge PDF manipulation stays disk-oriented and avoids full-document raster rebuilds', () async {
    final legacy = await File(
      'lib/src/core/pdf/pdf_page_manipulation_service.dart',
    ).readAsString();
    final large = await File(
      'lib/src/core/pdf/large_pdf_manipulation_service.dart',
    ).readAsString();
    final screen = await File(
      'lib/src/screens/pdf_page_tools_screen.dart',
    ).readAsString();

    expect(legacy, contains('splitEveryPageToDirectory'));
    expect(large, contains('composeToFile'));
    expect(large, contains('mergeToFile'));
    expect(large, contains('addBlankPageToFile'));
    expect(large, contains('imagesToPdfToFile'));
    expect(large, contains('insertImageOnPageToFile'));
    expect(large, contains('composeChunkPages = 32'));
    expect(large, contains('PdfEmbeddableImage.decode'));
    expect(large, contains('stampPage'));
    expect(large, contains('saveTail()'));
    expect(large, contains('FileMode.append'));
    expect(large, isNot(contains('page.render(')));
    expect(large, isNot(contains('pw.Document')));

    expect(screen, contains('composeToFile'));
    expect(screen, contains('mergeToFile'));
    expect(screen, contains('imagesToPdfToFile'));
    expect(screen, contains('addBlankPageToFile'));
    expect(screen, contains('insertImageOnPageToFile'));
    expect(screen, contains('splitEveryPageToDirectory'));
    expect(screen, isNot(contains('final outputs = await _service.splitEveryPage(source);')));
    expect(screen, isNot(contains('_service.compose(')));
    expect(screen, isNot(contains('_service.merge(')));
    expect(screen, isNot(contains('_service.imagesToPdf(')));
  });
}

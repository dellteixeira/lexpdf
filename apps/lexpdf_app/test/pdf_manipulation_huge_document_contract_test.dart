import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('huge PDF manipulation avoids catastrophic split and full-document raster insert', () async {
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
    expect(large, contains('insertImageOnPageToFile'));
    expect(large, contains('PdfEmbeddableImage.decode'));
    expect(large, contains('stampPage'));
    expect(large, contains('saveTail()'));
    expect(large, contains('FileMode.append'));
    expect(large, isNot(contains('page.render(')));

    expect(screen, contains('splitEveryPageToDirectory'));
    expect(screen, contains('LargePdfManipulationService'));
    expect(screen, isNot(contains('final outputs = await _service.splitEveryPage(source);')));
  });
}

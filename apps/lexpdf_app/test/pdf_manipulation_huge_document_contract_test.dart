import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('huge PDF manipulation avoids catastrophic split and full-document raster insert', () async {
    final service = await File(
      'lib/src/core/pdf/pdf_page_manipulation_service.dart',
    ).readAsString();
    final screen = await File(
      'lib/src/screens/pdf_page_tools_screen.dart',
    ).readAsString();

    expect(service, contains('splitEveryPageToDirectory'));
    expect(service, contains('insertImageOnPageToFile'));
    expect(service, contains('PdfEmbeddableImage.decode'));
    expect(service, contains('stampPage'));
    expect(service, contains('saveTail()'));
    expect(service, contains('FileMode.append'));
    expect(service, isNot(contains('for (final page in source.pages) {\n        final render = await page.render')));

    expect(screen, contains('splitEveryPageToDirectory'));
    expect(screen, isNot(contains('final outputs = await _service.splitEveryPage(source);')));
  });
}

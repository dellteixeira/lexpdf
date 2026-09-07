import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('huge-document OCR remains bounded and resumable', () async {
    final policy = await File('lib/src/core/pdf/huge_pdf_policy.dart').readAsString();
    final service = await File('lib/src/core/ocr/mobile_pdf_ocr_service.dart').readAsString();
    final store = await File('lib/src/core/storage/local_ocr_store.dart').readAsString();

    expect(policy, contains('ocrMaxPixels'));
    expect(policy, contains('ocrDesktopMaxPixels'));
    expect(policy, contains('ocrMaxDimension'));
    expect(policy, contains('ocrEmbeddedTextMinChars'));
    expect(service, contains('processedPageState'));
    expect(service, contains('loadStructuredText'));
    expect(service, contains("pageEngine = 'embedded-text'"));
    expect(service, contains('isCancelled?.call() == true'));
    expect(service, contains('rendered.dispose()'));
    expect(store, contains('SELECT page_number, length(trim(text)) AS has_text'));
    expect(store, isNot(contains('SELECT * FROM ocr_page_results\n      WHERE document_id = ? AND engine = ?')));
  });
}

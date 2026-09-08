import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lexpdf_app/src/core/pdf/huge_pdf_policy.dart';

void main() {
  test('reader preflights local PDFs and exposes render diagnostics', () {
    final reader = File('lib/src/screens/pdf_reader_screen.dart').readAsStringSync();

    expect(reader, contains("import '../core/pdf/pdf_file_preflight.dart';"));
    expect(reader, contains('PdfFilePreflight.inspectSync(path)'));
    expect(reader, contains("'Não foi possível abrir este PDF.'"));
    expect(reader, contains('[LexPDF][reader] viewer-ready'));
    expect(reader, contains('[LexPDF][reader] render-error'));
  });

  test('fast page changes debounce overlay hydration', () {
    final reader = File('lib/src/screens/pdf_reader_screen.dart').readAsStringSync();

    expect(
      HugePdfPolicy.overlayPageChangeDebounce,
      greaterThan(Duration.zero),
    );
    expect(
      HugePdfPolicy.overlayPageChangeDebounce,
      lessThan(const Duration(milliseconds: 250)),
    );
    expect(
      reader,
      contains('HugePdfPolicy.overlayPageChangeDebounce'),
    );
    expect(reader, contains('_deferredOverlayLoadTimer?.cancel();'));
  });
}

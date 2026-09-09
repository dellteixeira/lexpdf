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

  test('Windows preflight never performs synchronous filesystem I/O', () {
    final preflight = File(
      'lib/src/core/pdf/pdf_file_preflight.dart',
    ).readAsStringSync();

    final windowsGuard = preflight.indexOf('if (Platform.isWindows)');
    final windowsReady = preflight.indexOf(
      'PdfFilePreflightResult.ready(lengthBytes: 0)',
    );

    expect(windowsGuard, greaterThanOrEqualTo(0));
    expect(windowsReady, greaterThan(windowsGuard));

    for (final syncCall in [
      'file.existsSync()',
      'file.lengthSync()',
      'file.openSync()',
      'handle.readSync(',
    ]) {
      final index = preflight.indexOf(syncCall);
      expect(index, greaterThan(windowsReady), reason: syncCall);
    }
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

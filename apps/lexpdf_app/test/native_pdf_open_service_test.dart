import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lexpdf_app/src/core/documents/native_pdf_open_service.dart';

void main() {
  test('desktop launch arguments select the first PDF path', () {
    expect(
      NativePdfOpenService.pdfPathFromArgs(
        const ['--flag', r'C:\Users\User\Documents\sample.PDF', 'other.txt'],
      ),
      r'C:\Users\User\Documents\sample.PDF',
    );
    expect(
      NativePdfOpenService.pdfPathFromArgs(const ['--flag', 'notes.txt']),
      isNull,
    );
  });

  test('native open integration stays scoped to PDF intake', () {
    final service = File(
      'lib/src/core/documents/native_pdf_open_service.dart',
    ).readAsStringSync();
    final app = File('lib/src/lexpdf_app.dart').readAsStringSync();

    expect(service, contains("MethodChannel('lexpdf/native_pdf_open')"));
    expect(service, contains("call.method != 'openPdfPath'"));
    expect(service, contains("invokeMethod<String>('getInitialPdfPath')"));
    expect(app, contains('NativePdfOpenService _nativeOpen'));
    expect(app, contains('PdfWorkspaceScreen('));
    expect(app, contains('await _catalog.upsert(document)'));
    expect(app, contains('_catalog.markOpened(document.id)'));
    expect(app, isNot(contains('PdfReaderScreen(')));
  });
}

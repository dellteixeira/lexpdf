import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Windows compatibility layer detects and caches risky office PDFs', () {
    final service = File(
      'lib/src/core/pdf/windows_pdf_compat_normalizer.dart',
    ).readAsStringSync();

    expect(service, contains("MethodChannel('lexpdf/windows_pdf_compat')"));
    expect(service, contains('/StructTreeRoot'));
    expect(service, contains('/MarkInfo'));
    expect(service, contains('LibreOffice'));
    expect(service, contains('pdf_compat_normalized'));
    expect(service, contains('sha256.convert'));
    expect(service, contains('LEXPDF_FORCE_PDF_COMPAT_NORMALIZATION'));
    expect(service, contains('LEXPDF_DISABLE_PDF_COMPAT_NORMALIZATION'));
  });

  test('Windows native normalizer rebuilds pages instead of rasterizing them', () {
    final native = File(
      'windows/runner/windows_pdf_compat_normalizer.cpp',
    ).readAsStringSync();
    final flutterWindow =
        File('windows/runner/flutter_window.cpp').readAsStringSync();
    final cmake = File('windows/runner/CMakeLists.txt').readAsStringSync();

    expect(native, contains('FPDF_CreateNewDocument'));
    expect(native, contains('FPDF_ImportPages'));
    expect(native, contains('FPDF_SaveAsCopy'));
    expect(native, contains('kFpdfNoIncremental'));
    expect(native, isNot(contains('FPDF_RenderPageBitmap')));
    expect(native, isNot(contains('StretchDIBits')));
    expect(native, isNot(contains('RenderToStreamAsync')));
    expect(
      flutterWindow,
      contains('RegisterWindowsPdfCompatNormalizerChannel'),
    );
    expect(
      flutterWindow,
      contains('ShutdownWindowsPdfCompatNormalizerChannel'),
    );
    expect(cmake, contains('windows_pdf_compat_normalizer.cpp'));
  });

  test('workspace wrapper normalizes before opening the production viewer', () {
    final wrapper =
        File('lib/src/screens/pdf_workspace_screen.dart').readAsStringSync();

    expect(wrapper, contains('WindowsPdfCompatNormalizer'));
    expect(wrapper, contains("Text('Preparando PDF para renderização...')"));
    expect(wrapper, contains('widget.document.copyWith(localPath: result.path)'));
    expect(wrapper, contains('stylus.PdfWorkspaceScreen('));
    expect(wrapper, contains("'PDF compatível'"));
  });
}

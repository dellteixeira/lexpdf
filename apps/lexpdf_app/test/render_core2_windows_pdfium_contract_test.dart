import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Phase 4 Windows PDFium backend preserves native boundary contract', () {
    final dartBackend = File(
      'lib/src/core/pdf/render_core2_windows_pdfium_backend.dart',
    ).readAsStringSync();
    final nativeBridge = File(
      'windows/runner/render_core2_pdfium_channel.cpp',
    ).readAsStringSync();
    final flutterWindow = File(
      'windows/runner/flutter_window.cpp',
    ).readAsStringSync();
    final cmake = File('windows/runner/CMakeLists.txt').readAsStringSync();

    expect(dartBackend, contains('lexpdf/render_core2_pdfium'));
    expect(dartBackend, contains("'openDocument'"));
    expect(dartBackend, contains("'renderPage'"));
    expect(dartBackend, contains("'closeDocument'"));
    expect(dartBackend, contains("'pixelWidth': request.pixelWidth"));
    expect(dartBackend, contains("'pixelHeight': request.pixelHeight"));
    expect(dartBackend, contains('rowBytes < width * 4'));

    expect(nativeBridge, contains('LoadLibraryW(L"pdfium.dll")'));
    expect(nativeBridge, contains('FPDF_LoadDocument'));
    expect(nativeBridge, contains('FPDFBitmap_Create'));
    expect(nativeBridge, contains('FPDF_RenderPageBitmap'));
    expect(nativeBridge, contains('FPDFBitmap_GetBuffer'));
    expect(nativeBridge, contains('pdfium.dll is missing required PDFium exports'));

    // Phase 6 centralizes the physical-dimension guard in
    // ReadRenderArguments and passes width/height by pointer. Keep the Phase 4
    // contract focused on the invariant, not the previous local spelling.
    expect(nativeBridge, contains('ReadRenderArguments'));
    expect(nativeBridge, contains('*width > 32768 || *height > 32768'));
    expect(
      nativeBridge,
      contains('method == "renderPage" || method == "renderPageToTexture"'),
    );

    expect(flutterWindow, contains('RegisterRenderCore2PdfiumChannel'));
    expect(cmake, contains('render_core2_pdfium_channel.cpp'));
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('phase 5 diagnostic renders PDFium at physical dimensions exactly once', () {
    final diagnostic = File(
      'lib/render_core2_diagnostic_main.dart',
    ).readAsStringSync();
    final backend = File(
      'lib/src/core/pdf/render_core2_windows_pdfium_backend.dart',
    ).readAsStringSync();
    final native = File(
      'windows/runner/render_core2_pdfium_channel.cpp',
    ).readAsStringSync();

    expect(diagnostic, contains('info.widthPoints * viewerZoom'));
    expect(diagnostic, contains('(logicalWidth * dpr).ceil()'));
    expect(diagnostic, contains('(logicalHeight * dpr).ceil()'));
    expect(diagnostic, contains('filterQuality: FilterQuality.none'));
    expect(diagnostic, contains('LEXPDF_RENDER_CORE2_NATIVE_PROTOTYPE'));
    expect(diagnostic, isNot(contains('viewerZoom * dpr * viewerZoom')));

    expect(backend, contains("'getPageInfo'"));
    expect(backend, contains('widthPoints'));
    expect(backend, contains('heightPoints'));
    expect(native, contains('FPDF_GetPageWidth'));
    expect(native, contains('FPDF_GetPageHeight'));
    expect(native, contains('method == "getPageInfo"'));
  });
}

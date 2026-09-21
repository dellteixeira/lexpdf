import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Windows native PDF path has bounded cache cancellation and metrics', () {
    final native = File(
      'windows/runner/windows_native_pdf_surface.cpp',
    ).readAsStringSync();
    final dart = File(
      'lib/src/widgets/windows_native_pdf_surface.dart',
    ).readAsStringSync();

    expect(native, contains('NativePdfFrameCache'));
    expect(native, contains('128ull * 1024ull * 1024ull'));
    expect(native, contains('g_stale_discards'));
    expect(native, contains('"getDiagnostics"'));
    expect(native, contains('"clearRenderCache"'));
    expect(native, contains('SetDIBitsToDevice'));
    expect(native, isNot(contains('StretchDIBits')));
    expect(dart, contains('WindowsNativePdfDiagnostics'));
    expect(dart, contains('cacheHitRate'));
    expect(dart, contains('averageRenderMs'));
  });
}

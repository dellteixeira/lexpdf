import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android native reader bundles PDF.js and blocks runtime network access', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    final reader = File(
      'android/app/src/main/kotlin/com/lexpdf/lexpdf_app/NativePdfReaderActivity.kt',
    ).readAsStringSync();

    expect(gradle, contains('pdfjs-6.3.289-dist.zip'));
    expect(
      gradle,
      contains('98c5832ffe7af4edd59853476a478c0d4d4d76dd49c1701f4c86f7182725cdf9'),
    );
    expect(gradle, contains('build/pdf.min.mjs'));
    expect(gradle, contains('build/pdf.worker.min.mjs'));
    expect(gradle, contains('standard_fonts/'));
    expect(gradle, contains('wasm/'));
    expect(gradle, contains('dependsOn(preparePdfJsAssets)'));

    expect(reader, contains('PDFJS_MODULE_URL'));
    expect(reader, contains('PDFJS_WORKER_URL'));
    expect(reader, contains('PDFJS_STANDARD_FONTS_URL'));
    expect(reader, contains('PDFJS_WASM_URL'));
    expect(reader, contains('blockedNetworkResponse()'));
    expect(reader, contains('Content-Security-Policy'));
    expect(reader, isNot(contains('cdn.jsdelivr.net')));
  });

  test('Android reader keeps the protected 512 KB range transport unchanged', () {
    final reader = File(
      'android/app/src/main/kotlin/com/lexpdf/lexpdf_app/NativePdfReaderActivity.kt',
    ).readAsStringSync();

    expect(reader, contains('RANGE_CHUNK_SIZE = 512 * 1024'));
    expect(reader, contains('RandomAccessFile(sourceFile, "r")'));
    expect(reader, contains('disableStream: true'));
    expect(reader, contains('disableAutoFetch: true'));
    expect(reader, contains('disableRange: false'));
  });
}

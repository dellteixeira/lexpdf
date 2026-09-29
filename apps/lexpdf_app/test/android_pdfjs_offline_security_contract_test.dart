import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android native reader bundles PDF.js and blocks runtime network access', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    final reader = File(
      'android/app/src/main/kotlin/com/lexpdf/lexpdf_app/NativePdfReaderActivity.kt',
    ).readAsStringSync();

    expect(gradle, contains(r'pdfjs-dist-$pdfJsVersion.tgz'));
    expect(gradle, contains('val pdfJsVersion = "6.3.289"'));
    expect(
      gradle,
      contains(
        'ZHjSVpDa3D6izMq8/04lvkhkATUmL9px6ChPaXc1k6nU2Mrhlg1/7F0bdUqCwUjw3NsPTfPZsMDUU6ZIcRaeQw==',
      ),
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
    expect(
      reader,
      contains('Cache-Control" to "public, max-age=31536000, immutable"'),
    );
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

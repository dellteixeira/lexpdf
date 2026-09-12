import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('phase 6 keeps PDF page pixels on the native Texture path', () {
    final diagnostic = File(
      'lib/render_core2_diagnostic_main.dart',
    ).readAsStringSync();
    final backend = File(
      'lib/src/core/pdf/render_core2_windows_pdfium_backend.dart',
    ).readAsStringSync();
    final native = File(
      'windows/runner/render_core2_pdfium_channel.cpp',
    ).readAsStringSync();
    final window = File(
      'windows/runner/flutter_window.cpp',
    ).readAsStringSync();

    expect(diagnostic, contains('renderPageToTexture'));
    expect(diagnostic, contains('child: Texture('));
    expect(diagnostic, contains('filterQuality: FilterQuality.none'));
    expect(diagnostic, isNot(contains('RawImage(')));
    expect(diagnostic, isNot(contains('decodeImageFromPixels')));

    expect(backend, contains("'createTexture'"));
    expect(backend, contains("'renderPageToTexture'"));
    expect(backend, contains("'disposeTexture'"));

    expect(native, contains('flutter::PixelBufferTexture'));
    expect(native, contains('RegisterTexture'));
    expect(native, contains('MarkTextureFrameAvailable'));
    expect(native, contains('UnregisterTexture'));
    expect(native, contains('method == "renderPageToTexture"'));
    expect(native, contains('target[offset] = source[offset + 2]'));
    expect(native, contains('release_callback'));

    expect(window, contains('texture_registrar()'));
  });
}

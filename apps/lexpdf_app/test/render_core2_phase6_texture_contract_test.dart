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
    final windowHeader = File(
      'windows/runner/flutter_window.h',
    ).readAsStringSync();
    final cmake = File(
      'windows/runner/CMakeLists.txt',
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

    // FlutterEngine exposes a plugin registrar, while TextureRegistrar belongs
    // to the client-wrapper PluginRegistrar. Keep that wrapper alive with the
    // window so native texture callbacks never retain a dead registrar.
    expect(window, contains('GetRegistrarForPlugin("LexPDFRenderCore2")'));
    expect(window, contains('render_core2_registrar_->texture_registrar()'));
    expect(window, isNot(contains('engine()->texture_registrar()')));
    expect(windowHeader, contains('std::unique_ptr<flutter::PluginRegistrarWindows>'));

    // PluginRegistrarWindows is not header-only. Its constructor, destructor,
    // and ClearPlugins implementation are provided by flutter_wrapper_plugin.
    // Keep this link dependency explicit so Windows cannot regress to LNK2019.
    expect(cmake, contains('flutter_wrapper_plugin'));
  });
}

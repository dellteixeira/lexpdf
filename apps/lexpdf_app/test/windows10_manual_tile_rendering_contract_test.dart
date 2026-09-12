import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lexpdf_app/src/widgets/windows10_pdf_tile_overlay.dart';

void main() {
  test('Windows build parser distinguishes Windows 10 from Windows 11', () {
    expect(
      parseWindowsBuildNumber(
        'Microsoft Windows [Version 10.0.19045.4780]',
      ),
      19045,
    );
    expect(
      parseWindowsBuildNumber('Windows 11 Pro 10.0.22631'),
      22631,
    );
    expect(parseWindowsBuildNumber('OS Build 19045'), 19045);
    expect(parseWindowsBuildNumber('unknown version'), isNull);
  });

  test('Win10 workspace replaces the visible pdfrx raster with native Texture', () {
    final workspace = File(
      'lib/src/screens/pdf_workspace_stylus_screen.dart',
    ).readAsStringSync();
    final overlay = File(
      'lib/src/widgets/windows10_pdf_tile_overlay.dart',
    ).readAsStringSync();
    final native = File(
      'windows/runner/render_core2_production_pdfium_channel.cpp',
    ).readAsStringSync();
    final window = File(
      'windows/runner/flutter_window.cpp',
    ).readAsStringSync();
    final cmake = File('windows/runner/CMakeLists.txt').readAsStringSync();

    // Keep pdfrx only as the layout/navigation/text-selection substrate. Its
    // backing page remains low DPI and is hidden by the opaque native surface.
    expect(workspace, contains('isWindows10ManualTileRenderingEnabled()'));
    expect(workspace, contains('Windows10PdfTileOverlay('));
    expect(workspace, contains('if (_windows10Tiles) return 1.0;'));
    expect(workspace, contains('_SelectionMarkupOverlayPainter('));

    // The production visual path must never return to Dart pixel decoding or
    // RawImage bilinear resampling.
    expect(overlay, contains('lexpdf/render_core2_production_pdfium'));
    expect(overlay, contains("'ensureDocument'"));
    expect(overlay, contains("'renderPageToTexture'"));
    expect(overlay, contains('pageRectWidthLogical: pageRect.width'));
    expect(overlay, contains('devicePixelRatio: dpr'));
    expect(overlay, contains('child: ColoredBox('));
    expect(overlay, contains('Texture('));
    expect(overlay, contains('filterQuality: FilterQuality.none'));
    expect(overlay, contains('[LexPDF][RenderCore2][production]'));
    expect(overlay, isNot(contains('widget.page.render(')));
    expect(overlay, isNot(contains('decodeImageFromPixels')));
    expect(overlay, isNot(contains('RawImage(')));
    expect(overlay, isNot(contains('FilterQuality.low')));

    // Every visible page receives its own texture and PDFium renders screen
    // text with LCD/ClearType optimization at the exact physical target size.
    expect(native, contains('std::unordered_map<int64_t'));
    expect(native, contains('kFpdfLcdText = 0x02'));
    expect(native, contains('kFpdfAnnot | kFpdfLcdText'));
    expect(native, contains('flutter::PixelBufferTexture'));
    expect(native, contains('MarkTextureFrameAvailable'));
    expect(native, contains('textureKey'));
    expect(window, contains('RegisterRenderCore2ProductionPdfiumChannel'));
    expect(cmake, contains('render_core2_production_pdfium_channel.cpp'));
  });
}

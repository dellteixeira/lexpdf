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

  test('Win10 workspace uses hardened opaque native texture contract', () {
    final workspace = File(
      'lib/src/screens/pdf_workspace_stylus_screen.dart',
    ).readAsStringSync();
    final overlay = File(
      'lib/src/widgets/windows10_pdf_tile_overlay.dart',
    ).readAsStringSync();
    final native = File(
      'windows/runner/render_core2_production_pdfium_channel_v2.cpp',
    ).readAsStringSync();
    final window = File(
      'windows/runner/flutter_window.cpp',
    ).readAsStringSync();
    final cmake = File('windows/runner/CMakeLists.txt').readAsStringSync();

    expect(workspace, contains('isWindows10ManualTileRenderingEnabled()'));
    expect(workspace, contains('Windows10PdfTileOverlay('));
    expect(workspace, contains('if (_windows10Tiles) return 1.0;'));
    expect(workspace, contains('_SelectionMarkupOverlayPainter('));

    expect(overlay, contains('lexpdf/render_core2_production_pdfium'));
    expect(overlay, contains("'ensureDocument'"));
    expect(overlay, contains("'renderPageToTexture'"));
    expect(overlay, contains('pageRectWidthLogical: pageRect.width'));
    expect(overlay, contains('devicePixelRatio: dpr'));
    expect(overlay, contains('Texture('));
    expect(overlay, contains('filterQuality: FilterQuality.none'));
    expect(overlay, isNot(contains('widget.page.render(')));
    expect(overlay, isNot(contains('decodeImageFromPixels')));
    expect(overlay, isNot(contains('RawImage(')));

    // PDFium renders into an application-owned opaque BGRx buffer. The bridge
    // converts to tightly-packed opaque RGBA and returns the exact physical
    // size requested by Flutter's PixelBufferTexture callback.
    expect(native, contains('FPDFBitmap_CreateEx'));
    expect(native, contains('kFpdfBitmapBgrx = 3'));
    expect(native, contains('RenderOpaqueBgrx'));
    expect(native, contains('frame->rgba8888[offset + 3] = 0xFF'));
    expect(native, contains('requested_width != source->width'));
    expect(native, contains('requested_height != source->height'));
    expect(native, contains('ResizeNearest'));
    expect(native, contains('release_callback'));
    expect(native, contains('ProductionPixelBufferLease'));
    expect(native, contains('kFpdfAnnot | kFpdfLcdText'));
    expect(native, contains('flutter::PixelBufferTexture'));
    expect(native, contains('MarkTextureFrameAvailable'));
    expect(native, contains('textureKey'));

    expect(window, contains('RegisterRenderCore2ProductionPdfiumChannel'));
    expect(cmake, contains('render_core2_production_pdfium_channel_v2.cpp'));
    expect(cmake, isNot(contains('"render_core2_production_pdfium_channel.cpp"')));
  });
}

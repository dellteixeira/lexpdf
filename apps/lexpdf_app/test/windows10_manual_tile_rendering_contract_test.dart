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

  test('Win10 workspace uses one supersampled full-page raster', () {
    final workspace = File(
      'lib/src/screens/pdf_workspace_stylus_screen.dart',
    ).readAsStringSync();
    final overlay = File(
      'lib/src/widgets/windows10_pdf_tile_overlay.dart',
    ).readAsStringSync();

    expect(workspace, contains('isWindows10ManualTileRenderingEnabled()'));
    expect(workspace, contains('Windows10PdfTileOverlay('));
    expect(workspace, contains('if (_windows10Tiles) return 1.0;'));
    expect(workspace, contains('_SelectionMarkupOverlayPainter('));

    // The 7C path deliberately abandons the failed external texture bridge
    // and the old independently positioned tile composition.
    expect(overlay, contains('widget.page.render('));
    expect(overlay, contains('fullWidth: renderWidth.toDouble()'));
    expect(overlay, contains('fullHeight: renderHeight.toDouble()'));
    expect(overlay, contains('pageRectWidthLogical: pageRect.width'));
    expect(overlay, contains('devicePixelRatio: dpr'));
    expect(overlay, contains('ui.decodeImageFromPixels'));
    expect(overlay, contains('ui.PixelFormat.bgra8888'));
    expect(overlay, contains('RawImage('));
    expect(overlay, contains('filterQuality: FilterQuality.high'));
    expect(overlay, contains('RC2 fullpage'));
    expect(overlay, contains('if (longest <= 1800) return 2.0'));
    expect(overlay, contains('_maxRasterDimension = 8192'));

    expect(overlay, isNot(contains('MethodChannel(')));
    expect(overlay, isNot(contains('Texture(')));
    expect(overlay, isNot(contains('renderPageToTexture')));
    expect(overlay, isNot(contains('_TileKey')));
    expect(overlay, isNot(contains('_tilePixels')));
  });
}

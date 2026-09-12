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

  test('Win10 viewer uses manual sub-region tiles above a low-DPI backing page', () {
    final workspace = File(
      'lib/src/screens/pdf_workspace_stylus_screen.dart',
    ).readAsStringSync();
    final overlay = File(
      'lib/src/widgets/windows10_pdf_tile_overlay.dart',
    ).readAsStringSync();

    expect(workspace, contains('isWindows10ManualTileRenderingEnabled()'));
    expect(workspace, contains('Windows10PdfTileOverlay('));
    expect(workspace, contains('if (_windows10Tiles) return 1.0;'));
    expect(workspace, contains('onePassRenderingSizeThreshold: _windows10Tiles'));
    expect(workspace, contains('_SelectionMarkupOverlayPainter('));

    expect(overlay, contains('static const int _tilePixels = 768;'));
    expect(overlay, contains('widget.controller.visibleRect'));
    expect(overlay, contains('widget.page.render('));
    expect(overlay, contains('x: x'));
    expect(overlay, contains('y: y'));
    expect(overlay, contains('width: width'));
    expect(overlay, contains('height: height'));
    expect(overlay, contains('fullWidth: fullWidth.toDouble()'));
    expect(overlay, contains('fullHeight: fullHeight.toDouble()'));
    expect(overlay, contains('ui.PixelFormat.bgra8888'));
    expect(overlay, contains('FilterQuality.low'));
  });
}

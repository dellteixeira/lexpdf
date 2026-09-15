import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('mobile touch navigation and bounded Windows rendering stay wired', () {
    final overlay = File(
      'lib/src/widgets/pdf_stylus_page_overlay.dart',
    ).readAsStringSync();
    final workspace = File(
      'lib/src/screens/pdf_workspace_stylus_screen.dart',
    ).readAsStringSync();
    final router = File(
      'lib/src/widgets/pdf_android_finger_navigation_region.dart',
    ).readAsStringSync();

    // Ink belongs to S Pen/stylus. The overlay must not turn finger drags into
    // ink or install a competing pan recognizer.
    expect(overlay, contains('PointerDeviceKind.stylus'));
    expect(overlay, contains('PointerDeviceKind.invertedStylus'));
    expect(overlay, isNot(contains('PointerDeviceKind.touch')));
    expect(overlay, contains('HitTestBehavior.translucent'));
    expect(overlay, isNot(contains('onPanStart:')));
    expect(overlay, isNot(contains('onPanUpdate:')));
    expect(overlay, isNot(contains('onPanEnd:')));

    // Android finger navigation is now explicit and independent of the active
    // tool. pdfrx's internal Android pan/scale recognizers stay disabled so a
    // single owner applies one-finger pan and two-finger focal pinch exactly
    // once, including on the Galaxy Tab S6 Lite.
    expect(workspace, contains('PdfAndroidFingerNavigationRegion('));
    expect(workspace, contains('active: _android'));
    expect(workspace, contains('panAxis: PanAxis.free'));
    expect(workspace, contains('panEnabled:'));
    expect(workspace, contains('scaleEnabled:'));
    expect(workspace, contains('!_android &&'));

    expect(router, contains('PointerDeviceKind.touch'));
    expect(router, contains('PointerDeviceKind.stylus'));
    expect(router, contains('PointerDeviceKind.invertedStylus'));
    expect(router, contains('_applySingleFingerPan'));
    expect(router, contains('_applyTwoFingerPanAndZoom'));
    expect(router, contains('_palmBlockedTouches'));
    expect(router, contains('makeMatrixInSafeRange'));
    expect(router, contains('zoomOnLocalPosition'));

    expect(
      workspace,
      contains('onePassRenderingSizeThreshold: _windows10Tiles'),
    );
    expect(workspace, contains('? 1000'));
    expect(workspace, contains(': (_windows ? 6000 : 1400)'));
    expect(workspace, contains('getPageRenderingScale: _windows'));
    expect(workspace, contains('if (_windows10Tiles) return 1.0;'));
    expect(workspace, contains('const maxRenderPixels = 6000.0'));
    expect(workspace, contains('maxRenderPixels / page.width'));
    expect(workspace, contains('maxRenderPixels / page.height'));
    expect(workspace, contains('Windows10PdfTileOverlay('));
    expect(
      workspace,
      contains('enabled: _stylusMode == _StylusMode.selectText'),
    );
  });
}

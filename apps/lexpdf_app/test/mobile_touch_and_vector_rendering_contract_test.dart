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

    // Fingers belong to the PDF viewer on mobile; the ink overlay must only
    // consume stylus-like input and must not install a competing pan recognizer.
    expect(overlay, contains('PointerDeviceKind.stylus'));
    expect(overlay, contains('PointerDeviceKind.invertedStylus'));
    expect(overlay, isNot(contains('PointerDeviceKind.touch')));
    expect(overlay, contains('HitTestBehavior.translucent'));
    expect(overlay, isNot(contains('onPanStart:')));
    expect(overlay, isNot(contains('onPanUpdate:')));
    expect(overlay, isNot(contains('onPanEnd:')));

    // The viewer itself keeps touch navigation enabled on mobile regardless of
    // the currently selected annotation tool.
    expect(workspace, contains('panAxis: PanAxis.free'));
    expect(workspace, contains('panEnabled:'));
    expect(workspace, contains('scaleEnabled:'));
    expect(workspace, contains('_mobile ||'));

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

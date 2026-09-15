import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('PDF toolbar has a single zoom control group', () {
    final source = File('lib/src/screens/pdf_workspace_stylus_screen.dart')
        .readAsStringSync();

    final appBarStart = source.indexOf('appBar: AppBar(');
    final bodyStart = source.indexOf('body: CallbackShortcuts', appBarStart);
    expect(appBarStart, greaterThanOrEqualTo(0));
    expect(bodyStart, greaterThan(appBarStart));

    final appBar = source.substring(appBarStart, bodyStart);
    expect(appBar, isNot(contains('Icons.zoom_out')));
    expect(appBar, isNot(contains('Icons.zoom_in')));
    expect(appBar, isNot(contains('_buildZoomMenu')));
    expect(appBar, contains("Text('Pág. \$_page')"));

    final commandBarStart = source.indexOf('Widget _buildCommandBar');
    final stylusButtonStart = source.indexOf('Widget _stylusButton', commandBarStart);
    final commandBar = source.substring(commandBarStart, stylusButtonStart);
    expect(commandBar, contains('Icons.zoom_out'));
    expect(commandBar, contains('_buildZoomMenu()'));
    expect(commandBar, contains('Icons.zoom_in'));
  });

  test('Android PDF navigation is routed independently from every active tool', () {
    final workspace = File('lib/src/screens/pdf_workspace_stylus_screen.dart')
        .readAsStringSync();
    final overlay = File('lib/src/widgets/pdf_stylus_page_overlay.dart')
        .readAsStringSync();
    final router = File(
      'lib/src/widgets/pdf_android_finger_navigation_region.dart',
    ).readAsStringSync();

    expect(workspace, contains('PdfAndroidFingerNavigationRegion('));
    expect(workspace, contains('active: _android'));
    expect(workspace, contains('controller: _controller'));
    expect(workspace, contains('onNavigationEnd: _syncZoomFromController'));

    // Android no longer depends on pdfrx's internal gesture arena. The custom
    // router is the single owner of finger pan/pinch while the S Pen tool stays
    // selected. Other platforms retain the existing pdfrx gesture behavior.
    expect(workspace, contains('panEnabled:'));
    expect(workspace, contains('scaleEnabled:'));
    expect(workspace, contains('!_android &&'));

    expect(router, contains('PointerDeviceKind.touch'));
    expect(router, contains('PointerDeviceKind.stylus'));
    expect(router, contains('PointerDeviceKind.invertedStylus'));
    expect(router, contains('_applySingleFingerPan'));
    expect(router, contains('_applyTwoFingerPanAndZoom'));
    expect(router, contains('makeMatrixInSafeRange'));
    expect(router, contains('zoomOnLocalPosition'));
    expect(router, contains('_palmBlockedTouches'));

    // Finger input must never be converted into ink by the drawing overlay.
    expect(overlay, isNot(contains('_compactTouchDrawing')));
    expect(overlay, isNot(contains('PointerDeviceKind.touch')));
    expect(overlay, contains('PointerDeviceKind.stylus'));
    expect(overlay, contains('PointerDeviceKind.invertedStylus'));
  });
}

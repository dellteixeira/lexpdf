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

  test('Android input routing adapts between S Pen tablets and touch phones', () {
    final workspace = File('lib/src/screens/pdf_workspace_stylus_screen.dart')
        .readAsStringSync();
    final overlay = File('lib/src/widgets/pdf_stylus_page_overlay.dart')
        .readAsStringSync();
    final router = File(
      'lib/src/widgets/pdf_android_finger_navigation_region.dart',
    ).readAsStringSync();
    final policy = File(
      'lib/src/widgets/pdf_android_touch_input_policy.dart',
    ).readAsStringSync();

    expect(workspace, contains('PdfAndroidFingerNavigationRegion('));
    expect(workspace, contains('active: _android'));
    expect(workspace, contains('controller: _controller'));
    expect(workspace, contains('onNavigationEnd: _syncZoomFromController'));

    // Android does not depend on pdfrx's internal gesture arena. The custom
    // router owns finger navigation, while compact phones can temporarily give
    // one touch pointer to the ink overlay when a pen tool is active.
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
    expect(router, contains('beginMultiTouchNavigation'));

    expect(overlay, isNot(contains('_compactTouchDrawing')));
    expect(overlay, contains('PointerDeviceKind.touch'));
    expect(overlay, contains('PointerDeviceKind.stylus'));
    expect(overlay, contains('PointerDeviceKind.invertedStylus'));
    expect(overlay, contains('PdfAndroidTouchInputPolicy.compactPhoneInkActive'));
    expect(
      overlay,
      contains('PdfAndroidTouchInputPolicy.multiTouchNavigationActive'),
    );

    expect(policy, contains('compactPhoneShortestSide = 600'));
    expect(policy, contains('MediaQuery.sizeOf(context).shortestSide'));
    expect(policy, contains('TargetPlatform.android'));
  });
}

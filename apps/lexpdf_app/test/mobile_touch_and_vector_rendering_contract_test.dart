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
    final policy = File(
      'lib/src/widgets/pdf_android_touch_input_policy.dart',
    ).readAsStringSync();
    final normalizedWorkspace = workspace.replaceAll(RegExp(r'\s+'), ' ');

    // S Pen/stylus remains the primary ink source on tablets. Compact Android
    // phones may use one touch pointer as ink, while two fingers are promoted
    // to navigation for devices such as the Poco F5 that have no active pen.
    expect(overlay, contains('PointerDeviceKind.stylus'));
    expect(overlay, contains('PointerDeviceKind.invertedStylus'));
    expect(overlay, contains('PointerDeviceKind.touch'));
    expect(overlay, contains('PdfAndroidTouchInputPolicy.compactPhoneInkActive'));
    expect(
      overlay,
      contains('PdfAndroidTouchInputPolicy.multiTouchNavigationActive'),
    );
    expect(overlay, contains('HitTestBehavior.translucent'));
    expect(overlay, isNot(contains('onPanStart:')));
    expect(overlay, isNot(contains('onPanUpdate:')));
    expect(overlay, isNot(contains('onPanEnd:')));

    expect(policy, contains('compactPhoneShortestSide = 600'));
    expect(policy, contains('MediaQuery.sizeOf(context).shortestSide'));
    expect(policy, contains('TargetPlatform.android'));

    // Android finger navigation remains explicit and independent of pdfrx's
    // gesture arena. Tablets keep one-finger navigation; compact phones reserve
    // one finger for ink only while an ink tool is active and use two fingers
    // for pan/pinch.
    expect(workspace, contains('PdfAndroidFingerNavigationRegion('));
    expect(workspace, contains('active: _android && !_textSelectionOwnsGesture'));
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
    expect(router, contains('beginMultiTouchNavigation'));
    expect(router, contains('makeMatrixInSafeRange'));
    expect(router, contains('zoomOnLocalPosition'));

    expect(
      workspace,
      contains('onePassRenderingSizeThreshold: _windows10Tiles'),
    );
    expect(workspace, contains('? 1000'));
    expect(
      normalizedWorkspace,
      contains('HugePdfPolicy .androidOnePassRenderingSizeThreshold'),
    );
    expect(normalizedWorkspace, contains('getPageRenderingScale:'));
    expect(normalizedWorkspace, contains('if (_windows10Tiles) return 1.0;'));
    expect(normalizedWorkspace, contains('? 6000.0'));
    expect(
      normalizedWorkspace,
      contains('HugePdfPolicy.androidMaxRenderLongEdge'),
    );
    expect(workspace, contains('maxRenderPixels / page.width'));
    expect(workspace, contains('maxRenderPixels / page.height'));
    expect(workspace, contains('Windows10PdfTileOverlay('));
    expect(
      workspace,
      contains('enabled: _textSelectionEnabled'),
    );
  });
}

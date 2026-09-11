import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('compact Android touch tools and bounded Windows rendering stay wired', () {
    final overlay = File(
      'lib/src/widgets/pdf_stylus_page_overlay.dart',
    ).readAsStringSync();
    final workspace = File(
      'lib/src/screens/pdf_workspace_stylus_screen.dart',
    ).readAsStringSync();

    expect(overlay, contains('TargetPlatform.android'));
    expect(overlay, contains('size.shortestSide'));
    expect(overlay, contains('< 600'));
    expect(overlay, contains('onPanStart: _touchPanStart'));
    expect(overlay, contains('onPanUpdate: _touchPanUpdate'));
    expect(overlay, contains('onPanEnd: _touchPanEnd'));
    expect(overlay, contains('PointerDeviceKind.stylus'));

    expect(
      workspace,
      contains('onePassRenderingSizeThreshold: _windows ? 6000 : 1400'),
    );
    expect(workspace, contains('getPageRenderingScale: _windows'));
    expect(workspace, contains('const maxRenderPixels = 6000.0'));
    expect(workspace, contains('maxRenderPixels / page.width'));
    expect(workspace, contains('maxRenderPixels / page.height'));
    expect(
      workspace,
      contains('enabled: _stylusMode == _StylusMode.selectText'),
    );
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('PDF viewer keeps free pan and focal-point zoom on touch devices', () {
    final source = File('lib/src/screens/pdf_workspace_stylus_screen.dart')
        .readAsStringSync();
    final compact = source.replaceAll(RegExp(r'\s+'), '');

    expect(source, contains('panAxis: PanAxis.free'));
    expect(
      compact,
      contains('boundaryMargin:EdgeInsets.all(_mobile?320.0:120.0'),
    );
    expect(source, contains('onInteractionStart: (details)'));
    expect(source, contains('onInteractionUpdate: (details)'));
    expect(source, contains('_zoomAnchorLocal = details.localFocalPoint'));
    expect(source, contains('_effectiveZoomLocalAnchor()'));
    expect(source, contains('zoomOnLocalPosition('));
    expect(source, contains('zoomUpOnLocalPosition('));
    expect(source, contains('zoomDownOnLocalPosition('));
    expect(source, isNot(contains('setZoom(_controller.centerPosition')));
  });
}

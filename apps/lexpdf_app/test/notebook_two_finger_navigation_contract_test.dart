import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('notebook keeps stylus drawing and two-finger navigation separate', () {
    final navigator = File(
      'lib/src/widgets/notebook_two_finger_navigation_region.dart',
    ).readAsStringSync();
    final ink = File('lib/src/widgets/ink_canvas.dart').readAsStringSync();
    final notebook = File(
      'lib/src/screens/stylus_notebook_editor_screen.dart',
    ).readAsStringSync();

    expect(navigator, contains('PointerDeviceKind.touch'));
    expect(navigator, contains('_touchPositions.length >= 2'));
    expect(navigator, contains('currentDistance / _startDistance'));
    expect(navigator, contains('controller.toScene(focal)'));
    expect(
      navigator,
      contains('currentFocal.dx - _startSceneFocal.dx * targetScale'),
    );
    expect(
      navigator,
      contains('currentFocal.dy - _startSceneFocal.dy * targetScale'),
    );
    expect(navigator, contains('widget.onNavigationChanged?.call(true)'));
    expect(navigator, contains('widget.onNavigationChanged?.call(false)'));

    expect(ink, contains('NotebookTwoFingerNavigationRegion('));
    expect(ink, contains('_twoFingerNavigating'));
    expect(ink, contains('_activePoints.clear()'));
    expect(ink, contains('if (_twoFingerNavigating) return;'));
    expect(ink, contains('PointerDeviceKind.stylus'));
    expect(ink, contains('PointerDeviceKind.invertedStylus'));

    expect(notebook, contains('InteractiveViewer('));
    expect(notebook, contains('panEnabled: false'));
    expect(notebook, contains('scaleEnabled: false'));
    expect(notebook, contains('transformationController: _transform'));
  });
}

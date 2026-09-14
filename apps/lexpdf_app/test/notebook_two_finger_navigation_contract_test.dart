import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('notebook keeps one-finger tools and two-finger navigation separate', () {
    final navigator = File(
      'lib/src/widgets/notebook_two_finger_navigation_region.dart',
    ).readAsStringSync();
    final ink = File('lib/src/widgets/ink_canvas.dart').readAsStringSync();
    final text = File(
      'lib/src/widgets/notebook_rich_document_surface.dart',
    ).readAsStringSync();
    final objects = File(
      'lib/src/widgets/notebook_object_layer.dart',
    ).readAsStringSync();
    final notebook = File(
      'lib/src/screens/layered_notebook_screen.dart',
    ).readAsStringSync();

    expect(navigator, contains('PointerDeviceKind.touch'));
    expect(navigator, contains('_touchPositions.length >= 2'));
    expect(navigator, contains('currentDistance / _startDistance'));
    expect(navigator, contains('controller.toScene(focal)'));
    expect(navigator, contains('currentFocal.dx - _startSceneFocal.dx * targetScale'));
    expect(navigator, contains('currentFocal.dy - _startSceneFocal.dy * targetScale'));
    expect(navigator, contains('widget.onNavigationChanged?.call(true)'));
    expect(navigator, contains('widget.onNavigationChanged?.call(false)'));
    expect(navigator, contains('_viewer?.onInteractionEnd?.call'));

    expect(ink, contains('NotebookTwoFingerNavigationRegion('));
    expect(ink, contains('_twoFingerNavigating'));
    expect(ink, contains('_activePoints.clear()'));
    expect(ink, contains('if (_twoFingerNavigating) return;'));

    expect(text, contains('NotebookTwoFingerNavigationRegion('));
    expect(text, contains('ignoring: !widget.enabled || _twoFingerNavigating'));
    expect(text, contains('_restoreFocusAfterNavigation'));

    expect(objects, contains('NotebookTwoFingerNavigationRegion('));
    expect(objects, contains('if (_twoFingerNavigating) return;'));
    expect(objects, contains('ignoring: !widget.enabled || _twoFingerNavigating'));

    // The hand tool keeps the native InteractiveViewer behavior for one-finger
    // navigation. Other modes rely on the dedicated two-finger regions above.
    expect(notebook, contains('panEnabled: _handMode'));
    expect(notebook, contains('scaleEnabled: _handMode'));
  });
}

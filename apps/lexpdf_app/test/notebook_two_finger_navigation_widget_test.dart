import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexpdf_app/src/widgets/notebook_two_finger_navigation_region.dart';

void main() {
  testWidgets('two touch pointers pan and zoom around their focal point', (
    tester,
  ) async {
    final controller = TransformationController();
    final navigationStates = <bool>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              height: 420,
              child: InteractiveViewer(
                transformationController: controller,
                minScale: 0.25,
                maxScale: 4,
                panEnabled: false,
                scaleEnabled: false,
                child: NotebookTwoFingerNavigationRegion(
                  active: true,
                  onNavigationChanged: navigationStates.add,
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final region = find.byType(NotebookTwoFingerNavigationRegion);
    final rect = tester.getRect(region);
    final center = rect.center;

    final first = await tester.createGesture(
      pointer: 1,
      kind: PointerDeviceKind.touch,
    );
    await first.down(center + const Offset(-45, 0));
    await first.moveBy(const Offset(12, 8));
    await tester.pump();

    // One finger remains available to the active notebook tool.
    expect(controller.value.getMaxScaleOnAxis(), closeTo(1, 0.0001));
    expect(controller.value.storage[12], closeTo(0, 0.0001));
    expect(controller.value.storage[13], closeTo(0, 0.0001));

    final second = await tester.createGesture(
      pointer: 2,
      kind: PointerDeviceKind.touch,
    );
    await second.down(center + const Offset(45, 0));
    await tester.pump();

    await first.moveTo(center + const Offset(-85, 20));
    await second.moveTo(center + const Offset(85, 20));
    await tester.pump();

    final scaleAfterPinch = controller.value.getMaxScaleOnAxis();
    expect(scaleAfterPinch, greaterThan(1.5));

    final xBeforePan = controller.value.storage[12];
    final yBeforePan = controller.value.storage[13];
    await first.moveBy(const Offset(30, 35));
    await second.moveBy(const Offset(30, 35));
    await tester.pump();

    expect(controller.value.storage[12], isNot(closeTo(xBeforePan, 0.001)));
    expect(controller.value.storage[13], isNot(closeTo(yBeforePan, 0.001)));

    await second.up();
    await first.up();
    await tester.pump();

    expect(navigationStates, containsAllInOrder(<bool>[true, false]));
  });

  testWidgets('active stylus prevents touch navigation', (tester) async {
    final controller = TransformationController();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              height: 420,
              child: InteractiveViewer(
                transformationController: controller,
                minScale: 0.25,
                maxScale: 4,
                panEnabled: false,
                scaleEnabled: false,
                child: const NotebookTwoFingerNavigationRegion(
                  active: true,
                  child: SizedBox.expand(),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final rect = tester.getRect(find.byType(NotebookTwoFingerNavigationRegion));
    final center = rect.center;

    final stylus = await tester.createGesture(
      pointer: 10,
      kind: PointerDeviceKind.stylus,
    );
    await stylus.down(center);

    final first = await tester.createGesture(
      pointer: 11,
      kind: PointerDeviceKind.touch,
    );
    final second = await tester.createGesture(
      pointer: 12,
      kind: PointerDeviceKind.touch,
    );
    await first.down(center + const Offset(-40, 0));
    await second.down(center + const Offset(40, 0));
    await first.moveTo(center + const Offset(-100, 40));
    await second.moveTo(center + const Offset(100, 40));
    await tester.pump();

    expect(controller.value.getMaxScaleOnAxis(), closeTo(1, 0.0001));
    expect(controller.value.storage[12], closeTo(0, 0.0001));
    expect(controller.value.storage[13], closeTo(0, 0.0001));

    await second.up();
    await first.up();
    await stylus.up();
  });
}

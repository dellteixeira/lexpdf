import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

import '../lib/src/widgets/pdf_android_finger_navigation_region.dart';

void main() {
  testWidgets('one finger pans and two fingers pinch without changing tools', (
    tester,
  ) async {
    final controller = _FakePdfViewerController();
    final navigationStates = <bool>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox.expand(
            child: PdfAndroidFingerNavigationRegion(
              active: true,
              controller: controller,
              onNavigationChanged: navigationStates.add,
              child: const ColoredBox(color: Colors.white),
            ),
          ),
        ),
      ),
    );

    final finger = await tester.createGesture(kind: PointerDeviceKind.touch);
    await finger.down(const Offset(200, 300));
    await finger.moveTo(const Offset(235, 250));
    await tester.pump();

    expect(controller.translation.dx.abs(), greaterThan(1));
    expect(controller.translation.dy.abs(), greaterThan(1));
    await finger.up();
    await tester.pump();

    controller.reset();

    final first = await tester.createGesture(kind: PointerDeviceKind.touch);
    final second = await tester.createGesture(kind: PointerDeviceKind.touch);
    await first.down(const Offset(150, 300));
    await second.down(const Offset(250, 300));
    await first.moveTo(const Offset(100, 300));
    await second.moveTo(const Offset(300, 300));
    await tester.pump();

    expect(controller.currentZoom, greaterThan(1.4));
    await first.up();
    await second.up();
    await tester.pump();

    expect(navigationStates, containsAllInOrder(<bool>[true, false, true, false]));
  });

  testWidgets('active S Pen blocks palm touch until fingers are placed again', (
    tester,
  ) async {
    final controller = _FakePdfViewerController();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox.expand(
            child: PdfAndroidFingerNavigationRegion(
              active: true,
              controller: controller,
              child: const ColoredBox(color: Colors.white),
            ),
          ),
        ),
      ),
    );

    final stylus = await tester.createGesture(kind: PointerDeviceKind.stylus);
    final palm = await tester.createGesture(kind: PointerDeviceKind.touch);

    await stylus.down(const Offset(180, 260));
    await palm.down(const Offset(260, 320));
    await palm.moveTo(const Offset(310, 240));
    await tester.pump();

    expect(controller.currentZoom, 1);
    expect(controller.translation, Offset.zero);

    await stylus.up();
    await palm.moveTo(const Offset(340, 200));
    await tester.pump();

    // The palm contact that began while the pen was down stays blocked.
    expect(controller.translation, Offset.zero);
    await palm.up();

    final freshFinger = await tester.createGesture(kind: PointerDeviceKind.touch);
    await freshFinger.down(const Offset(250, 300));
    await freshFinger.moveTo(const Offset(285, 250));
    await tester.pump();

    expect(controller.translation.dx.abs(), greaterThan(1));
    expect(controller.translation.dy.abs(), greaterThan(1));
    await freshFinger.up();
  });
  testWidgets('single tap toggles UI callback but drag pinch and stylus do not', (
    tester,
  ) async {
    final controller = _FakePdfViewerController();
    var taps = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox.expand(
            child: PdfAndroidFingerNavigationRegion(
              active: true,
              controller: controller,
              onSingleTap: () => taps++,
              child: const ColoredBox(color: Colors.white),
            ),
          ),
        ),
      ),
    );

    final tap = await tester.createGesture(kind: PointerDeviceKind.touch);
    await tap.down(const Offset(180, 260));
    await tap.up();
    await tester.pump();
    expect(taps, 1);

    final drag = await tester.createGesture(kind: PointerDeviceKind.touch);
    await drag.down(const Offset(180, 260));
    await drag.moveTo(const Offset(230, 320));
    await drag.up();
    await tester.pump();
    expect(taps, 1);

    final first = await tester.createGesture(kind: PointerDeviceKind.touch);
    final second = await tester.createGesture(kind: PointerDeviceKind.touch);
    await first.down(const Offset(140, 260));
    await second.down(const Offset(240, 260));
    await first.up();
    await second.up();
    await tester.pump();
    expect(taps, 1);

    final stylus = await tester.createGesture(kind: PointerDeviceKind.stylus);
    await stylus.down(const Offset(180, 260));
    await stylus.up();
    await tester.pump();
    expect(taps, 1);
  });

}

class _FakePdfViewerController extends PdfViewerController {
  Matrix4 _matrix = Matrix4.identity();

  @override
  bool get isReady => true;

  @override
  Matrix4 get value => _matrix;

  @override
  set value(Matrix4 newValue) {
    _matrix = newValue.clone();
  }

  @override
  double get currentZoom => _matrix.getMaxScaleOnAxis();

  @override
  double get minScale => 0.25;

  @override
  double get maxScale => 4;

  Offset get translation => Offset(_matrix.storage[12], _matrix.storage[13]);

  void reset() {
    _matrix = Matrix4.identity();
  }

  @override
  void stopInteractiveViewerAnimation() {}

  @override
  Matrix4 makeMatrixInSafeRange(
    Matrix4 newValue, {
    bool forceClamp = false,
  }) => newValue.clone();

  @override
  Future<void> zoomOnLocalPosition({
    required Offset localPosition,
    required double newZoom,
    Duration duration = const Duration(milliseconds: 200),
  }) async {
    final oldZoom = currentZoom;
    final ratio = oldZoom == 0 ? 1.0 : newZoom / oldZoom;
    final oldTranslation = translation;
    final newTranslation = Offset(
      localPosition.dx - (localPosition.dx - oldTranslation.dx) * ratio,
      localPosition.dy - (localPosition.dy - oldTranslation.dy) * ratio,
    );

    _matrix = Matrix4.identity()
      ..setEntry(0, 0, newZoom)
      ..setEntry(1, 1, newZoom)
      ..setEntry(0, 3, newTranslation.dx)
      ..setEntry(1, 3, newTranslation.dy);
  }
}

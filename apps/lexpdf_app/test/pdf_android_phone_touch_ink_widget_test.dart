import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

import '../lib/src/core/ink/ink_models.dart';
import '../lib/src/core/ink/pdf_ink_models.dart';
import '../lib/src/widgets/pdf_android_finger_navigation_region.dart';
import '../lib/src/widgets/pdf_android_touch_input_policy.dart';
import '../lib/src/widgets/pdf_stylus_page_overlay.dart';

void main() {
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    PdfAndroidTouchInputPolicy.reset();
  });

  tearDown(() {
    PdfAndroidTouchInputPolicy.reset();
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('compact Android phone uses one finger as ink', (tester) async {
    final completed = <PdfInkStroke>[];

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(400, 800)),
          child: Scaffold(
            body: SizedBox(
              width: 400,
              height: 700,
              child: PdfStylusPageOverlay(
                documentId: 'doc',
                pageNumber: 1,
                strokes: const <PdfInkStroke>[],
                enabled: true,
                tool: InkTool.pen,
                colorValue: 0xFF000000,
                strokeWidth: 3,
                eraserMode: false,
                onStrokeCompleted: completed.add,
                onEraseApplied: (_) {},
              ),
            ),
          ),
        ),
      ),
    );

    expect(PdfAndroidTouchInputPolicy.compactPhoneInkActive, isTrue);

    final finger = await tester.createGesture(kind: PointerDeviceKind.touch);
    await finger.down(const Offset(80, 120));
    await finger.moveTo(const Offset(140, 180));
    await finger.moveTo(const Offset(180, 220));
    await finger.up();
    await tester.pump();

    expect(completed, hasLength(1));
    expect(completed.single.points.length, greaterThanOrEqualTo(3));
  });

  testWidgets('large Android tablet keeps touch out of ink but S Pen writes', (
    tester,
  ) async {
    final completed = <PdfInkStroke>[];

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(800, 1200)),
          child: Scaffold(
            body: SizedBox(
              width: 500,
              height: 600,
              child: PdfStylusPageOverlay(
                documentId: 'doc',
                pageNumber: 1,
                strokes: const <PdfInkStroke>[],
                enabled: true,
                tool: InkTool.pen,
                colorValue: 0xFF000000,
                strokeWidth: 3,
                eraserMode: false,
                onStrokeCompleted: completed.add,
                onEraseApplied: (_) {},
              ),
            ),
          ),
        ),
      ),
    );

    expect(PdfAndroidTouchInputPolicy.compactPhoneInkActive, isFalse);

    final finger = await tester.createGesture(kind: PointerDeviceKind.touch);
    await finger.down(const Offset(80, 120));
    await finger.moveTo(const Offset(150, 200));
    await finger.up();
    await tester.pump();
    expect(completed, isEmpty);

    final sPen = await tester.createGesture(kind: PointerDeviceKind.stylus);
    await sPen.down(const Offset(100, 140));
    await sPen.moveTo(const Offset(170, 210));
    await sPen.moveTo(const Offset(210, 250));
    await sPen.up();
    await tester.pump();

    expect(completed, hasLength(1));
  });

  testWidgets('compact phone reserves two fingers for PDF navigation', (
    tester,
  ) async {
    final controller = _FakePdfViewerController();
    PdfAndroidTouchInputPolicy.compactPhoneInkActive = true;

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

    final first = await tester.createGesture(kind: PointerDeviceKind.touch);
    await first.down(const Offset(150, 300));
    await first.moveTo(const Offset(190, 250));
    await tester.pump();

    // One finger is reserved for Caneta/Marca-texto/Borracha on compact phones.
    expect(controller.translation, Offset.zero);

    final second = await tester.createGesture(kind: PointerDeviceKind.touch);
    await second.down(const Offset(270, 300));
    await first.moveTo(const Offset(110, 280));
    await second.moveTo(const Offset(320, 320));
    await tester.pump();

    expect(PdfAndroidTouchInputPolicy.multiTouchNavigationActive, isTrue);
    expect(controller.currentZoom, greaterThan(1));

    await second.up();
    await first.moveTo(const Offset(130, 240));
    await tester.pump();

    // After a two-finger gesture starts, the remaining finger stays navigation
    // until the full sequence ends; it must not resume a partial ink stroke.
    expect(controller.translation.distance, greaterThan(1));

    await first.up();
    await tester.pump();
    expect(PdfAndroidTouchInputPolicy.multiTouchNavigationActive, isFalse);
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

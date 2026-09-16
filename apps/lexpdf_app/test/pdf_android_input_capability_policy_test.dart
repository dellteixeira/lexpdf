import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/src/widgets/pdf_android_touch_input_policy.dart';

void main() {
  testWidgets('touch-only Android tablet can use one-finger ink', (tester) async {
    await _withAndroidPlatform(() async {
      PdfAndroidTouchInputPolicy.setStylusHardwareAvailable(false);
      late BuildContext captured;

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(size: Size(900, 1400)),
            child: Builder(
              builder: (context) {
                captured = context;
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      );

      PdfAndroidTouchInputPolicy.configureInk(
        context: captured,
        inkEnabled: true,
      );
      expect(PdfAndroidTouchInputPolicy.touchInkActive, isTrue);
    });
  });

  testWidgets('active-stylus phone keeps fingers reserved for navigation', (
    tester,
  ) async {
    await _withAndroidPlatform(() async {
      PdfAndroidTouchInputPolicy.setStylusHardwareAvailable(true);
      late BuildContext captured;

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(size: Size(400, 800)),
            child: Builder(
              builder: (context) {
                captured = context;
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      );

      PdfAndroidTouchInputPolicy.configureInk(
        context: captured,
        inkEnabled: true,
      );
      expect(PdfAndroidTouchInputPolicy.touchInkActive, isFalse);
    });
  });

  test('runtime stylus contact upgrades the automatic capability signal', () {
    PdfAndroidTouchInputPolicy.reset();
    PdfAndroidTouchInputPolicy.setStylusHardwareAvailable(false);
    PdfAndroidTouchInputPolicy.touchInkActive = true;

    PdfAndroidTouchInputPolicy.registerStylusContact();

    expect(PdfAndroidTouchInputPolicy.stylusHardwareAvailable, isTrue);
    expect(PdfAndroidTouchInputPolicy.touchInkActive, isFalse);
    PdfAndroidTouchInputPolicy.reset();
  });

  test('Android runner exposes native stylus capability channel', () {
    final source = File(
      'android/app/src/main/kotlin/com/lexpdf/lexpdf_app/MainActivity.kt',
    ).readAsStringSync();
    final router = File(
      'lib/src/widgets/pdf_android_finger_navigation_region.dart',
    ).readAsStringSync();

    expect(source, contains('lexpdf/input_capabilities'));
    expect(source, contains('InputDevice.SOURCE_STYLUS'));
    expect(source, contains('SOURCE_BLUETOOTH_STYLUS'));
    expect(source, contains('"hasStylus"'));
    expect(router, contains("invokeMethod<bool>('hasStylus')"));
    expect(router, contains('registerStylusContact()'));
  });
}

Future<void> _withAndroidPlatform(Future<void> Function() body) async {
  PdfAndroidTouchInputPolicy.reset();
  debugDefaultTargetPlatformOverride = TargetPlatform.android;
  try {
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = null;
    PdfAndroidTouchInputPolicy.reset();
  }
}

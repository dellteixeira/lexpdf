import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Shared Android PDF input policy.
///
/// The policy prefers real device capability information when the Android
/// runner can enumerate an attached stylus source. If capability probing is
/// unavailable, it falls back to the validated phone/tablet size heuristic.
/// Runtime stylus contacts also upgrade the capability signal immediately.
///
/// This keeps the two important contracts together:
/// - active-stylus devices: stylus writes while touch navigates;
/// - touch-only devices: one finger can operate ink tools and two fingers
///   promote the whole sequence to PDF pan/pinch navigation.
class PdfAndroidTouchInputPolicy {
  PdfAndroidTouchInputPolicy._();

  static const double compactPhoneShortestSide = 600;

  static bool touchInkActive = false;
  static bool multiTouchNavigationActive = false;
  static bool? stylusHardwareAvailable;

  // Compatibility alias retained for the existing overlay/tests while input
  // ownership is no longer determined only by screen size.
  static bool get compactPhoneInkActive => touchInkActive;
  static set compactPhoneInkActive(bool value) => touchInkActive = value;

  static bool isCompactAndroidPhone(BuildContext context) =>
      defaultTargetPlatform == TargetPlatform.android &&
      MediaQuery.sizeOf(context).shortestSide < compactPhoneShortestSide;

  static void setStylusHardwareAvailable(bool? available) {
    stylusHardwareAvailable = available;
    if (available == true) {
      touchInkActive = false;
    }
  }

  static void registerStylusContact() {
    stylusHardwareAvailable = true;
    touchInkActive = false;
  }

  static bool shouldUseTouchForInk({
    required BuildContext context,
    required bool inkEnabled,
  }) {
    if (!inkEnabled || defaultTargetPlatform != TargetPlatform.android) {
      return false;
    }

    final hardware = stylusHardwareAvailable;
    if (hardware != null) {
      return !hardware;
    }

    // Conservative fallback for environments where native capability probing
    // is unavailable (tests, unusual Android embeddings, early startup).
    return isCompactAndroidPhone(context);
  }

  static void configureInk({
    required BuildContext context,
    required bool inkEnabled,
  }) {
    touchInkActive = shouldUseTouchForInk(
      context: context,
      inkEnabled: inkEnabled,
    );
    if (!touchInkActive) {
      multiTouchNavigationActive = false;
    }
  }

  static void beginMultiTouchNavigation() {
    if (touchInkActive) {
      multiTouchNavigationActive = true;
    }
  }

  static void finishTouchSequence() {
    multiTouchNavigationActive = false;
  }

  static void reset({bool resetCapability = true}) {
    touchInkActive = false;
    multiTouchNavigationActive = false;
    if (resetCapability) {
      stylusHardwareAvailable = null;
    }
  }
}

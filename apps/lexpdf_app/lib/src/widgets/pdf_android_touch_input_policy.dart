import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Shared Android PDF input policy.
///
/// Compact Android phones commonly have no active stylus hardware, so a touch
/// contact must be usable as ink when an ink tool is selected. Larger Android
/// tablets retain the S Pen/stylus-first contract: touch remains navigation.
///
/// Once a second finger joins a compact-phone ink gesture, navigation owns the
/// whole touch sequence until every finger is lifted. This prevents a remaining
/// finger from resuming a half-finished ink stroke after pinch/pan.
class PdfAndroidTouchInputPolicy {
  PdfAndroidTouchInputPolicy._();

  static const double compactPhoneShortestSide = 600;

  static bool compactPhoneInkActive = false;
  static bool multiTouchNavigationActive = false;

  static bool isCompactAndroidPhone(BuildContext context) =>
      defaultTargetPlatform == TargetPlatform.android &&
      MediaQuery.sizeOf(context).shortestSide < compactPhoneShortestSide;

  static void configureInk({
    required BuildContext context,
    required bool inkEnabled,
  }) {
    compactPhoneInkActive =
        inkEnabled && isCompactAndroidPhone(context);
    if (!compactPhoneInkActive) {
      multiTouchNavigationActive = false;
    }
  }

  static void beginMultiTouchNavigation() {
    if (compactPhoneInkActive) {
      multiTouchNavigationActive = true;
    }
  }

  static void finishTouchSequence() {
    multiTouchNavigationActive = false;
  }

  static void reset() {
    compactPhoneInkActive = false;
    multiTouchNavigationActive = false;
  }
}

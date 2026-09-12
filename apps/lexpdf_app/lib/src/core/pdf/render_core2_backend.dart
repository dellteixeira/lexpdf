import 'package:flutter/foundation.dart';

enum RenderCore2Backend {
  existingViewer,
  nativePrototype,
}

class RenderCore2BackendPolicy {
  const RenderCore2BackendPolicy._();

  static const String nativePrototypeDefine =
      'LEXPDF_RENDER_CORE2_NATIVE_PROTOTYPE';

  static RenderCore2Backend resolve({
    bool? forceNativePrototype,
    TargetPlatform? platform,
  }) {
    final effectivePlatform = platform ?? defaultTargetPlatform;
    final nativeRequested = forceNativePrototype ??
        const bool.fromEnvironment(
          nativePrototypeDefine,
          defaultValue: false,
        );

    if (nativeRequested && effectivePlatform == TargetPlatform.windows) {
      return RenderCore2Backend.nativePrototype;
    }

    return RenderCore2Backend.existingViewer;
  }

  static bool isNativePrototypeEnabled({
    bool? forceNativePrototype,
    TargetPlatform? platform,
  }) =>
      resolve(
        forceNativePrototype: forceNativePrototype,
        platform: platform,
      ) ==
      RenderCore2Backend.nativePrototype;
}

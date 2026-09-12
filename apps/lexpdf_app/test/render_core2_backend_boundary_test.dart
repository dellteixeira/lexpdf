import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexpdf_app/src/core/pdf/render_core2_backend.dart';

void main() {
  test('native prototype stays disabled by default', () {
    expect(
      RenderCore2BackendPolicy.resolve(
        forceNativePrototype: false,
        platform: TargetPlatform.windows,
      ),
      RenderCore2Backend.existingViewer,
    );
  });

  test('native prototype can only activate on Windows', () {
    expect(
      RenderCore2BackendPolicy.resolve(
        forceNativePrototype: true,
        platform: TargetPlatform.windows,
      ),
      RenderCore2Backend.nativePrototype,
    );
    expect(
      RenderCore2BackendPolicy.resolve(
        forceNativePrototype: true,
        platform: TargetPlatform.android,
      ),
      RenderCore2Backend.existingViewer,
    );
    expect(
      RenderCore2BackendPolicy.resolve(
        forceNativePrototype: true,
        platform: TargetPlatform.iOS,
      ),
      RenderCore2Backend.existingViewer,
    );
  });

  test('backend selection is explicit and side-effect free', () {
    expect(RenderCore2Backend.values, hasLength(2));
    expect(
      RenderCore2BackendPolicy.nativePrototypeDefine,
      'LEXPDF_RENDER_CORE2_NATIVE_PROTOTYPE',
    );
  });
}

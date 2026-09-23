import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lexpdf_app/src/core/pdf/huge_pdf_policy.dart';

void main() {
  test('Windows PDF viewer preserves full-resolution page rendering', () {
    final source = File(
      'lib/src/screens/pdf_workspace_stylus_screen.dart',
    ).readAsStringSync();
    final normalizedSource = source.replaceAll(RegExp(r'\s+'), ' ');

    expect(
      source,
      contains(
        'bool get _windows => defaultTargetPlatform == TargetPlatform.windows;',
      ),
    );
    expect(source, contains('useProgressiveLoading: true'));

    // Windows 10 uses the manual tiled page renderer and keeps pdfrx at a
    // lightweight backing resolution. Windows 11 retains the established
    // high-resolution one-pass path; non-Windows stays at the bounded default.
    expect(
      source,
      contains('onePassRenderingSizeThreshold: _windows10Tiles'),
    );
    expect(source, contains('? 1000'));
    expect(
      normalizedSource,
      contains(
        ': (_windows ? 6000 : HugePdfPolicy .androidOnePassThresholdForRecovery(',
      ),
    );
    expect(source, contains('if (_windows10Tiles) return 1.0;'));
    expect(source, contains('Windows10PdfTileOverlay('));

    // Keep this contract semantic rather than formatter-sensitive. Dart format
    // may wrap the boolean expression after the named argument colon.
    expect(
      normalizedSource,
      contains('loadPageDimensionsOnDemand: !_windows'),
    );
    expect(
      normalizedSource,
      isNot(contains('loadPageDimensionsOnDemand: !_windows && !_android')),
    );
    expect(
      normalizedSource,
      contains('enableLowResolutionPagePreview: !_windows && !_android'),
    );
    expect(source, isNot(contains('enableLowResolutionPagePreview: true')));
    expect(source, contains('HugePdfPolicy.viewerImageCacheBytesFor('));
    expect(source, contains('isWindows: _windows'));
    expect(
      source,
      contains('maxImageBytesCachedOnMemory:'),
    );
    expect(source, contains('_renderCacheBudget(context)'));

    final normalWindows = HugePdfPolicy.viewerImageCacheBytesFor(
      isWindows: true,
      pageCount: 200,
      viewportWidth: 2560,
      viewportHeight: 1440,
      devicePixelRatio: 1.5,
    );
    final largeWindows = HugePdfPolicy.viewerImageCacheBytesFor(
      isWindows: true,
      pageCount: 1600,
      viewportWidth: 2560,
      viewportHeight: 1440,
      devicePixelRatio: 1.5,
    );
    final hugeWindows = HugePdfPolicy.viewerImageCacheBytesFor(
      isWindows: true,
      pageCount: 5000,
      viewportWidth: 2560,
      viewportHeight: 1440,
      devicePixelRatio: 1.5,
    );

    expect(normalWindows, lessThanOrEqualTo(100 * 1024 * 1024));
    expect(largeWindows, lessThanOrEqualTo(84 * 1024 * 1024));
    expect(hugeWindows, lessThanOrEqualTo(72 * 1024 * 1024));
    expect(largeWindows, lessThan(normalWindows));
    expect(hugeWindows, lessThan(largeWindows));

    expect(
      normalizedSource,
      contains(
        'horizontalCacheExtent: _windows ? 1.0 : HugePdfPolicy.androidCacheExtentForRecovery(',
      ),
    );
    expect(
      normalizedSource,
      contains(
        'verticalCacheExtent: _windows ? 1.0 : HugePdfPolicy.androidCacheExtentForRecovery(',
      ),
    );
    expect(
      source,
      isNot(contains('if (_windows) _controller.invalidate();')),
    );
  });
}

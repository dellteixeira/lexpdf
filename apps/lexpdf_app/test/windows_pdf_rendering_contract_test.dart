import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Windows PDF viewer preserves full-resolution page rendering', () {
    final source = File(
      'lib/src/screens/pdf_workspace_stylus_screen.dart',
    ).readAsStringSync();

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
    expect(source, contains(': (_windows ? 6000 : 1400)'));
    expect(source, contains('if (_windows10Tiles) return 1.0;'));
    expect(source, contains('Windows10PdfTileOverlay('));

    expect(source, contains('loadPageDimensionsOnDemand: !_windows'));
    expect(source, contains('enableLowResolutionPagePreview: !_windows'));
    expect(source, isNot(contains('enableLowResolutionPagePreview: true')));
    expect(source, contains('? 100 * 1024 * 1024'));
    expect(source, contains('horizontalCacheExtent: _windows ? 1.0 : 0.30'));
    expect(source, contains('verticalCacheExtent: _windows ? 1.0 : 0.30'));
    expect(
      source,
      isNot(contains('if (_windows) _controller.invalidate();')),
    );
  });
}

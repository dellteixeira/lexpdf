import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Windows PDF viewer restores native pdfrx rendering defaults', () {
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
    expect(
      source,
      contains('onePassRenderingSizeThreshold: _windows ? 2000 : 1400'),
    );
    expect(source, contains('loadPageDimensionsOnDemand: !_windows'));
    expect(source, contains('enableLowResolutionPagePreview: true'));
    expect(source, contains('? 100 * 1024 * 1024'));
    expect(source, contains('horizontalCacheExtent: _windows ? 1.0 : 0.30'));
    expect(source, contains('verticalCacheExtent: _windows ? 1.0 : 0.30'));
    expect(
      source,
      isNot(contains('if (_windows) _controller.invalidate();')),
    );
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Windows PDF viewer avoids stale low-resolution redraw tiles', () {
    final source = File(
      'lib/src/screens/pdf_workspace_stylus_screen.dart',
    ).readAsStringSync();

    expect(source, contains('bool get _windows => defaultTargetPlatform == TargetPlatform.windows;'));
    expect(source, contains('useProgressiveLoading: !_windows'));
    expect(source, contains('onePassRenderingSizeThreshold: _windows ? 4096 : 1400'));
    expect(source, contains('enableLowResolutionPagePreview: !_windows'));
    expect(source, contains('? 128 * 1024 * 1024'));
    expect(source, contains('if (_windows) _controller.invalidate();'));
  });
}

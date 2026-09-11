import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Windows disables low-resolution PDF page preview', () {
    final source = File(
      'lib/src/screens/pdf_workspace_stylus_screen.dart',
    ).readAsStringSync();

    expect(source, contains('enableLowResolutionPagePreview: !_windows'));
    expect(source, isNot(contains('enableLowResolutionPagePreview: true')));
  });
}

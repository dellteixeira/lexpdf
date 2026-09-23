import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Windows disables low-resolution PDF page preview', () {
    final source = File(
      'lib/src/screens/pdf_workspace_stylus_screen.dart',
    ).readAsStringSync();
    final normalizedSource = source.replaceAll(RegExp(r'\s+'), ' ');

    expect(
      normalizedSource,
      contains('enableLowResolutionPagePreview: !_windows && !_android'),
    );
    expect(source, isNot(contains('enableLowResolutionPagePreview: true')));
  });
}

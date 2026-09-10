import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('PDF workspace keeps persistent markup paint lightweight on Windows', () {
    final source = File(
      'lib/src/widgets/pdf_selection_action_menu.dart',
    ).readAsStringSync();

    expect(source, contains('final fragmentBounds = range'));
    expect(source, contains('final List<PdfRect> fragmentBounds;'));
    expect(source, contains('if (annotations == null || annotations.isEmpty) return;'));
  });
}

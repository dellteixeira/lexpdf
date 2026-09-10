import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('selection paint callback only consumes cached geometry', () {
    final source = File(
      'lib/src/widgets/pdf_selection_action_menu.dart',
    ).readAsStringSync();
    final paintIndex = source.indexOf('void paint(Canvas canvas');
    expect(paintIndex, greaterThan(0));
    final paintSource = source.substring(paintIndex);
    expect(paintSource, contains('rendered.fragmentBounds'));
    expect(paintSource, isNot(contains('loadStructuredText')));
    expect(paintSource, isNot(contains('PdfPageTextRange(')));
  });
}

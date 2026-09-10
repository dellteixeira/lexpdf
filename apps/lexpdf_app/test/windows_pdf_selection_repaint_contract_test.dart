import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Windows PDF markup avoids expensive geometry work during repaint', () {
    final source = File(
      'lib/src/widgets/pdf_selection_action_menu.dart',
    ).readAsStringSync();

    final paintIndex = source.indexOf('void paint(Canvas canvas');
    final geometryIndex = source.indexOf('enumerateFragmentBoundingRects()');

    expect(geometryIndex, greaterThanOrEqualTo(0));
    expect(paintIndex, greaterThan(geometryIndex));

    final paintSource = source.substring(paintIndex);
    expect(paintSource, isNot(contains('enumerateFragmentBoundingRects()')));
    expect(paintSource, contains('defaultTargetPlatform == TargetPlatform.windows'));
    expect(paintSource, contains('if (!isWindows) paint.blendMode = BlendMode.multiply'));
  });
}

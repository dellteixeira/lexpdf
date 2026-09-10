import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Windows highlight path uses normal alpha composition', () {
    final source = File(
      'lib/src/widgets/pdf_selection_action_menu.dart',
    ).readAsStringSync();

    expect(source, contains('final isWindows = defaultTargetPlatform == TargetPlatform.windows;'));
    expect(source, contains('if (!isWindows) paint.blendMode = BlendMode.multiply;'));
    expect(source, contains('annotation.opacity * 0.78'));
  });
}

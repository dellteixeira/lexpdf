import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('all PDF text-selection surfaces open actions automatically', () {
    const paths = <String>[
      'lib/src/screens/pdf_workspace_stylus_screen.dart',
      'lib/src/screens/pdf_reader_screen.dart',
      'lib/src/screens/pdf_advanced_annotation_screen.dart',
      'lib/src/screens/pdf_navigation_screen.dart',
    ];

    for (final path in paths) {
      final source = File(path).readAsStringSync();
      expect(
        source,
        contains('showContextMenuAutomatically: true'),
        reason: '$path must show actions immediately when selection ends',
      );
      expect(
        source,
        contains('onTextSelectionChange:'),
        reason: '$path must refresh the selection overlay without another tap',
      );
      expect(
        source,
        contains('.invalidate();'),
        reason: '$path must invalidate the viewer after selection changes',
      );
    }
  });
}

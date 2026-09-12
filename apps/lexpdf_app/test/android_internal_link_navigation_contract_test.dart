import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android internal PDF links use fully measured deterministic navigation', () {
    final source = File('lib/src/screens/pdf_workspace_stylus_screen.dart')
        .readAsStringSync();

    expect(source, contains('bool get _android =>'));
    expect(
      source,
      contains('loadPageDimensionsOnDemand: !_windows && !_android'),
    );
    expect(source, contains('_goToInternalPdfDestination(dest)'));
    expect(source, contains('final targetPage = dest.pageNumber;'));
    expect(source, contains('pageNumber: targetPage'));
    expect(source, contains('anchor: PdfPageAnchor.top'));
    expect(source, contains('await _controller.goToDest(dest, duration: Duration.zero)'));
    expect(source, contains('currentPage != targetPage'));
    expect(source, isNot(contains('targetPage + 1')));
    expect(source, isNot(contains('targetPage - 1')));
  });
}

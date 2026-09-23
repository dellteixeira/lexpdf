import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android keeps lazy page dimensions with guarded internal-link navigation', () {
    final source = File('lib/src/screens/pdf_workspace_stylus_screen.dart')
        .readAsStringSync();
    final normalizedSource = source.replaceAll(RegExp(r'\s+'), ' ');

    expect(source, contains('bool get _android =>'));
    // Dart format may wrap this named argument across lines. Normalize
    // whitespace so the contract checks behavior, not source layout.
    expect(
      normalizedSource,
      contains('loadPageDimensionsOnDemand: !_windows'),
    );
    expect(source, isNot(contains('loadPageDimensionsOnDemand: !_windows && !_android')));
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

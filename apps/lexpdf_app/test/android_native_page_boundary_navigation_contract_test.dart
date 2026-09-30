import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('native Android reader turns pages only from an existing boundary', () {
    final source = File(
      'android/app/src/main/kotlin/com/lexpdf/lexpdf_app/NativePdfReaderActivity.kt',
    ).readAsStringSync();

    expect(source, contains('let singleTouchStartedAtTop = false;'));
    expect(source, contains('let singleTouchStartedAtBottom = false;'));
    expect(
      source,
      contains(
        'singleTouchStartedAtBottom =\n'
        '      stage.scrollTop + stage.clientHeight >= stage.scrollHeight - 3;',
      ),
    );
    expect(
      source,
      contains('dy < 0 && singleTouchStartedAtBottom && atBottom'),
    );
    expect(
      source,
      contains('dy > 0 && singleTouchStartedAtTop && atTop'),
    );

    // Ordinary reading swipes must not advance just because the zoom happens
    // to be close to 1x or because the page moved only a small amount.
    expect(source, isNot(contains('normalReadingScale')));
    expect(source, isNot(contains('barelyScrolled')));
  });
}

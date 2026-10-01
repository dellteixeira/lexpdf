import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Index and Close stay pinned in every Android orientation', () {
    final source = File(
      'android/app/src/main/kotlin/com/lexpdf/lexpdf_app/NativePdfReaderActivity.kt',
    ).readAsStringSync();

    expect(source, contains('val indexButton = button("Índice") { showOutlineDialog() }'));
    expect(source, contains('val closeButton = button("Fechar") { finish() }'));
    expect(source, contains('val pinnedNavigationRow = toolRow()'));
    expect(source, contains('val navigationScroller = HorizontalScrollView(this).apply'));
    expect(source, contains('pinnedNavigationRow.addView(indexButton)'));
    expect(source, contains('pinnedNavigationRow.addView(closeButton)'));

    // Essential commands must never become children of the scrolling navigation
    // row, otherwise rotation/narrow screens can hide them off-screen.
    expect(
      source,
      isNot(contains('navigationRow.addView(indexButton)')),
    );
    expect(
      source,
      isNot(contains('navigationRow.addView(closeButton)')),
    );
    expect(
      source,
      isNot(contains('val inkRow = if (landscape) navigationRow else toolRow()')),
    );

    final pinnedStart = source.indexOf('val pinnedNavigationRow = toolRow()');
    final pinnedEnd = source.indexOf('readerFrame = StylusRouterLayout(this)', pinnedStart);
    expect(pinnedStart, greaterThan(0));
    expect(pinnedEnd, greaterThan(pinnedStart));
    final pinnedBlock = source.substring(pinnedStart, pinnedEnd);
    expect(
      pinnedBlock.indexOf('navigationScroller,'),
      lessThan(pinnedBlock.indexOf('pinnedNavigationRow.addView(indexButton)')),
    );
    expect(
      pinnedBlock.indexOf('pinnedNavigationRow.addView(indexButton)'),
      lessThan(pinnedBlock.indexOf('pinnedNavigationRow.addView(closeButton)')),
    );
    expect(pinnedBlock, contains('root.addView(\n            inkRow,'));
    expect(source, contains('48.dp'));
    expect(source, contains('WindowInsetsCompat.Type.systemBars()'));
    expect(source, contains('requestDisallowInterceptTouchEvent(true)'));
  });
}

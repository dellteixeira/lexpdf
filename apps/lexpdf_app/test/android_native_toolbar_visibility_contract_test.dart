import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('portrait always exposes Index and Close next to scrolling navigation', () {
    final source = File(
      'android/app/src/main/kotlin/com/lexpdf/lexpdf_app/NativePdfReaderActivity.kt',
    ).readAsStringSync();

    expect(source, contains('val indexButton = button("Índice") { showOutlineDialog() }'));
    expect(source, contains('val closeButton = button("Fechar") { finish() }'));
    expect(source, contains('if (landscape) {\n            navigationRow.addView(indexButton)'));
    expect(source, contains('val pinnedNavigationRow = toolRow()'));
    expect(source, contains('val navigationScroller = HorizontalScrollView(this).apply'));
    expect(source, contains('pinnedNavigationRow.addView(indexButton)'));
    expect(source, contains('pinnedNavigationRow.addView(closeButton)'));

    // Navigation itself may overflow but Index/Close must not be its children
    // on portrait. Maintain the two existing 48dp rows and one in landscape.
    final portraitStart = source.indexOf('val pinnedNavigationRow = toolRow()');
    final portraitEnd = source.indexOf('readerFrame = StylusRouterLayout(this)', portraitStart);
    expect(portraitStart, greaterThan(0));
    expect(portraitEnd, greaterThan(portraitStart));
    final portraitBlock = source.substring(portraitStart, portraitEnd);
    expect(
      portraitBlock.indexOf('navigationScroller,'),
      lessThan(portraitBlock.indexOf('pinnedNavigationRow.addView(indexButton)')),
    );
    expect(
      portraitBlock.indexOf('pinnedNavigationRow.addView(indexButton)'),
      lessThan(portraitBlock.indexOf('pinnedNavigationRow.addView(closeButton)')),
    );
    expect(portraitBlock, contains('root.addView(\n                inkRow,'));
    expect(source, contains('48.dp'));
    expect(source, contains('WindowInsetsCompat.Type.systemBars()'));
    expect(source, contains('requestDisallowInterceptTouchEvent(true)'));
  });
}

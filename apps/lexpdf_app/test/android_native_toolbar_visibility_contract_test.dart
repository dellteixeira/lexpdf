import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android native reader keeps one ordered toolbar row in every orientation', () {
    final source = File(
      'android/app/src/main/kotlin/com/lexpdf/lexpdf_app/NativePdfReaderActivity.kt',
    ).readAsStringSync();

    expect(source, contains('val unifiedToolbarRow = toolRow()'));
    expect(source, contains('val toolbarScroller = HorizontalScrollView(this).apply'));
    expect(source, contains('Configuration.ORIENTATION_LANDSCAPE'));
    expect(source, contains('val compactToolbar ='));

    final previous = source.indexOf('unifiedToolbarRow.addView(button("‹")');
    final jump = source.indexOf('unifiedToolbarRow.addView(button("Ir")');
    final next = source.indexOf('unifiedToolbarRow.addView(button("›")');
    final search = source.indexOf('unifiedToolbarRow.addView(button("Buscar")');
    final index = source.indexOf('unifiedToolbarRow.addView(button("Índice")');
    final zoomOut = source.indexOf('unifiedToolbarRow.addView(button("−")');
    final zoomIn = source.indexOf('unifiedToolbarRow.addView(button("+")');
    final pen = source.indexOf('unifiedToolbarRow.addView(penButton)');
    final highlight = source.indexOf('unifiedToolbarRow.addView(highlighterButton)');
    final eraser = source.indexOf('unifiedToolbarRow.addView(eraserButton)');
    final undo = source.indexOf('unifiedToolbarRow.addView(button("Desfazer")');
    final redo = source.indexOf('unifiedToolbarRow.addView(button("Refazer")');
    final close = source.indexOf('unifiedToolbarRow.addView(button("Fechar")');

    for (final position in <int>[
      previous,
      jump,
      next,
      search,
      index,
      zoomOut,
      zoomIn,
      pen,
      highlight,
      eraser,
      undo,
      redo,
      close,
    ]) {
      expect(position, greaterThanOrEqualTo(0));
    }

    expect(previous, lessThan(jump));
    expect(jump, lessThan(next));
    expect(next, lessThan(search));
    expect(search, lessThan(index));
    expect(index, lessThan(zoomOut));
    expect(zoomOut, lessThan(zoomIn));
    expect(zoomIn, lessThan(pen));
    expect(pen, lessThan(highlight));
    expect(highlight, lessThan(eraser));
    expect(eraser, lessThan(undo));
    expect(undo, lessThan(redo));
    expect(redo, lessThan(close));

    // Regression guard: the toolbar must not be split into navigation and ink
    // rows, and Index/Close must not be visually detached as pinned siblings.
    expect(source, isNot(contains('val pinnedNavigationRow = toolRow()')));
    expect(source, isNot(contains('val navigationRow = toolRow()')));
    expect(source, isNot(contains('val inkRow = toolRow()')));
    expect(source, isNot(contains('pinnedNavigationRow.addView(indexButton)')));
    expect(source, isNot(contains('pinnedNavigationRow.addView(closeButton)')));

    expect(source, contains('FrameLayout.LayoutParams.WRAP_CONTENT'));
    expect(source, contains('WindowInsetsCompat.Type.systemBars()'));
    expect(source, contains('requestDisallowInterceptTouchEvent(true)'));
  });

  test('native search field follows Android light and dark system theme', () {
    final source = File(
      'android/app/src/main/kotlin/com/lexpdf/lexpdf_app/NativePdfReaderActivity.kt',
    ).readAsStringSync();

    expect(source, contains('Configuration.UI_MODE_NIGHT_MASK'));
    expect(source, contains('Configuration.UI_MODE_NIGHT_YES'));
    expect(source, contains('val searchBackground ='));
    expect(source, contains('val searchForeground ='));
    expect(source, contains('val searchSecondary ='));
    expect(source, contains('val searchAccent ='));
    expect(source, contains('setTextColor(searchForeground)'));
    expect(source, contains('setHintTextColor(searchSecondary)'));
    expect(
      source,
      contains('backgroundTintList = ColorStateList.valueOf(searchAccent)'),
    );
    expect(source, contains('setBackgroundColor(searchBackground)'));
  });
}

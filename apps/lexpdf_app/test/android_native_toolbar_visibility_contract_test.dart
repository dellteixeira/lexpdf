import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('small portrait uses fixed primary actions plus overflow menu', () {
    final source = File(
      'android/app/src/main/kotlin/com/lexpdf/lexpdf_app/NativePdfReaderActivity.kt',
    ).readAsStringSync();

    expect(source, contains('val screenWidthDp = resources.configuration.screenWidthDp'));
    expect(source, contains('val useOverflowMenu = !landscape && screenWidthDp < 600'));
    expect(source, contains('PopupMenu(this, anchor)'));
    expect(source, contains('button("⋮")'));
    expect(source, contains('contentDescription = "Mais opções"'));

    for (final item in <String>[
      'menu.add("Zoom −")',
      'menu.add("Zoom +")',
      'menu.add("Página inteira")',
      'menu.add("Selecionar texto")',
      'menu.add("Caneta")',
      'menu.add("Marca-texto")',
      'menu.add("Borracha")',
      'menu.add("Desfazer")',
      'menu.add("Refazer")',
      'menu.add("Fechar")',
    ]) {
      expect(source, contains(item));
    }

    expect(source, contains('unifiedToolbarRow.addView(button("Buscar")'));
    expect(source, contains('unifiedToolbarRow.addView(button("Índice")'));
    expect(source, contains('if (!useOverflowMenu) {'));
    expect(source, contains('val toolbarContainer: View ='));
    expect(source, contains('if (useOverflowMenu) {'));
  });

  test('large screens and landscape keep full single-row toolbar', () {
    final source = File(
      'android/app/src/main/kotlin/com/lexpdf/lexpdf_app/NativePdfReaderActivity.kt',
    ).readAsStringSync();

    expect(source, contains('Configuration.ORIENTATION_LANDSCAPE'));
    expect(source, contains('val unifiedToolbarRow = toolRow()'));
    expect(source, contains('HorizontalScrollView(this).apply'));
    expect(source, contains('button("Texto") { selectTextMode() }'));
    expect(source, contains('unifiedToolbarRow.addView(penButton)'));
    expect(source, contains('unifiedToolbarRow.addView(highlighterButton)'));
    expect(source, contains('unifiedToolbarRow.addView(eraserButton)'));
    expect(source, contains('unifiedToolbarRow.addView(button("Fechar")'));

    expect(source, isNot(contains('val pinnedNavigationRow = toolRow()')));
    expect(source, isNot(contains('val navigationRow = toolRow()')));
    expect(source, isNot(contains('val inkRow = toolRow()')));
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

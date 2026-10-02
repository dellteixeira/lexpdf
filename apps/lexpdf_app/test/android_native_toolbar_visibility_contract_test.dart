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
    expect(source, contains('toolbarContainer ='));
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

  test('reading-first shell auto-hides chrome without changing the renderer', () {
    final source = File(
      'android/app/src/main/kotlin/com/lexpdf/lexpdf_app/NativePdfReaderActivity.kt',
    ).readAsStringSync();

    expect(source, contains('private lateinit var readingPageIndicator: TextView'));
    expect(source, contains('private lateinit var toolbarContainer: View'));
    expect(source, contains('hideReaderChromeRunnable'));
    expect(source, contains('scheduleReaderChromeAutoHide()'));
    expect(source, contains('readerChromeHandler.postDelayed(hideReaderChromeRunnable, 3200L)'));
    expect(source, contains('toolbarContainer.visibility = if (visible) View.VISIBLE else View.GONE'));
    expect(source, contains('readingPageIndicator.visibility = if (visible) View.GONE else View.VISIBLE'));
    expect(source, contains('fun readerChromeTap()'));
    expect(source, contains('LexPdfBridge.readerChromeTap()'));
    expect(source, contains('target === canvas'));
    expect(source, contains('readingPageIndicator.text = label'));

    expect(source, contains('PDFDataRangeTransport'));
    expect(source, contains('private const val RANGE_CHUNK_SIZE = 512 * 1024'));
    expect(source, contains('keepPinchAnchorAtViewport('));
    expect(source, contains('ACTION_UNDO_MARKUP'));
    expect(source, contains('ACTION_REDO_MARKUP'));
    expect(source, isNot(contains('justify-content:center')));
  });

  test('reader exposes page vertical and horizontal navigation modes', () {
    final source = File(
      'android/app/src/main/kotlin/com/lexpdf/lexpdf_app/NativePdfReaderActivity.kt',
    ).readAsStringSync();

    expect(source, contains('private enum class ReaderViewMode'));
    expect(source, contains('ReaderViewMode.PAGE'));
    expect(source, contains('ReaderViewMode.CONTINUOUS_VERTICAL'));
    expect(source, contains('ReaderViewMode.CONTINUOUS_HORIZONTAL'));
    expect(source, contains('showReaderViewModeDialog()'));
    expect(source, contains('menu.add("Modo de leitura")'));
    expect(source, contains('button("Modo")'));
    expect(source, contains('"Contínuo vertical"'));
    expect(source, contains('"Contínuo horizontal"'));
    expect(source, contains('LexPDF.setViewMode('));
    expect(source, contains("readerViewMode === 'continuous_vertical'"));
    expect(source, contains("readerViewMode === 'continuous_horizontal'"));
    expect(source, contains("readerViewMode === 'page'"));
    expect(source, contains('singleTouchStartedAtBottom && atBottom'));
    expect(source, contains('singleTouchStartedAtTop && atTop'));
    expect(source, contains('dx < 0 && atRight'));
    expect(source, contains('dx > 0 && atLeft'));

    // Horizontal mode must not remove free pan or the focal pinch implementation.
    expect(source, contains('keepPinchAnchorAtViewport('));
    expect(source, contains('stage.scrollWidth - stage.clientWidth'));
    expect(source, contains('stage.scrollHeight - stage.clientHeight'));
  });

  test('reading intelligence persists theme margin fit width and view mode', () {
    final source = File(
      'android/app/src/main/kotlin/com/lexpdf/lexpdf_app/NativePdfReaderActivity.kt',
    ).readAsStringSync();

    expect(source, contains('private enum class ReaderTheme'));
    expect(source, contains('ReaderTheme.NORMAL'));
    expect(source, contains('ReaderTheme.NIGHT'));
    expect(source, contains('ReaderTheme.SEPIA'));
    expect(source, contains('READING_PREFS'));
    expect(source, contains('PREF_READER_VIEW_MODE'));
    expect(source, contains('PREF_READER_THEME'));
    expect(source, contains('PREF_READER_MARGIN_DP'));
    expect(source, contains('PREF_SMART_FIT_WIDTH'));
    expect(source, contains('loadReadingPreferences()'));
    expect(source, contains('saveReadingPreferences()'));
    expect(source, contains('showReadingPreferencesDialog()'));
    expect(source, contains('LexPDF.fitWidth()'));
    expect(source, contains('applyReadingPreferencesToViewer()'));
    expect(source, contains('LexPDF.applyReadingPreferences('));
    expect(source, contains("normalizedTheme === 'night'"));
    expect(source, contains("normalizedTheme === 'sepia'"));
    expect(source, contains("wrap.style.paddingLeft = safeMargin + 'px'"));
    expect(source, contains('smartFitWidthEnabled'));
    expect(source, contains('saveReadingPreferences()\n        super.onPause()'));
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

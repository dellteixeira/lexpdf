import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('selection mode exposes floating markup actions', () {
    final source = File(
      'lib/src/widgets/pdf_selection_action_menu.dart',
    ).readAsStringSync();

    for (final label in [
      'Recortar',
      'Colar',
      'Marca-texto',
      'Sublinhado',
      'Tachado',
      'Limpar seleção',
    ]) {
      expect(source, contains(label));
    }
    expect(source, contains('ContextMenuButtonType.copy'));
    expect(source, contains('getSelectedTextRanges'));
    expect(source, contains('TextAnnotationType.highlight'));
    expect(source, contains('TextAnnotationType.underline'));
    expect(source, contains('TextAnnotationType.strikeout'));
    expect(source, contains('BlendMode.multiply'));
  });

  test('workspace automatically opens selection menu and paints markup', () {
    final source = File(
      'lib/src/screens/pdf_workspace_stylus_screen.dart',
    ).readAsStringSync();

    expect(source, contains('buildContextMenu: _stylusMode == _StylusMode.selectText'));
    expect(source, contains('showContextMenuAutomatically: true'));

    // Normal renderer keeps the pdfrx page paint callback. Windows 10 tiled
    // rendering paints the same persisted markup above the manual page tiles,
    // avoiding duplicate painting into the low-DPI backing page.
    expect(source, contains('pagePaintCallbacks: _windows10Tiles'));
    expect(source, contains('? const []'));
    expect(source, contains(': [_selectionMenu.paint]'));
    expect(source, contains('_SelectionMarkupOverlayPainter('));
    expect(source, contains('menu: _selectionMenu'));

    expect(source, contains('_selectionMenu.load(document)'));
  });

  test('eraser has adjustable width and side-button shortcut', () {
    final workspace = File(
      'lib/src/screens/pdf_workspace_stylus_screen.dart',
    ).readAsStringSync();
    final overlay = File(
      'lib/src/widgets/pdf_stylus_page_overlay.dart',
    ).readAsStringSync();

    expect(workspace, contains('double _eraserWidth = 36.0'));
    expect(workspace, contains('Espessura da borracha'));
    expect(workspace, contains('eraserRadius: _eraserWidth / 2'));
    expect(overlay, contains('kPrimaryStylusButton'));
    expect(overlay, contains('kSecondaryStylusButton'));
    expect(overlay, contains('_stylusButtonPressed'));
    expect(overlay, contains('widget.eraserMode ||'));
  });
}

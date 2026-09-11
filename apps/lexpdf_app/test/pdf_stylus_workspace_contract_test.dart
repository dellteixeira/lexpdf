import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('unified workspace exposes explicit input modes on Android', () {
    final workspace = File(
      'lib/src/screens/pdf_workspace_stylus_screen.dart',
    ).readAsStringSync();

    expect(workspace, contains('_StylusMode.hand'));
    expect(workspace, contains('_StylusMode.selectText'));
    expect(workspace, contains('_StylusMode.note'));
    expect(workspace, contains('_StylusMode.pen'));
    expect(workspace, isNot(contains('_StylusMode.pencil')));
    expect(workspace, contains('_StylusMode.highlighter'));
    expect(workspace, contains('_StylusMode.eraser'));
    expect(workspace, contains('TargetPlatform.android'));
    expect(workspace, contains('? _StylusMode.pen'));
    expect(workspace, contains("'Selecionar'"));
    expect(workspace, contains("'Anotar'"));
    expect(workspace, contains("'Caneta'"));
    expect(workspace, isNot(contains("'Lápis'")));
    expect(workspace, contains("'Marca-texto'"));
    expect(workspace, contains("'Borracha'"));
    expect(
      workspace,
      contains('enabled: _stylusMode == _StylusMode.selectText'),
    );
    expect(workspace, contains('_stylusMode == _StylusMode.note'));
    expect(workspace, contains(': (!_inkMode || _mobile)'));
  });

  test('stylus overlay rejects touch and keeps pressure-aware vector ink', () {
    final overlay = File(
      'lib/src/widgets/pdf_stylus_page_overlay.dart',
    ).readAsStringSync();

    expect(overlay, contains('PointerDeviceKind.stylus'));
    expect(overlay, contains('PointerDeviceKind.invertedStylus'));
    expect(overlay, contains('PointerDeviceKind.mouse'));
    expect(overlay, isNot(contains('PointerDeviceKind.touch')));
    expect(overlay, contains('event.pressure'));
    expect(overlay, contains('event.tilt'));
    expect(overlay, contains('PdfInkEraser'));
    expect(overlay, contains('event.kind == PointerDeviceKind.invertedStylus'));
  });

  test('highlighter is translucent and preserves glyph contrast', () {
    final workspace = File(
      'lib/src/screens/pdf_workspace_stylus_screen.dart',
    ).readAsStringSync();
    final overlay = File(
      'lib/src/widgets/pdf_stylus_page_overlay.dart',
    ).readAsStringSync();

    expect(workspace, contains('InkTool.highlighter'));
    expect(workspace, contains('_inkWidth * 5.0'));
    expect(overlay, contains('InkTool.highlighter ? 0.24 : 1.0'));
    expect(overlay, contains('BlendMode.multiply'));
    expect(overlay, contains('paint.blendMode = BlendMode.multiply'));
  });

  test('PDF ink remains persisted and windowed for huge documents', () {
    final workspace = File(
      'lib/src/screens/pdf_workspace_stylus_screen.dart',
    ).readAsStringSync();

    expect(workspace, contains('LocalPdfInkStore(widget.store.db)'));
    expect(workspace, contains('HugePdfPolicy.overlayWindow'));
    expect(workspace, contains('_inkStore.listForPageRange'));
    expect(workspace, contains('_inkStore.addStroke'));
    expect(workspace, contains('_inkStore.replaceStrokeWithFragments'));
    expect(workspace, contains('_inkStore.deleteStroke'));
  });
}
